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
    bool finalized;
    mapping (address => bytes32) secretVotes;
    mapping (address => bool) revealedVotes;
    mapping (address => bool) revealed;
  }

  mapping (address => uint) public userDeposits; // Number of CGS tokens (plus decimals).
  mapping (address => uint) public voteIdDeposited; // Vote id in which the user deposited the tokens

  Vote[] public votes; // Log of votes
  uint public numVotes; // Number of elements in the array votes

  address public wevernAddress;
  address public cgsToken;

  event ev_NewStage(uint indexed voteId, Stages stage);

  modifier onlyWevernContract() {
    require(msg.sender == wevernAddress);

    _;
  }

  modifier atStage(Stages _stage) {
    require(votes[numVotes-1].stage == _stage);

    _;
  }

  // Perform timed transitions.
  modifier timedTransitions() {
    if (votes[numVotes-1].stage == Stages.SecretVote && now >= votes[numVotes-1].date + TIME_TO_VOTE)
      setStage(Stages.RevealVote);

    if (votes[numVotes-1].stage == Stages.RevealVote && now >= votes[numVotes-1].date + TIME_TO_VOTE + TIME_TO_REVEAL)
      setStage(Stages.Settlement);

    _;
  }

  /// @notice Creates a CGSVote smart contract
  /// @dev Creates a CGSVote smart contract.
  /// @param _wevernAddress Address of the Wevern smart contract
  /// @param _cgsToken Address of the CGS token smart contract
  function CGSVote(address _wevernAddress, address _cgsToken) public {
    wevernAddress = _wevernAddress;
    cgsToken = _cgsToken;
  }

  /// @notice Deposits CGS tokens and vote. Should be executed after Token.Approve(...)
  /// @dev Deposits CGS tokens and vote. Should be executed after Token.Approve(...)
  /// @param secretVote Hash of the vote + salt
  function vote(bytes32 secretVote) public timedTransitions atStage(Stages.SecretVote) returns(bool) {
    // There must be at least one vote open
    require(numVotes > 0);
    // The user must withdraw first their tokens from previous votes
    // It can only vote once per Voting period
    require(userDeposits[msg.sender] > 0);

    uint amount = ERC20(cgsToken).allowance(msg.sender, this);

    // You cannot vote with 0 tokens (?)
    require(amount > 0);

    assert(ERC20(cgsToken).transferFrom(msg.sender, this, amount));
    userDeposits[msg.sender] = amount;

    votes[numVotes-1].secretVotes[msg.sender] = secretVote;

    return true;
  }

  /// @notice Reveal the vote
  /// @dev Reveal the vote
  /// @param salt Random salt used to vote
  /// @return The direction of the vote
  function reveal(bytes32 salt) public timedTransitions atStage(Stages.RevealVote) returns(bool) {
    // Only users who vote can reveal their vote
    require(votes[numVotes-1].secretVotes[msg.sender].length > 0);
    // Check if the vote is already revealed
    require(!votes[numVotes-1].revealed[msg.sender]);

    // Check the vote as revealed
    votes[numVotes-1].revealed[msg.sender] = true;

    // Check if he user voted yes or no to update the results
    if(keccak256(true, salt) == votes[numVotes-1].secretVotes[msg.sender]) {
      votes[numVotes-1].revealedVotes[msg.sender] = true;
      votes[numVotes-1].votesYes += userDeposits[msg.sender];
    } else if(keccak256(false, salt) == votes[numVotes-1].secretVotes[msg.sender]) {
      votes[numVotes-1].revealedVotes[msg.sender] = false;
      votes[numVotes-1].votesNo += userDeposits[msg.sender];
    } else
      revert(); // Revert the tx if the reveal fails

    return true;
  }

  /// @notice Count the votes and calls Wevern to inform of the result
  /// @dev Count the votes and calls Wevern to inform of the result
  function finalizeVote() public timedTransitions atStage(Stages.Settlement) {
    if(!votes[numVotes-1].finalized) {
      if(votes[numVotes-1].votesYes > votes[numVotes-1].votesNo)
        Wevern(wevernAddress).claimResult(true);
      else
        Wevern(wevernAddress).claimResult(false);

      votes[numVotes-1].finalized = true;
    }
  }

  /// @notice Withdraws CGS tokens after bonus/penalization
  /// @dev Withdraws CGS tokens after bonus/penalization
  function withdrawTokens() public returns(bool) {
    // Only if in Settlement stage or the user has not voted in the current vote and has CGS tokens deposited
    require(userDeposits[msg.sender] > 0);

    // If the user has voted in the current vote
    if(votes[numVotes-1].secretVotes[msg.sender].length > 0) {
      require(votes[numVotes-1].stage == Stages.Settlement); // It must be in Settlement stage

      // If there are more votes saying that the ICO is not doing a proper use of the funds
      bool successfulClaim = (votes[numVotes-1].votesNo > votes[numVotes-1].votesYes);

    } else {
      // The user has tokens deposited from previous votes
    }

    return true;
  }

  /// @notice Starts a vote
  /// @dev Starts a vote
  function startVote() public onlyWevernContract returns(bool) {
    Vote memory newVote = Vote(now, Stages.SecretVote, 0, 0, false);

    votes.push(newVote);
    numVotes++;

    return true;
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param _stage New stage
  function setStage(Stages _stage) private {
    votes[numVotes].stage = _stage;

    ev_NewStage(numVotes, _stage);
  }
}
