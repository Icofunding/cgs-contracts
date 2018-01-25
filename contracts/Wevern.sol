pragma solidity ^0.4.18;

import './util/SafeMath.sol';
import './util/ERC20.sol';
import './CGSVote.sol';
import './Vault.sol';

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

/// @title Wevern contract
/// @author Icofunding
contract Wevern is SafeMath {
  uint constant TIME_BETWEEN_CLAIMS = 100 days;
  uint constant TIME_FOR_REDEEM = 10 days;

  /*
   * - ClaimPeriod: Users can deposit and withdraw tokens. If more than claimPrice tokens are
   *   deposited, a claim is open.
   * - ClaimOpen: Deposits and withdrawals get blocked while the CGS holders vote the dispute.
   *   When the result of the vote is received, the state moves to the appropriate next stage.
   * - Redeem: Deposits and withdrawals are blocked. Users can cashout their ICO tokens.
   *   ICO holders can exhcnage theur ICO token for ether.
   *   The state moves to ClaimEnded if startRedeem + TIME_FOR_REDEEM <= now.
   *   The state moves to ClaimPeriod if lastClaim + TIME_BETWEEN_CLAIMS <= now.
   * - ClaimEnded: Deposits and withdrawals are blocked. Users can cashout their ICO tokens.
   *   The state moves to ClaimPeriod if lastClaim + TIME_BETWEEN_CLAIMS <= now.
   */
  enum Stages {
    ClaimPeriod,
    ClaimOpen,
    Redeem,
    ClaimEnded
  }

  mapping (address => uint) public userDeposits; // Number of ICO tokens (plus decimals).
  uint public totalDeposit; // Number of ICO tokens (plus decimals) collected to open a claim. Resets to 0 after a claim is open.
  uint public claimPrice; // Number of ICO tokens (plus decimals)
  uint public lastClaim; // Timestamp when the last claim was open
  uint public startRedeem; // Timestamp when the redeem period starts

  Stages public stage; // Current stage. Returns uint.

  uint public currentClaim; // currentClaim
  mapping (uint => bool) public claimResults; // If the claims have succeded or not
  // claim in which the token holder has deposited tokens.
  // 0 = no tokens deposited in previous claims
  mapping (address => uint) public claimDeposited;

  address public icoLauncherWallet; // ICO launcher token wallet
  address public cgsVoteAddress; // CGSVote smart contract address
  address public tokenAddress; // ICO token smart contract address
  address public vaultAddress; // Vault smart contract

  event ev_DepositTokens(address who, uint amount);
  event ev_WithdrawTokens(address who, uint amount);

  modifier onlyCGSVote() {
    require(msg.sender == cgsVoteAddress);

    _;
  }

  modifier backToClaimPeriod() {
    if(stage != Stages.ClaimPeriod && isClaimPeriod()) {
      totalDeposit = 0;
      currentClaim++;
      setStage(Stages.ClaimPeriod);
    }

    _;
  }

  modifier endRedeemPeriod() {
    if(stage == Stages.Redeem && isRedeemStage()) {
      setStage(Stages.ClaimEnded);
    }

    _;
  }

  /// @notice Creates a Wevern smart contract
  /// @dev Creates a Wevern smart contract.
  /// @param _claimPrice Number of tokens (plus decimals) needed to open a claim
  /// @param _icoLauncher Token wallet of the ICO launcher
  /// @param _tokenAddress Address of the ICO token smart contract
  function Wevern(
    uint _claimPrice,
    address _icoLauncher,
    address _tokenAddress,
    address _cgsVoteAddress
  ) public {
    claimPrice = _claimPrice;
    icoLauncherWallet = _icoLauncher;
    tokenAddress = _tokenAddress;
    cgsVoteAddress = _cgsVoteAddress;
    vaultAddress = new Vault(this);
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
      if(CGSVote(cgsVoteAddress).openClaim()) {
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

    // No tokens in this (or any) claim
    if(userDeposits[msg.sender] == 0)
      claimDeposited[msg.sender] = 0;

    // Send the tokens to the user
    assert(ERC20(tokenAddress).transfer(msg.sender, amount));

    ev_WithdrawTokens(msg.sender, amount);

    return true;
  }

  /// @notice Withdraws all tokens after a claim finished
  /// @dev Withdraws all tokens after a claim finished
  function cashOut() public endRedeemPeriod backToClaimPeriod returns(bool) {
    uint claim = claimDeposited[msg.sender];

    if(claim != 0) {
      if(claim == currentClaim && stage == Stages.ClaimEnded) {
        var (,, votesYes, votesNo) = CGSVote(cgsVoteAddress).votes(claim-1);

        uint tokensToCashOut = userDeposits[msg.sender];

        // If the claim does not succeded
        if(votesYes >= votesNo) {
          // 1% penalization goes to ICO launcher
          uint tokensToIcoLauncher = tokensToCashOut/100;
          tokensToCashOut -= tokensToIcoLauncher;

          assert(ERC20(tokenAddress).transfer(icoLauncherWallet, tokensToIcoLauncher));
        }

        // Update balance
        userDeposits[msg.sender] = 0;
        claimDeposited[msg.sender] = 0;

        // Cash out
        assert(ERC20(tokenAddress).transfer(msg.sender, tokensToCashOut));
      }
    }
  }

  /// @notice Exchange tokens for ether if a claim success. Executed after approve(...)
  /// @dev Exchange tokens for ether if a claim success. Executed after approve(...)
  function redeem() public endRedeemPeriod returns(bool) {
    // Check stage
    require(stage == Stages.Redeem);

    // Number of tokens to exchange
    uint numTokens = ERC20(tokenAddress).allowance(msg.sender, this);
    // Calculate the amount of Wei to receive in exchange of the tokens
    uint weiToSend = (numTokens * Vault(vaultAddress).etherBalance()) / ERC20(tokenAddress).totalSupply();

    // Send Tokens to ICO launcher
    assert(ERC20(tokenAddress).transferFrom(msg.sender, icoLauncherWallet, numTokens));
    // Send ether to ICO holder
    Vault(vaultAddress).withdraw(msg.sender, weiToSend);

    return true;
  }

  /// @notice Receives the result of a claim
  /// @dev Receives the result of a claim
  function claimResult(bool claimSucceed) public onlyCGSVote {
    claimResults[currentClaim] = claimSucceed;

    if(claimSucceed) {
      setStage(Stages.Redeem);
      startRedeem = now;
    } else {
      setStage(Stages.ClaimEnded);
    }
  }

  /// @notice Whether a new claim can be open or not
  /// @dev Whether a new claim can be open or not
  /// @return True if new claims can be open
  function isClaimPeriod() public view returns(bool) {

    return (lastClaim + TIME_BETWEEN_CLAIMS <= now);
  }

  /// @notice Whether ICO tokens can be exchanged for ether or not
  /// @dev Whether ICO tokens can be exchanged for ether or not
  /// @return True if ICO tokens can be exchanged for ether
  function isRedeemStage() public view returns(bool) {

    return (startRedeem + TIME_FOR_REDEEM <= now);
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param _stage New stage
  function setStage(Stages _stage) private {
    stage = _stage;
  }
}
