pragma solidity ^0.4.18;

import './util/SafeMath.sol';
import './Vault.sol';
import './Claim.sol';

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

/// @title CGS contract
/// @author Icofunding
contract CGS is SafeMath {
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
    mapping (address => bytes32) secretVotes;
    mapping (address => bool) revealed;
  }

  mapping (address => uint) public userDeposits; // Number of CGS tokens (plus decimals).

  Vote[] public votes; // Log of votes
  uint public currentVote; // id of the current vote

  uint[] public roadMapMoney; // Wei
  uint[] public roadMapDates; // Timestamps

  address public vaultAddress;
  address public claimAddress;
  address public icoLauncherWallet;

  event ev_NewStage(uint indexed voteId, Stages stage);

  modifier onlyClaimContract() {
    require(msg.sender == claimAddress);

    _;
  }

  modifier atStage(Stages _stage) {
    require(votes[currentVote].stage == _stage);

    _;
  }

  // Perform timed transitions.
  modifier timedTransitions() {
    if (votes[currentVote].stage == Stages.SecretVote && now >= votes[currentVote].date + TIME_TO_VOTE)
      setStage(Stages.RevealVote);

    if (votes[currentVote].stage == Stages.RevealVote && now >= votes[currentVote].date + TIME_TO_VOTE + TIME_TO_REVEAL)
      setStage(Stages.Settlement);

    _;
  }

  /// @notice Creates a CGS smart contract
  /// @dev Creates a CGS smart contract.
  /// roadMapMoney and roadMapDates must have the same length.
  /// roadMapDates must be an ordered list.
  /// @param _roadMapMoney List of wei amounts to be released
  /// @param _roadMapDates List of timestamps when the wei amounts in roadMapMoney are going to be released
  /// @param _wallet ICO launcher wallet address
  function CGS(
    uint[] _roadMapMoney,
    uint[] _roadMapDates,
    uint _claimPrice,
    address _wallet,
    address _token
  ) public {
    roadMapMoney = _roadMapMoney;
    roadMapDates = _roadMapDates;
    icoLauncherWallet = _wallet;
    vaultAddress = new Vault();
    claimAddress = new Claim(_claimPrice, _wallet, _token, vaultAddress, this);
  }

  /// @notice Deposits CGS tokens and vote. Should be executed after Token.Approve(...)
  /// @dev Deposits CGS tokens and vote. Should be executed after Token.Approve(...)
  /// @param secretVote Hash of the vote + salt
  function vote(bytes32 secretVote) public timedTransitions atStage(Stages.SecretVote) returns(bool) {

    return true;
  }

  /// @notice Reveal the vote
  /// @dev Reveal the vote
  /// @param salt Random salt used to vote
  /// @return The direction of the vote
  function reveal(bytes32 salt) public timedTransitions atStage(Stages.RevealVote) returns(bool) {

    return true;
  }

  /// @notice Count the votes and calls Claim to inform of the result
  /// @dev Count the votes and calls Claim to inform of the result
  function finalizeVote() public atStage(Stages.Settlement) {
    // Claim(claimAddress).claimResult(true);
    // Claim(claimAddress).claimResult(false);
  }

  /// @notice Withdraws CGS tokens after bonus/penalization
  /// @dev Withdraws CGS tokens after bonus/penalization
  function withdrawTokens() public returns(bool) {
    // Only if in Settlement stage or the user has not voted in the current vote and has CGS tokens deposited

    return true;
  }

  /// @notice Opens a claim by starting a vote
  /// @dev Opens a claim by starting a vote
  function openClaim() public onlyClaimContract returns(bool) {

    return true;
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param _stage New stage
  function setStage(Stages _stage) private {
    votes[currentVote].stage = _stage;

    ev_NewStage(currentVote, _stage);
  }
}
