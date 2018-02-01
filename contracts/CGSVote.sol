pragma solidity ^0.4.18;

import './util/SafeMath.sol';
import './Vault.sol';
import './Wevern.sol';

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

/// @title CGSVote contract
/// @author Icofunding
contract CGSVote is SafeMath {
  uint constant TIME_TO_VOTE = 7 days;
  uint constant TIME_TO_REVEAL = 3 days;

  /*
   * - Ok: No claim has been ever open
   * - SecretVote: Users deposit their CGS tokens and a hash of their vote.
   *   This stage last for TIME_TO_VOTE.
   * - RevealVote: Users must reveal their vote in the previous stage.
   *   This stage last for TIME_TO_REVEAL.
   * - Settlement: Users can withdraw their tokens with a bonus or penalization,
   *   depending on the outcome of the vote.
   *   This stage remains until a new claim is open
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
    mapping (address => bytes32) secretVotes; // Hashes of votes
    mapping (address => bool) revealedVotes; // Votes in plain text
    mapping (address => bool) hasRevealed; // True if the user has revealed is vote
    mapping (address => uint) userDeposits; // Amount of CGS tokens deposited for this vote.
  }

  mapping (address => uint) public userDeposits; // Number of CGS tokens (plus decimals).
  mapping (address => uint) public voteIdDeposited; // Vote id in which the user deposited the tokens

  Vote[] public votes; // Log of votes
  uint public numVotes; // Number of elements in the array votes

  address public cgsToken;

  event ev_NewStage(uint indexed voteId, Stages stage);
  event ev_NewVote(uint indexed voteId, address who, uint amount);
  event ev_NewReveal(uint indexed voteId, address who, uint amount, bool value);

  modifier atStage(uint voteId, Stages _stage) {
    require(votes[voteId].stage == _stage);

    _;
  }

  // Perform timed transitions.
  modifier timedTransitions(uint voteId) {
    if (votes[voteId].stage == Stages.SecretVote && now >= votes[voteId].date + TIME_TO_VOTE)
      setStage(Stages.RevealVote);

    if (votes[voteId].stage == Stages.RevealVote && now >= votes[voteId].date + TIME_TO_VOTE + TIME_TO_REVEAL) {
      setStage(Stages.Settlement);
      finalizeVote();
    }

    _;
  }

  /// @notice Creates a CGSVote smart contract
  /// @dev Creates a CGSVote smart contract.
  /// @param _cgsToken Address of the CGS token smart contract
  function CGSVote(address _cgsToken) public {
    cgsToken = _cgsToken;
  }

  /// @notice Starts a vote
  /// @dev Starts a vote
  /// @returns the vote ID
  function startVote() public returns(uint) {
    Vote memory newVote = Vote(now, Stages.SecretVote, 0, 0);

    votes.push(newVote);
    numVotes++;

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

    ev_NewVote(voteId, msg.sender, numTokens);

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
    if(keccak256(true, salt) == votes[voteId].secretVotes[msg.sender]) {
      // Vote true
      votes[voteId].revealedVotes[msg.sender] = true;
      votes[voteId].votesYes += votes[voteId].userDeposits[msg.sender];

      ev_NewReveal(voteId, msg.sender, votes[voteId].userDeposits[msg.sender], true);
    } else if(keccak256(false, salt) == votes[voteId].secretVotes[msg.sender]) {
      // Vote false
      votes[voteId].revealedVotes[msg.sender] = false;
      votes[voteId].votesNo += votes[voteId].userDeposits[msg.sender];

      ev_NewReveal(voteId, msg.sender, votes[voteId].userDeposits[msg.sender], false);
    } else
      revert(); // Revert the tx if the reveal fails

    return true;
  }

  /// @notice Withdraws CGS tokens after bonus/penalization
  /// @dev Withdraws CGS tokens after bonus/penalization
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

  /// @notice Count the votes and calls Wevern to inform of the result
  /// @dev Count the votes and calls Wevern to inform of the result
  function finalizeVote() private atStage(Stages.Settlement) {
    if(votes[numVotes-1].votesYes > votes[numVotes-1].votesNo)
      Wevern(wevernAddress).claimResult(true);
    else
      Wevern(wevernAddress).claimResult(false);
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param _stage New stage
  function setStage(Stages _stage) private {
    votes[numVotes-1].stage = _stage;

    ev_NewStage(numVotes-1, _stage);
  }
}
