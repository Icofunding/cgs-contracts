pragma solidity ^0.4.18;

import './util/SafeMath.sol';
import './util/ERC20.sol';
import './CGS.sol';

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
contract Claim is SafeMath {
  uint constant TIME_BETWEEN_CLAIMS = 100 days;
  uint constant TIME_FOR_REDEEM = 10 days;

  /*
   * - ClaimPeriod: Users can deposit and withdraw tokens. If more than claimPrice tokens are
   *   deposited, a claim is open.
   * - ClaimOpen: Deposits and withdrawals get blocked while the CGS holders vote the dispute.
   *   When the result of the vote is received, the state moves to the appropriate next stage.
   * - ClaimSucceed: Users can exchange their tokens (using transferFrom) for ether for a limited period of time.
   *   Users with tokens deposited must withdraw them first.
   *   The state moves to ClaimPeriod if ClaimPeriod + TIME_BETWEEN_CLAIMS <= now.
   * - ClaimFailed: Users can withdraw their tokens with a penalization.
   *   The state moves to ClaimPeriod if ClaimPeriod + TIME_BETWEEN_CLAIMS <= now.
   */
  enum Stages {
    ClaimPeriod,
    ClaimOpen,
    ClaimSucceed,
    ClaimFailed
  }

  mapping (address => uint) public userDeposits; // Number of ICO tokens (plus decimals).
  uint public totalDeposit; // Number of ICO tokens (plus decimals) collected to open a claim. Resets to 0 after a claim is open.
  uint public claimPrice; // Number of ICO tokens (plus decimals)
  uint public lastClaim; // Timestamp when the last claim was open

  Stages public stage; // Current stage. Returns uint.

  uint public currentClaim; // currentClaim
  // claim in which the token holder has deposited tokens.
  // 0 = no tokens deposited in previous claims
  mapping (address => uint) public claimDeposited;

  address public icoLauncherWallet; // ICO launcher token wallet
  address public cgsAddress; // CGS smart contract address
  address public tokenAddress; // CGS smart contract address
  address public vaultAddress; // Vault smart contract

  event ev_DepositTokens(address who, uint amount);
  event ev_WithdrawTokens(address who, uint amount);

  modifier onlyCGS() {
    require(msg.sender == cgsAddress);

    _;
  }

  modifier backToClaimPeriod() {
    if(stage != Stages.ClaimPeriod && lastClaim + TIME_BETWEEN_CLAIMS <= now) {
      totalDeposit = 0;
      currentClaim++;
      setStage(Stages.ClaimPeriod);
    }

    _;
  }

  /// @notice Creates a Claim smart contract
  /// @dev Creates a Claim smart contract.
  /// @param _claimPrice Number of tokens (plus decimals) needed to open a claim
  /// @param _icoLauncher Token wallet of the ICO launcher
  /// @param _tokenAddress Address of the ICO token smart contract
  /// @param _vaultAddress Address of the Vault smart contract
  function Claim(
    uint _claimPrice,
    address _icoLauncher,
    address _tokenAddress,
    address _vaultAddress,
    address _cgsAddress
  ) public {
    claimPrice = _claimPrice;
    icoLauncherWallet = _icoLauncher;
    tokenAddress = _tokenAddress;
    vaultAddress = _vaultAddress;
    cgsAddress = _cgsAddress;
    currentClaim = 1;

    setStage(Stages.ClaimPeriod);
  }

  /// @notice Deposits tokens. Should be executed after Token.Approve(...)
  /// @dev Deposits tokens. Should be executed after Token.Approve(...)
  function depositTokens() public backToClaimPeriod returns(bool) {
    // Check stage
    require(stage == Stages.ClaimPeriod);
    // The user has no tokens deposited in previous claims
    require(claimDeposited[msg.sender] == 0 || claimDeposited[msg.sender] == currentClaim);

    // Send the approved amount of tokens
    uint amount = ERC20(tokenAddress).allowance(msg.sender, this);

    assert(ERC20(tokenAddress).transferFrom(msg.sender, this, amount));

    // Update balances
    userDeposits[msg.sender] += amount;
    totalDeposit += amount;

    claimDeposited[msg.sender] = currentClaim;

    // Open a claim?
    if(totalDeposit >= claimPrice) {
      if(CGS(cgsAddress).openClaim()) {
        lastClaim = now;
        setStage(Stages.ClaimOpen);
      }
    }

    ev_DepositTokens(msg.sender, amount);

    return true;
  }

  /// @notice Withdraws tokens
  /// @dev Withdraws tokens
  /// @param amount Number of tokens
  function withdrawTokens(uint amount) public backToClaimPeriod returns(bool) {
    // Check stage
    require(stage == Stages.ClaimPeriod);
    // Enough tokens deposited
    require(userDeposits[msg.sender] >= amount);
    // The tokens are doposited for the current claim.
    // If the tokens are from previous claims, the user should cashOut instead
    require(claimDeposited[msg.sender] == currentClaim);

    // Update balances
    userDeposits[msg.sender] -= amount;
    totalDeposit -= amount;

    // No tokens in this claim
    if(userDeposits[msg.sender] == 0)
      claimDeposited[msg.sender] = 0;

    // Send the tokens to the user
    assert(ERC20(tokenAddress).transfer(msg.sender, amount));

    ev_WithdrawTokens(msg.sender, amount);

    return true;
  }

  /// @notice Withdraws all tokens after a claim is open
  /// @dev Withdraws all tokens after a claim is open
  function cashOut() public backToClaimPeriod returns(bool) {

  }

  /// @notice Exchange tokens for ether if a claim success
  /// @dev Exchange tokens for ether if a claim success
  function redeem() public returns(bool) {

    return true;
  }

  /// @notice Receives the result of a claim
  /// @dev Receives the result of a claim
  function claimResult(bool claimSucceed) public onlyCGS {
    // setStage(Stages.ClaimSucceed);
    // setStage(Stages.ClaimFailed);
  }

  /// @notice Whether withdraws are allowed or not
  /// @dev Whether withdraws are allowed or not.
  /// @return True if in ClaimPeriod stage or if a claim succeded no more than 10 days ago ??
  function isWithdrawOpen() public view returns(bool) {

    return true;
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param _stage New stage
  function setStage(Stages _stage) private {
    stage = _stage;
  }

  /// @notice Sends tokens to the ICO launcher when there is a failed claim
  /// @dev Sends tokens to the ICO launcher when there is a failed claim
  function sendTokensToIcoLauncher(uint numTokens) private returns(bool) {

    return true;
  }

}
