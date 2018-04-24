pragma solidity ^0.4.18;

import './util/SafeMath.sol';
import './interfaces/ERC20.sol';
import './interfaces/CGSBinaryVoteInterface.sol';
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
contract CGS {
  uint constant TIME_BETWEEN_CLAIMS = 100 days;
  uint constant TIME_FOR_REDEEM = 10 days;

  using SafeMath for uint;

  /*
   * - ClaimPeriod: Users can deposit and withdraw tokens. If more than claimPrice tokens are
   *   deposited, a claim is open.
   * - ClaimOpen: Deposits and withdrawals get blocked while the CGS holders vote the dispute.
   *   When the result of the vote is received, the state moves to the appropriate next stage.
   * - Redeem: Deposits and withdrawals are blocked. Users can cashout their ICO tokens.
   *   ICO holders can exhcnage theur ICO token for ether.
   *   The state moves to ClaimEnded if lastClaim + VOTING_DURATION + TIME_FOR_REDEEM <= now.
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
  uint public weiBalanceAtlastClaim; // Wei balance when the last claim was open

  uint public tokensInVestingAtLastClaim; // Number of tokens in Redeem Vesting before the current claim
  uint public tokensInVesting; // Number of tokens in Redeem Vesting
  uint public weiRedeem; // Ether withdraw by ICO token holders during the Redeem process
  uint public weiToWithdrawAtLastClaim; // Wei available for the ICO launcher when the last claim was open.

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

  event ev_NewStage(Stages stage);
  event ev_DepositTokens(address who, uint amount);
  event ev_WithdrawTokens(address who, uint amount);
  event ev_OpenClaim(uint voteId);
  event ev_CashOut(address who, uint tokensToUser, uint tokensToIcolauncher);
  event ev_Redeem(address who, uint tokensSent, uint weiReceived);


  modifier atStage(Stages _stage) {
    require(stage == _stage);

    _;
  }

  modifier wakeVoter {
    CGSBinaryVoteInterface(cgsVoteAddress).finalizeVote(voteIds[currentClaim]);

    _;
  }

  modifier timedTransitions() {
    Stages newStage = getStage();

    if(newStage != stage) {
      setStage(newStage);
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
    require(CGSBinaryVoteInterface(_cgsVoteAddress).getVotingProcessDuration() + TIME_FOR_REDEEM <= TIME_BETWEEN_CLAIMS);

    weiPerSecond = _weiPerSecond;
    claimPrice = _claimPrice;
    icoLauncherWallet = _icoLauncher;
    tokenAddress = _tokenAddress;
    cgsVoteAddress = _cgsVoteAddress;
    vaultAddress = new Vault(this);
    startDate = _startDate; // Very careful with this!!!!
    currentClaim = 1;
  }

  /// @notice Deposits tokens. Should be executed after Token.Approve(...)
  /// @dev Deposits tokens. Should be executed after Token.Approve(...)
  /// @param numTokens Number of tokens
  function depositTokens(uint numTokens) public timedTransitions atStage(Stages.ClaimPeriod) returns(bool) {
    // The user cannot deposit tokens if there is no ether to claim
    require(isActive());
    // The user has no tokens deposited in previous claims
    require(claimDeposited[msg.sender] == 0 || claimDeposited[msg.sender] == currentClaim);
    // Enough tokens allowed
    require(numTokens <= ERC20(tokenAddress).allowance(msg.sender, this));

    assert(ERC20(tokenAddress).transferFrom(msg.sender, this, numTokens));

    // Update balances
    userDeposits[msg.sender] = userDeposits[msg.sender].add(numTokens);
    totalDeposit = totalDeposit.add(numTokens);

    claimDeposited[msg.sender] = currentClaim;

    // Open a claim?
    if(totalDeposit >= claimPrice) {
      voteIds[currentClaim] = CGSBinaryVoteInterface(cgsVoteAddress).startVote(this);
      lastClaim = now;
      weiBalanceAtlastClaim = Vault(vaultAddress).etherBalance();
      tokensInVestingAtLastClaim = tokensInVesting;
      weiToWithdrawAtLastClaim = calculateWeiToWithdraw();
      setStage(Stages.ClaimOpen);

      ev_OpenClaim(voteIds[currentClaim]);
    }

    ev_DepositTokens(msg.sender, numTokens);

    return true;
  }

  /// @notice Withdraws tokens during the Claim period
  /// @dev Withdraws tokens during the Claim period
  /// @param numTokens Number of tokens
  function withdrawTokens(uint numTokens) public timedTransitions atStage(Stages.ClaimPeriod) returns(bool) {
    // Enough tokens deposited
    require(userDeposits[msg.sender] >= numTokens); // Redundant with SafeMath
    // The tokens are doposited for the current claim.
    // If the tokens are from previous claims, the user should cashOut instead
    require(claimDeposited[msg.sender] == currentClaim);

    // Update balances
    userDeposits[msg.sender] = userDeposits[msg.sender].sub(numTokens);
    totalDeposit = totalDeposit.sub(numTokens);

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
  function cashOut() public wakeVoter timedTransitions returns(bool) {
    uint tokensToUser;
    uint tokensToIcoLauncher;
    (tokensToUser, tokensToIcoLauncher) = tokensToCashOut(msg.sender);

    if(tokensToUser > 0) {
      // Update balance
      userDeposits[msg.sender] = 0;
      claimDeposited[msg.sender] = 0;

      // Make transfers //

      // To user (99-100%)
      assert(ERC20(tokenAddress).transfer(msg.sender, tokensToUser));

      // To ICO launcher if the claim did not succeed
      if (tokensToIcoLauncher > 0) {
        assert(ERC20(tokenAddress).transfer(icoLauncherWallet, tokensToIcoLauncher));
      }

      ev_CashOut(msg.sender, tokensToUser, tokensToIcoLauncher);
    }
  }

  /// @notice Exchange tokens for ether if a claim success. Executed after approve(...)
  /// @dev Exchange tokens for ether if a claim success. Executed after approve(...)
  /// @param numTokens Number of tokens
  function redeem(uint numTokens) public wakeVoter timedTransitions atStage(Stages.Redeem) returns(bool) {
    // Enough tokens allowed
    require(numTokens <= ERC20(tokenAddress).allowance(msg.sender, this));

    // Calculate the amount of Wei to receive in exchange of the tokens
    uint weiToSend = calculateEtherPerTokens(numTokens);

    // Send Tokens to the Redeem Vesting
    // Redeem vesting is needed to avoid the icoLauncher using Redeem to drain all the ether.
    assert(ERC20(tokenAddress).transferFrom(msg.sender, this, numTokens));
    tokensInVesting = tokensInVesting.add(numTokens);
    // Send ether to ICO token holder
    weiRedeem = weiRedeem.add(weiToSend);
    Vault(vaultAddress).withdraw(msg.sender, weiToSend);

    ev_Redeem(msg.sender, numTokens, weiToSend);

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
    }
  }

  /// @notice Withdraws money by the ICO launcher according to the roadmap
  /// @dev Withdraws money by the ICO launcher according to the roadmap
  function withdrawWei() public onlyIcoLauncher wakeVoter timedTransitions {
    uint weiToWithdraw = calculateWeiToWithdraw();

    weiWithdrawToDate = weiWithdrawToDate.add(weiToWithdraw);

    Vault(vaultAddress).withdraw(icoLauncherWallet, weiToWithdraw);
  }

  /// @notice Withdraws tokens in Redeem vesting by the ICO launcher when the CGS ends
  /// @dev Withdraws tokens in Redeem vesting by the ICO launcher when the CGS ends
  function withdrawLockedTokens() public onlyIcoLauncher {
    // This is needed to avoid the icoLauncher using Redeem to drain all the ether.
    require(Vault(vaultAddress).etherBalance() == 0);

    assert(ERC20(tokenAddress).transfer(icoLauncherWallet, tokensInVesting));

    tokensInVesting = 0;
  }

  /// @notice Returns the actual stage of the claim
  /// @dev Returns the actual stage of the claim
  /// @return the actual stage of the claim
  function getStage() public view returns(Stages) {
    Stages s = stage;

    if(s == Stages.Redeem && (lastClaim + CGSBinaryVoteInterface(cgsVoteAddress).getVotingProcessDuration() + TIME_FOR_REDEEM <= now))
      s = Stages.ClaimEnded;

    if(s == Stages.ClaimEnded && (lastClaim + TIME_BETWEEN_CLAIMS <= now))
      s = Stages.ClaimPeriod;

    return s;
  }

  /// @notice Returns the actual number of tokens deposited to open a claim
  /// @dev Returns the actual number of tokens deposited to open a claim (taking into account discrepancies between actual stage and the one stored on the blockchain)
  /// @return the actual number of tokens deposited to open a claim
  function getTotalDeposit() public view returns(uint) {
    uint numTokens = totalDeposit;

    if(stage != getStage() && getStage() == Stages.ClaimPeriod)
      numTokens = 0;

    return numTokens;
  }

  /// @notice Returns the actual claim
  /// @dev Returns the actual claim (taking into account discrepancies between actual stage and the one stored on the blockchain)
  /// @return the actual claim
  function getCurrentClaim() public view returns(uint) {
    uint claim = currentClaim;

    if(stage != getStage() && getStage() == Stages.ClaimPeriod)
      claim++;

    return claim;
  }

  /// @notice Calculates the number of tokens to cashout by the user and the ones that go to the ICO launcher
  /// @dev Calculates the number of tokens to cashout by the user and the ones that go to the ICO launcher
  /// @param user Address of he user
  /// @return a tuple with the number of tokens to send to the user and the ICO launcher
  function tokensToCashOut(address user) public view returns (uint, uint) {
    uint tokensToUser;
    uint tokensToIcoLauncher;
    uint claim = claimDeposited[user];

    if(claim != 0) {
      if(claim != getCurrentClaim() || getStage() == Stages.ClaimEnded || getStage() == Stages.Redeem) {
        tokensToUser = userDeposits[user];

        // If the claim did not succeed
        if(claimResults[claim]) {
          // 1% penalization goes to the ICO launcher
          tokensToIcoLauncher = tokensToUser.div(100);
          tokensToUser = tokensToUser.sub(tokensToIcoLauncher);
        }
      }
    }

    return (tokensToUser, tokensToIcoLauncher);
  }

  /// @notice Calculates the amount of ether send to the token holder in exchange of n tokens.
  /// @dev Calculates the amount of ether send to the token holder in exchange of n tokens
  /// @param numTokens Number of tokens to exchange
  /// @return the amount of Ether to be sent in exchange of the tokens
  function calculateEtherPerTokens(uint numTokens) public view returns(uint) {
    uint etherPerTokens = 0;

    if(getStage() == Stages.Redeem) {
      uint weiToWithdraw = calculateWeiToWithdraw();

      // etherPerTokens = ( numTokens * (weiBalanceAtlastClaim - weiToWithdraw) ) / (ERC20(tokenAddress).totalSupply() - tokensInVestingAtLastClaim);
      etherPerTokens = (  numTokens.mul( weiBalanceAtlastClaim.sub(weiToWithdraw) )  ).div( ERC20(tokenAddress).totalSupply().sub(tokensInVestingAtLastClaim) );
    }

    return etherPerTokens;
  }

  /// @notice Returns the amount of Wei available for the ICO launcher to withdraw
  /// @dev Returns the amount of Wei available for the ICO launcher to withdraw
  /// @return the amount of Wei available for the ICO launcher to withdraw
  function calculateWeiToWithdraw() public view returns(uint) {
    uint weiToWithdraw;

    // If there is an ongoing claim, only the ether available until the moment the claim was open can be withdraw
    if(getStage() == Stages.ClaimOpen || getStage() == Stages.Redeem) {
      weiToWithdraw = weiToWithdrawAtLastClaim;
    } else {
      //weiToWithdraw = (now - startDate) * weiPerSecond - weiWithdrawToDate - weiRedeem;
      weiToWithdraw = now.sub(startDate).mul(weiPerSecond).sub(weiWithdrawToDate).sub(weiRedeem);

      if(weiToWithdraw > Vault(vaultAddress).etherBalance())
        weiToWithdraw = Vault(vaultAddress).etherBalance();
    }

    return weiToWithdraw;
  }

  /// @notice Returns true if the CGS is active
  /// @dev Returns true if the CGS is active
  /// NOTE: To be changed for two new stages
  /// @return true if the CGS is active
  function isActive() public view returns(bool) {
    bool active = false;

    if(now >= startDate && calculateWeiToWithdraw() < Vault(vaultAddress).etherBalance())
      active = true;

    return active;
  }

  /// @notice Changes the stage to _stage
  /// @dev Changes the stage to _stage
  /// @param _stage New stage
  function setStage(Stages _stage) private {
    stage = _stage;

    newStageHandler(stage);
  }

  /// @notice Handles the change to a new state
  /// @dev Handles the change to a new state
  /// @param _stage New stage
  function newStageHandler(Stages _stage) private {
    // Executed only once, when the a claim ends
    if(_stage == Stages.ClaimPeriod) {
      totalDeposit = 0;
      currentClaim++;
    }

    ev_NewStage(_stage);
  }
}
