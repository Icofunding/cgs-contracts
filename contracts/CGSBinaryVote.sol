pragma solidity ^0.4.18;

import './util/SafeMath.sol';
import './interfaces/BinaryVoteCallback.sol';
import './interfaces/ERC20.sol';

/*
  Copyright (C) 2018 Icofunding S.L.

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

/// @title CGSBinaryVote contract
/// @author Icofunding
contract CGSBinaryVote {
  uint constant TIME_TO_VOTE = 7 days;
  uint constant TIME_TO_REVEAL = 3 days;

  using SafeMath for uint;

  /*
   * - SecretVote: Users deposit their CGS tokens and a hash of their vote.
   *   This stage last for TIME_TO_VOTE.
   * - RevealVote: Users must reveal their vote in the previous stage.
   *   This stage last for TIME_TO_REVEAL.
   * - Settlement: Users can withdraw their tokens with a bonus or penalization,
   *   depending on the outcome of the vote.
   */
  enum Stages {
    SecretVote,
    RevealVote,
    Settlement
  }

  struct Vote {
    uint date; // Timestamp when the claim is open
    Stages stage; // Current state of the vote
    uint votesYes; // Votes that the project is doing a proper use of the funds. Updated during Reveal stage
    uint votesNo; // Votes that the project is not doing a proper use of the funds. Updated during Reveal stage
    address callback; // The address to call when the vote ends
    uint totalVotes; // Total number of votes (at the moment of voting, no matter if revealed or not)
    mapping (address => bytes32) secretVotes; // Hashes of votes
    mapping (address => bool) revealedVotes; // Votes in plain text
    mapping (address => bool) hasRevealed; // True if the user has revealed his vote
    mapping (address => uint) userDeposits; // Amount of CGS tokens deposited for this vote.
  }

  Vote[] public votes; // Log of votes
  uint public numVotes; // Number of elements in the array votes

  address public cgsToken; // Address of the CGS token smart contract

  event ev_NewStage(uint indexed voteId, Stages stage);
  event ev_NewVote(uint indexed voteId, address callback);
  event ev_Vote(uint indexed voteId, address who, uint amount);
  event ev_Reveal(uint indexed voteId, address who, uint amount, bool value);
  event ev_Withdraw(uint indexed voteId, address who, uint amount);

  modifier atStage(uint voteId, Stages _stage) {
    require(votes[voteId].stage == _stage);

    _;
  }

  // Perform timed transitions.
  modifier timedTransitions(uint voteId) {
    Stages newStage = getStage(voteId);

    if(newStage != votes[voteId].stage) {
      setStage(voteId, newStage);
    }

    _;
  }

  /// @notice Creates a CGSBinaryVote smart contract
  /// @dev Creates a CGSBinaryVote smart contract.
  /// @param _cgsToken Address of the CGS token smart contract
  function CGSBinaryVote(address _cgsToken) public {
    cgsToken = _cgsToken;
  }

  /// @notice Starts a vote
  /// @dev Starts a vote
  /// @return the vote ID
  function startVote(address _callback) public returns(uint) {
    Vote memory newVote = Vote(now, Stages.SecretVote, 0, 0, _callback, 0);

    votes.push(newVote);
    numVotes++;

    ev_NewVote(numVotes-1, _callback);

    return numVotes-1;
  }

  /// @notice Deposits CGS tokens and vote. Should be executed after Token.Approve(...) or Token.increaseApproval(...)
  /// @dev Deposits CGS tokens and vote. Should be executed after Token.Approve(...) or Token.increaseApproval(...)
  /// @param voteId ID of the vote
  /// @param numTokens number of tokens used to vote
  /// @param secretVote Hash of the vote + salt
  function vote(uint voteId, uint numTokens, bytes32 secretVote)
    public
    timedTransitions(voteId)
    atStage(voteId, Stages.SecretVote)
    returns(bool)
  {
    // The voteId must exist
    require(voteId < numVotes);
    // It can only vote once per Vote
    require(votes[voteId].userDeposits[msg.sender] == 0);
    // You cannot vote with 0 tokens (?)
    require(numTokens > 0);
    // Enough tokens allowed
    require(numTokens <= ERC20(cgsToken).allowance(msg.sender, this));

    assert(ERC20(cgsToken).transferFrom(msg.sender, this, numTokens));

    votes[voteId].userDeposits[msg.sender] = numTokens;
    votes[voteId].secretVotes[msg.sender] = secretVote;

    votes[voteId].totalVotes = votes[voteId].totalVotes.add(numTokens);

    ev_Vote(voteId, msg.sender, numTokens);

    return true;
  }

  /// @notice Reveal the vote
  /// @dev Reveal the vote
  /// @param voteId ID of the vote
  /// @param salt Random salt used to vote
  function reveal(uint voteId, bytes32 salt)
    public
    timedTransitions(voteId)
    atStage(voteId, Stages.RevealVote)
    returns(bool)
  {
    // Only users who vote can reveal their vote
    require(votes[voteId].secretVotes[msg.sender].length > 0);
    // Check if the vote is already revealed
    require(!votes[voteId].hasRevealed[msg.sender]);

    // Check the vote as revealed
    votes[voteId].hasRevealed[msg.sender] = true;

    // Check if the user voted yes or no to update the results
    bool revealedvote = calculateRevealedVote(voteId, msg.sender, salt);

    votes[voteId].revealedVotes[msg.sender] = revealedvote;

    if(revealedvote) {
      // Vote true
      votes[voteId].votesYes = votes[voteId].votesYes.add(votes[voteId].userDeposits[msg.sender]);
    } else {
      // Vote false
      votes[voteId].votesNo = votes[voteId].votesNo.add(votes[voteId].userDeposits[msg.sender]);
    }

    ev_Reveal(voteId, msg.sender, votes[voteId].userDeposits[msg.sender], revealedvote);

    return true;
  }

  /// @notice Withdraws CGS tokens after bonus/penalization
  /// @dev Withdraws CGS tokens after bonus/penalization
  /// @param voteId ID of the vote
  function withdrawTokens(uint voteId)
    public
    timedTransitions(voteId)
    atStage(voteId, Stages.Settlement)
    returns(bool)
  {
    // Number of tokens to withdraw after penalization/bonus
    uint numTokens = tokensToWithdraw(voteId, msg.sender);

    // Check if the user has any withdrawal pending
    require(numTokens > 0);

    // Update balance
    votes[voteId].userDeposits[msg.sender] = 0;

    // Send tokens to the user
    assert(ERC20(cgsToken).transfer(msg.sender, numTokens));

    ev_Withdraw(voteId, msg.sender, numTokens);

    return true;
  }

  /// @notice Returns the actual stage of a vote
  /// @dev Returns the actual stage of a vote
  /// @param voteId ID of the votes
  /// @return the actual stage of a vote
  function getStage(uint voteId) public view returns(Stages) {
    Stages stage = Stages.SecretVote;

    if(now >= votes[voteId].date + TIME_TO_VOTE)
      stage = Stages.RevealVote;

    if(now >= votes[voteId].date + TIME_TO_VOTE + TIME_TO_REVEAL)
      stage = Stages.Settlement;

    return stage;
  }

  /// @notice Calculates the number of tokens to withdraw after a voting process
  /// @dev Calculates the number of tokens to withdraw after a voting process
  /// @param voteId ID of the vote
  /// @param who Address of the user
  /// @return number of tokens
  function tokensToWithdraw(uint voteId, address who) public view returns(uint) {
    // Number of tokens deposited by the user
    uint deposited = votes[voteId].userDeposits[who];
    // Did the vote succeed?
    bool voteResult = (votes[voteId].votesYes > votes[voteId].votesNo);
    // If the user revealed his vote and vote the same as the winner option
    bool userWon = votes[voteId].hasRevealed[who] && (voteResult == votes[voteId].revealedVotes[who]);

    uint numTokens;

    if(deposited == 0) {
      numTokens = 0;
    } else if(userWon) {
      // 20% of the tokens that voted the wrong option or not revealed are distributed among the winners
      uint bonus;
      if(voteResult) {
        // If the result is positive
        // bonus = ((votes[voteId].totalVotes - votes[voteId].votesYes) * 20) / 100;
        bonus = votes[voteId].totalVotes.sub(votes[voteId].votesYes).mul(20).div(100);

        // numTokens = deposited + bonus*deposited/votes[voteId].votesYes;
        numTokens = deposited.add( bonus.mul(deposited).div(votes[voteId].votesYes) );
      } else {
        // If the result is negative
        // bonus = ((votes[voteId].totalVotes - votes[voteId].votesNo) * 20) / 100;
        bonus = votes[voteId].totalVotes.sub(votes[voteId].votesNo).mul(20).div(100);

        // numTokens = deposited + bonus*deposited/votes[voteId].votesNo;
        numTokens = deposited.add( bonus.mul(deposited).div(votes[voteId].votesNo) );
      }
    } else {
      // Losers and people that did not revealed their vote lose 20% of their tokens
      // numTokens = deposited - (deposited*20)/100;
      numTokens = deposited.sub( deposited.mul(20).div(100) );
    }

    return numTokens;
  }

  /// @notice Synchronizes the stage of the contract
  /// @dev Synchronizes the stage of the contract
  /// @param voteId ID of the vote
  function wake(uint voteId) public timedTransitions(voteId) {
  }

  /// @notice Returns if the user has revealed his vote
  /// @dev Returns if the user has revealed his vote
  /// @param voteId ID of the vote
  /// @param who Address of the user
  /// @return true if the user has revealed his vote
  function hasUserRevealed(uint voteId, address who) public view returns(bool) {

    return votes[voteId].hasRevealed[who];
  }

  /// @notice Returns the revealed vote of the user
  /// @dev Returns the revealed vote of the user
  /// @param voteId ID of the vote
  /// @param who Address of the user
  /// @return the vote of the user
  function getRevealedVote(uint voteId, address who) public view returns(bool) {
    require(hasUserRevealed(voteId, who));

    return votes[voteId].revealedVotes[who];
  }

  /// @notice Returns amount of tokens deposited by a user in a vote
  /// @dev Returns amount of tokens deposited by a user in a vote
  /// @param voteId ID of the vote
  /// @param who Address of the user
  /// @return the amount of tokens deposited by a user in a vote
  function getUserDeposit(uint voteId, address who) public view returns(uint) {

    return votes[voteId].userDeposits[who];
  }

  /// @notice Checks if the vote can be revealed with the given data
  /// @dev Checks if the vote can be revealed with the given data
  /// @param voteId ID of the vote
  /// @param user Voter
  /// @param salt random salt used to vote
  /// @return what the user voted
  function canRevealVote(uint voteId, address user, bytes32 salt)
    public
    view
    returns(bool)
  {
    return checkReveal(voteId, user, true, salt) || checkReveal(voteId, user, false, salt);
  }

  /// @notice Computes the hash of the given data to calculate the revealed vote
  /// @dev Computes the hash of the given data to calculate the revealed vote
  /// @param voteId ID of the vote
  /// @param user Voter
  /// @param salt random salt used to vote
  /// @return what the user voted
  function calculateRevealedVote(uint voteId, address user, bytes32 salt)
    public
    view
    returns(bool)
  {
    bool revealedvote;
    // Check if the user voted yes or no to update the results
    if(checkReveal(voteId, user, true, salt)) {
      // Vote true
      revealedvote = true;
    } else if(checkReveal(voteId, user, false, salt)) {
      // Vote false
      revealedvote = false;
    } else {
      revert(); // Revert the tx if the reveal fails
    }

    return revealedvote;
  }

  /// @notice Returns how much time last the voting process
  /// @dev Returns how much time last the voting process
  /// @return how much time last the voting process
  function getVotingProcessDuration()
    public
    pure
    returns(uint)
  {
    return TIME_TO_VOTE + TIME_TO_REVEAL;
  }

  /// @notice Returns how much time last the vote phase
  /// @dev Returns how much time last the vote phase
  /// @return how much time last the vote phase
  function getVotePhaseDuration()
    public
    pure
    returns(uint)
  {
    return TIME_TO_VOTE;
  }

  /// @notice Returns how much time last the reveal phase
  /// @dev Returns how much time last the reveal phase
  /// @return how much time last the reveal phase
  function getRevealPhaseDuration()
    public
    pure
    returns(uint)
  {
    return TIME_TO_REVEAL;
  }

  /// @notice Computes the hash of the given data to check if the vote can be revealed
  /// @dev Computes the hash of the given data to check if the vote can be revealed
  /// @param voteId ID of the vote
  /// @param user Voter
  /// @param revealedVote What the user vote
  /// @param salt ID of the vote
  /// @return true if the vote can be revealed
  function checkReveal(uint voteId, address user, bool revealedVote, bytes32 salt)
    internal
    view
    returns(bool)
  {

    return keccak256(revealedVote, salt) == votes[voteId].secretVotes[user];
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param voteId ID of the vote
  /// @param _stage New stage
  function setStage(uint voteId, Stages _stage) private {
    votes[voteId].stage = _stage;

    newStageHandler(voteId, _stage);
  }

  /// @notice Handles the change to a new state
  /// @dev Handles the change to a new state
  /// @param voteId ID of the vote
  /// @param _stage New stage
  function newStageHandler(uint voteId, Stages _stage) private {
    // Executed only once
    if(_stage == Stages.Settlement)
      finalizeVote(voteId); // It is executed only once

    ev_NewStage(voteId, _stage);
  }

  /// @notice Count the votes and calls BinaryVoteCallback to inform of the result. it is executed only once.
  /// @dev Count the votes and calls BinaryVoteCallback to inform of the result. it is executed only once.
  /// @param voteId ID of the vote
  function finalizeVote(uint voteId) private timedTransitions(voteId) atStage(voteId, Stages.Settlement) {
      if(votes[voteId].votesYes > votes[voteId].votesNo)
        BinaryVoteCallback(votes[voteId].callback).binaryVoteResult(voteId, true);
      else
        BinaryVoteCallback(votes[voteId].callback).binaryVoteResult(voteId, false);
  }
}
