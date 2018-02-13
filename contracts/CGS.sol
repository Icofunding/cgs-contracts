pragma solidity ^0.4.18;

import './util/SafeMath.sol';
import './interfaces/ERC20.sol';
import './CGSBinaryVote.sol';
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

/// @title CGS contract
/// @author Icofunding
contract CGS is SafeMath {
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
  mapping (uint => bool) public claimResults; // If everything is ok with the project or not
  mapping (uint => uint) public voteIds; // Ids of the votes in CGSBinaryVote
  // claim in which the token holder has deposited tokens.
  // 0 = no tokens deposited in previous claims
  mapping (address => uint) public claimDeposited;

  uint public weiPerSecond; // Wei that the ICO launcher can withdraw per second
  uint public startDate; // Timestamp when the CGS starts
  uint public weiWithdrawToDate; // Wei that the ICO launcher has withdraw to date

  address public icoLauncherWallet; // ICO launcher token wallet
  address public cgsVoteAddress; // CGSVote smart contract address
  address public tokenAddress; // ICO token smart contract address
  address public vaultAddress; // Vault smart contract

  event ev_DepositTokens(address who, uint amount);
  event ev_WithdrawTokens(address who, uint amount);
  event ev_OpenClaim(uint voteId);

  modifier atStage(Stages _stage) {
    require(stage == _stage);

    _;
  }

  modifier timedTransitions() {
    Stages newStage = getStage();

    if(newStage != stage) {
      setStage(newStage);

      // Executed only once, when the a claim ends
      if(newStage == Stages.ClaimPeriod) {
        totalDeposit = 0;
        currentClaim++;
        setStage(Stages.ClaimPeriod);
      }
    }

    _;
  }

  modifier onlyCGSVote() {
    require(msg.sender == cgsVoteAddress);

    _;
  }

  modifier onlyIcoLauncher() {
    require(msg.sender == icoLauncherWallet);

    _;
  }

  /// @notice Creates a CGS smart contract
  /// @dev Creates a CGS smart contract.
  /// @param _weiPerSecond Amount of wei available to withdraw by the ICO lacunher per second
  /// @param _claimPrice Number of tokens (plus decimals) needed to open a claim
  /// @param _icoLauncher Token wallet of the ICO launcher
  /// @param _tokenAddress Address of the ICO token smart contract
  /// @param _cgsVoteAddress Address of the CGS Vote smart contract
  /// @param _startDate Date from when the ICO launcher can start withdrawing funds
  function CGS(
    uint _weiPerSecond,
    uint _claimPrice,
    address _icoLauncher,
    address _tokenAddress,
    address _cgsVoteAddress,
    uint _startDate
  ) public {
    require(_weiPerSecond > 0);
    weiPerSecond = _weiPerSecond;
    claimPrice = _claimPrice;
    icoLauncherWallet = _icoLauncher;
    tokenAddress = _tokenAddress;
    cgsVoteAddress = _cgsVoteAddress;
    vaultAddress = new Vault(this);
    startDate = _startDate; // Very careful with this!!!!
    currentClaim = 1;

    setStage(Stages.ClaimPeriod);
  }

  /// @notice Deposits tokens. Should be executed after Token.Approve(...)
  /// @dev Deposits tokens. Should be executed after Token.Approve(...)
  /// @param numTokens Number of tokens
  function depositTokens(uint numTokens) public timedTransitions atStage(Stages.ClaimPeriod) returns(bool) {
    // The user has no tokens deposited in previous claims
    require(claimDeposited[msg.sender] == 0 || claimDeposited[msg.sender] == currentClaim);
    // Enough tokens allowed
    require(numTokens <= ERC20(tokenAddress).allowance(msg.sender, this));

    assert(ERC20(tokenAddress).transferFrom(msg.sender, this, numTokens));

    // Update balances
    userDeposits[msg.sender] += numTokens;
    totalDeposit += numTokens;

    claimDeposited[msg.sender] = currentClaim;

    // Open a claim?
    if(totalDeposit >= claimPrice) {
      voteIds[currentClaim] = CGSBinaryVote(cgsVoteAddress).startVote(this);
      lastClaim = now;
      setStage(Stages.ClaimOpen);

      ev_OpenClaim(voteIds[currentClaim]);
    }

    ev_DepositTokens(msg.sender, numTokens);

    return true;
  }

  /// @notice Withdraws tokens during the Claim period
  /// @dev Withdraws tokens during the Claim period
  /// @param numTokens Number of tokens
  function withdrawTokens(uint numTokens) public atStage(Stages.ClaimPeriod) returns(bool) {
    // Enough tokens deposited
    require(userDeposits[msg.sender] >= numTokens);
    // The tokens are doposited for the current claim.
    // If the tokens are from previous claims, the user should cashOut instead
    require(claimDeposited[msg.sender] == currentClaim);

    // Update balances
    userDeposits[msg.sender] -= numTokens;
    totalDeposit -= numTokens;

    // No tokens in this (or any) claim
    if(userDeposits[msg.sender] == 0)
      claimDeposited[msg.sender] = 0;

    // Send the tokens to the user
    assert(ERC20(tokenAddress).transfer(msg.sender, numTokens));

    ev_WithdrawTokens(msg.sender, numTokens);

    return true;
  }

  /// @notice Withdraws all tokens after a claim finished
  /// @dev Withdraws all tokens after a claim finished
  function cashOut() public timedTransitions returns(bool) {
    uint claim = claimDeposited[msg.sender];

    if(claim != 0) {
      if(claim != currentClaim || stage == Stages.ClaimEnded || stage == Stages.Redeem) {
        bool isProjectOk = claimResults[claim];
        uint tokensToCashOut = userDeposits[msg.sender];

        // Update balance
        userDeposits[msg.sender] = 0;
        claimDeposited[msg.sender] = 0;

        // If the claim does not succeded
        if(isProjectOk) {
          // 1% penalization goes to the ICO launcher
          uint tokensToIcoLauncher = tokensToCashOut/100;
          tokensToCashOut -= tokensToIcoLauncher;

          assert(ERC20(tokenAddress).transfer(icoLauncherWallet, tokensToIcoLauncher));
        }

        // Cash out
        assert(ERC20(tokenAddress).transfer(msg.sender, tokensToCashOut));
      }
    }
  }

  /// @notice Exchange tokens for ether if a claim success. Executed after approve(...)
  /// @dev Exchange tokens for ether if a claim success. Executed after approve(...)
  /// @param numTokens Number of tokens
  function redeem(uint numTokens) public timedTransitions atStage(Stages.Redeem) returns(bool) {
    // Enough tokens allowed
    require(numTokens <= ERC20(tokenAddress).allowance(msg.sender, this));

    // Calculate the amount of Wei to receive in exchange of the tokens
    uint weiToSend = (numTokens * (Vault(vaultAddress).etherBalance() - calculateWeiToWithdrawAt(lastClaim))) / ERC20(tokenAddress).totalSupply();

    // Send Tokens to ICO launcher
    assert(ERC20(tokenAddress).transferFrom(msg.sender, icoLauncherWallet, numTokens));
    // Send ether to ICO holder
    Vault(vaultAddress).withdraw(msg.sender, weiToSend);

    return true;
  }

  /// @notice Receives the result of a claim
  /// @dev Receives the result of a claim
  /// @param voteId id of the vote
  /// @param voteResult Outcome of the vote
  function binaryVoteResult(uint voteId, bool voteResult) public onlyCGSVote {
    // To make sure that the Id of the vote is the one expected
    require(voteIds[currentClaim] == voteId);

    claimResults[currentClaim] = voteResult;

    if(voteResult) {
      // Everything is ok with the project
      setStage(Stages.ClaimEnded);
    } else {
      // Meh, the CGS voters thin that the funds are not well managed
      setStage(Stages.Redeem);

      startRedeem = now;
    }
  }
/*
  /// @notice Withdraws money by the ICO launcher according to the roadmap
  /// @dev Withdraws money by the ICO launcher according to the roadmap
  function withdrawWei() public onlyIcoLauncher {
    calculateWeiToWithdrawAt(now);
  }
*/

  /// @notice Returns the actual stage of the claim
  /// @dev Returns the actual stage of the claim
  /// @return the actual stage of the claim
  function getStage() public view returns(Stages) {
    Stages s = stage;

    if(s == Stages.Redeem && (startRedeem + TIME_FOR_REDEEM <= now))
      s = Stages.ClaimEnded;

    if(s == Stages.ClaimEnded && (lastClaim + TIME_BETWEEN_CLAIMS <= now))
      s = Stages.ClaimPeriod;

    return s;
  }

  /// @notice Returns the amount of Wei available for the ICO launcher to withdraw at a specified date
  /// @dev Returns the amount of Wei available for the ICO launcher to withdraw at a specified date
  /// @return the amount of Wei available for the ICO launcher to withdraw at a specified date
  function calculateWeiToWithdrawAt(uint date) public view returns(uint) {
    return (date - startDate) * weiPerSecond - weiWithdrawToDate;
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param _stage New stage
  function setStage(Stages _stage) private {
    stage = _stage;
  }
}
