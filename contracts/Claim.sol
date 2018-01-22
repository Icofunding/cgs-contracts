pragma solidity ^0.4.18;

import './util/SafeMath.sol';
import './util/ERC20.sol';

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

  address public icoLauncherWallet; // ICO launcher token wallet
  address public cgsAddress; // CGS smart contract address
  address public tokenAddress; // CGS smart contract address
  address public vaultAddress;

  event ev_DepositTokens(address who, uint amount);

  modifier onlyCGS() {
    require(msg.sender == cgsAddress);

    _;
  }

  modifier backToClaimPeriod() {
    if(stage != Stages.ClaimPeriod && lastClaim + TIME_BETWEEN_CLAIMS <= now)
      setStage(Stages.ClaimPeriod);

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
    address _vaultAddress
    ) public {
    claimPrice = _claimPrice;
    icoLauncherWallet = _icoLauncher;
    tokenAddress = _tokenAddress;
    vaultAddress = _vaultAddress;

    setStage(Stages.ClaimPeriod);
  }

  /// @notice Deposits tokens. Should be executed after Token.Approve(...)
  /// @dev Deposits tokens. Should be executed after Token.Approve(...)
  function depositTokens() public backToClaimPeriod returns(bool) {
    // A claim should only be open if redeem is not open

    // ev_DepositTokens(msg.sender, amount);

    return true;
  }

  /// @notice Withdraws tokens
  /// @dev Withdraws tokens
  /// @param amount Number of tokens
  function withdrawTokens(uint amount) public backToClaimPeriod returns(bool) {

    return true;
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
