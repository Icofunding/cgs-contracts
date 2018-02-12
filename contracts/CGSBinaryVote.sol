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
contract CGSBinaryVote is SafeMath {
  uint constant TIME_TO_VOTE = 7 days;
  uint constant TIME_TO_REVEAL = 3 days;

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
    mapping (address => bytes32) secretVotes; // Hashes of votes
    mapping (address => bool) revealedVotes; // Votes in plain text
    mapping (address => bool) hasRevealed; // True if the user has revealed is vote
    mapping (address => uint) userDeposits; // Amount of CGS tokens deposited for this vote.
  }

  Vote[] public votes; // Log of votes
  uint public numVotes; // Number of elements in the array votes

  address public cgsToken; // Address of the CGS token smart contract

  event ev_NewStage(uint indexed voteId, Stages stage);
  event ev_NewVote(uint indexed voteId, address callback);
  event ev_Vote(uint indexed voteId, address who, uint amount);
  event ev_Reveal(uint indexed voteId, address who, uint amount, bool value);

  modifier atStage(uint voteId, Stages _stage) {
    require(votes[voteId].stage == _stage);

    _;
  }

  // Perform timed transitions.
  modifier timedTransitions(uint voteId) {
    Stages newStage = getStage(voteId);

    if(newStage != votes[voteId].stage) {
      setStage(voteId, newStage);

      // Executed only once, when the Settlement stage is set
      if(newStage == Stages.Settlement)
        finalizeVote(voteId);
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
    Vote memory newVote = Vote(now, Stages.SecretVote, 0, 0, _callback);

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
    if(checkReveal(voteId, msg.sender, true, salt)) {
      // Vote true
      votes[voteId].revealedVotes[msg.sender] = true;
      votes[voteId].votesYes += votes[voteId].userDeposits[msg.sender];

      ev_Reveal(voteId, msg.sender, votes[voteId].userDeposits[msg.sender], true);
    } else if(checkReveal(voteId, msg.sender, false, salt)) {
      // Vote false
      votes[voteId].revealedVotes[msg.sender] = false;
      votes[voteId].votesNo += votes[voteId].userDeposits[msg.sender];

      ev_Reveal(voteId, msg.sender, votes[voteId].userDeposits[msg.sender], false);
    } else
      revert(); // Revert the tx if the reveal fails

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
    uint deposited = votes[voteId].userDeposits[msg.sender];
    // Check if the user has any withdrawal pending
    require(deposited > 0);

    // Did the vote succeed?
    bool voteResult = (votes[voteId].votesYes > votes[voteId].votesNo);
    // If the user revealed his vote and vote the same as the winner option
    bool userWon = votes[voteId].hasRevealed[msg.sender] && (voteResult == votes[voteId].revealedVotes[msg.sender]);

    uint tokensToWithdraw;
    if(userWon) {
      uint bonus;
      if(voteResult) {
        bonus = votes[voteId].votesNo*20/100;

        tokensToWithdraw = deposited + bonus*deposited/votes[voteId].votesYes;
      } else {
        bonus = votes[voteId].votesYes*20/100;

        tokensToWithdraw = deposited + bonus*deposited/votes[voteId].votesNo;
      }
    } else {
      tokensToWithdraw = deposited - deposited*20/100;
    }

    // Update balance
    votes[voteId].userDeposits[msg.sender] = 0;

    // Send tokens to the user
    assert(ERC20(cgsToken).transfer(msg.sender, tokensToWithdraw));

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

  /// @notice Returns the vote of the user
  /// @dev Returns the vote of the user
  /// @param voteId ID of the vote
  /// @param who Address of the user
  /// @return the vote of the user
  function getRevealedVotes(uint voteId, address who) public view returns(bool) {
    require(hasUserRevealed(voteId, who));

    return votes[voteId].revealedVotes[who];
  }

  /// @notice Returns if the user has revealed his vote
  /// @dev Returns if the user has revealed his vote
  /// @param voteId ID of the vote
  /// @param who Address of the user
  /// @return true if the user has revealed his vote
  function hasUserRevealed(uint voteId, address who) public view returns(bool) {

    return votes[voteId].hasRevealed[who];
  }

  /// @notice Returns amount of tokens deposited by a user in a vote
  /// @dev Returns amount of tokens deposited by a user in a vote
  /// @param voteId ID of the vote
  /// @param who Address of the user
  /// @return the amount of tokens deposited by a user in a vote
  function getUserDeposit(uint voteId, address who) public view returns(uint) {

    return votes[voteId].userDeposits[who];
  }

  /// @notice Computes the hash of the given data to check if the vote can be revealed
  /// @dev Computes the hash of the given data to check if the vote can be revealed
  /// @param voteId ID of the vote
  /// @param user Voter
  /// @param revealedVote What the user vote
  /// @param salt ID of the vote
  /// @return true if the vote can be reveales
  function checkReveal(uint voteId, address user, bool revealedVote, bytes32 salt)
    internal
    view
    returns(bool)
  {

    return keccak256(revealedVote, salt) == votes[voteId].secretVotes[user];
  }


  /// @notice Count the votes and calls BinaryVoteCallback to inform of the result
  /// @dev Count the votes and calls BinaryVoteCallback to inform of the result
  /// @param voteId ID of the vote
  function finalizeVote(uint voteId) private atStage(voteId, Stages.Settlement) {
    if(votes[voteId].votesYes > votes[voteId].votesNo)
      BinaryVoteCallback(votes[voteId].callback).binaryVoteResult(voteId, true);
    else
      BinaryVoteCallback(votes[voteId].callback).binaryVoteResult(voteId, false);
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param voteId ID of the vote
  /// @param _stage New stage
  function setStage(uint voteId, Stages _stage) private {
    votes[voteId].stage = _stage;

    ev_NewStage(voteId, _stage);
  }
}