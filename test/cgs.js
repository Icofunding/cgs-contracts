const increaseTime = require("./helpers/increaseTime.js");
const mineBlock = require("./helpers/mineBlock.js");
const CGS = artifacts.require("./CGS.sol");
const Vault = artifacts.require("./Vault.sol");
const TestToken = artifacts.require("./test/TestToken.sol");
const FakeCGSBinaryVote = artifacts.require("./test/FakeCGSBinaryVote.sol");
const CGSBinaryVote = artifacts.require("./CGSBinaryVote.sol");

contract('CGS', function(accounts) {
  const ONE_DAY = 24*3600;
  const CLAIM_PERIOD_STAGE = 0;
  const CLAIM_OPEN_STAGE = 1;
  const REDEEM_STAGE = 2;
  const CLAIM_ENDED_STAGE = 3;
  const TIME_TO_VOTE = 7*ONE_DAY;
  const TIME_TO_REVEAL = 3*ONE_DAY;
  const TIME_FOR_REDEEM = 10*ONE_DAY;
  const TIME_BETWEEN_CLAIMS = 100*ONE_DAY;

  let owner;
  let tokenHolder1;
  let tokenHolder2;
  let icoLauncher;

  let tokenName;
  let tokenSymbol;
  let tokenDecimals;

  let claimPrice;
  let isClaimPriceVariable;

  let FakeCGSBinaryVoteContract;

  before(async () => {
    owner = accounts[0];
    tokenHolder1 = accounts[1];
    tokenHolder2 = accounts[2];
    icoLauncher = accounts[3];

    tokenName = "ICO Token";
    tokenSymbol = "ICOT";
    tokenDecimals = 18;

    claimPrice = 500;
    isClaimPriceVariable = false;

    FakeCGSBinaryVoteContract = await FakeCGSBinaryVote.new();
  });

  it("Deployment with initial values", async function() {
    let icoInitialSupply = 1000;
    let weiPerSecond = 5;
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);

    // Default value for all variables
    assert.equal(weiPerSecond, (await CGSContract.weiPerSecond.call()).toNumber(), "incorrect weiPerSecond");
    assert.equal(claimPrice, (await CGSContract.claimPrice.call()).toNumber(), "incorrect price");
    assert.equal(icoLauncher, await CGSContract.icoLauncherWallet.call(), "incorrect _icoLauncherWallet");
    assert.equal(TestTokenContract.address, await CGSContract.tokenAddress.call(), "incorrect tokenAddress");
    assert.equal(CLAIM_PERIOD_STAGE, (await CGSContract.stage.call()).toNumber(), "incorrect stage");
    assert.equal(1, (await CGSContract.currentClaim.call()).toNumber(), "incorrect current claim");
    assert.equal(0, (await CGSContract.totalDeposit.call()).toNumber(), "incorrect total deposit");
    assert.equal(0, (await CGSContract.lastClaim.call()).toNumber(), "incorrect lastClaim");
    assert.equal(0, (await CGSContract.weiWithdrawToDate.call()).toNumber(), "incorrect weiWithdrawToDate");
    assert.equal(0, (await CGSContract.weiRedeem.call()).toNumber(), "incorrect weiRedeem");
    assert.equal(timestamp, (await CGSContract.startDate.call()).toNumber(), "incorrect date");
    assert.isFalse(await CGSContract.isActive.call(), "incorrect value");
    assert.isFalse(await CGSContract.isClaimPriceVariable.call(), "incorrect value");
  });

  it("Set CGSVote as owner", async function() {
    let icoInitialSupply = 1000;
    let weiPerSecond = 5;
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    assert.equal(FakeCGSBinaryVoteContract.address, await CGSContract.cgsVoteAddress.call(), "incorrect cgsVoteAddress");
  });

  it("Check variable claim Price", async function() {
    let icoInitialSupply = 1000;
    let numTokensToMint = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    claimPriceVariable = 5;
    isClaimPriceVariableTrue = true;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPriceVariable, isClaimPriceVariableTrue, icoLauncher, TestTokenContract.address, timestamp);

    assert.equal(0.05 * icoInitialSupply, (await CGSContract.getClaimPriceTokens.call()).toNumber(), "incorrect variable claim price");

    await TestTokenContract.mint(owner, numTokensToMint);

    assert.equal(0.05 * (icoInitialSupply + numTokensToMint), (await CGSContract.getClaimPriceTokens.call()).toNumber(), "incorrect variable claim price");
  });

  it("Check stages with redeem", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit to activate the CGS
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Waiting to open a claim
    assert.equal(CLAIM_PERIOD_STAGE, await CGSContract.getStage.call(), "incorrect value");

    // Approve and transferFrom to move tokens to the contract to open a claim
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // A claim is open
    assert.equal(CLAIM_OPEN_STAGE, await CGSContract.getStage.call(), "incorrect value");

    // Simulate the vote
    await increaseTime(TIME_TO_VOTE + TIME_TO_REVEAL);
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // The claim starts redeen stage
    assert.equal(REDEEM_STAGE, await CGSContract.getStage.call(), "incorrect value");

    await increaseTime(TIME_FOR_REDEEM);

    // The claim has ended
    assert.equal(CLAIM_ENDED_STAGE, await CGSContract.getStage.call(), "incorrect value");

    await increaseTime(TIME_BETWEEN_CLAIMS);

    // The project goes back to open claim period
    assert.equal(CLAIM_PERIOD_STAGE, await CGSContract.getStage.call(), "incorrect value");
    assert.equal(0, await CGSContract.getTotalDeposit.call(), "incorrect value");
    assert.equal(2, await CGSContract.getCurrentClaim.call(), "incorrect value");
    // To force the change in the contract itself
    await CGSContract.cashOut({from: tokenHolder1});    
  });

  it("Check stages without redeem", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit to activate the CGS
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Waiting to open a claim
    assert.equal(CLAIM_PERIOD_STAGE, await CGSContract.getStage.call(), "incorrect value");

    // Approve and transferFrom to move tokens to the contract to open a claim
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // A claim is open
    assert.equal(CLAIM_OPEN_STAGE, await CGSContract.getStage.call(), "incorrect value");

    // Simulate the vote
    await increaseTime(TIME_TO_VOTE + TIME_TO_REVEAL);
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), true);

    // The claim has ended
    assert.equal(CLAIM_ENDED_STAGE, await CGSContract.getStage.call(), "incorrect value");

    await increaseTime(TIME_BETWEEN_CLAIMS);

    // The project goes back to open claim period
    assert.equal(CLAIM_PERIOD_STAGE, await CGSContract.getStage.call(), "incorrect value");
    assert.equal(0, await CGSContract.getTotalDeposit.call(), "incorrect value");
    assert.equal(2, await CGSContract.getCurrentClaim.call(), "incorrect value");
    // To force the change in the contract itself
    await CGSContract.cashOut({from: tokenHolder1});
  });

  it("Deposit tokens", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    // Check the event
    let event = (await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_DepositTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), numTokensToDeposit, "incorrect amount");

    // To make sure that the balances are updated correctly
    assert.equal(numTokensToDeposit, (await TestTokenContract.balanceOf.call(CGSContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(numTokensToDeposit, (await CGSContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(numTokensToDeposit, (await CGSContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");

    assert.equal(1, (await CGSContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");
  });

  it("Deposit tokens until a claim is open", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Add more tokens
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Still not enough
    assert.isTrue(await FakeCGSBinaryVoteContract.isVoteOpen.call(), "incorrect value");
    assert.equal(CLAIM_OPEN_STAGE, await CGSContract.stage.call(), "incorrect value");

    // To make sure that the balances are updated correctly
    assert.equal(numTokensToDeposit*2, (await TestTokenContract.balanceOf.call(CGSContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(numTokensToDeposit*2, (await CGSContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(numTokensToDeposit*2, (await CGSContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Deposit tokens in a different stage should fail");
  it("Deposit tokens while the user has deposits in previous claims should fail");

  it("Withdraw tokens", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let numTokensToWithdraw = 150;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Check the event
    let event = (await CGSContract.withdrawTokens(numTokensToWithdraw, {from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_WithdrawTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), numTokensToWithdraw, "incorrect amount");

    assert.equal(1, (await CGSContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");

    // To make sure that the balances are updated correctly
    assert.equal(numTokensToDeposit-numTokensToWithdraw, (await TestTokenContract.balanceOf.call(CGSContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(numTokensToDeposit-numTokensToWithdraw, (await CGSContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(numTokensToDeposit-numTokensToWithdraw, (await CGSContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Withdraw all the tokens", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    await CGSContract.withdrawTokens(numTokensToDeposit, {from: tokenHolder1});

    assert.equal(0, (await CGSContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");

    // To make sure that the balances are updated correctly
    assert.equal(0, (await TestTokenContract.balanceOf.call(CGSContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(0, (await CGSContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(0, (await CGSContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Withdraw tokens in a different stage should fail");
  it("Withdraw more tokens than deposited should fail");
  it("Withdraw tokens from previous claims should fail");

  it("Receive a voting result: true, everything is ok with the project", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), true);

    // To make sure that the balances are updated correctly
    assert.isTrue(await CGSContract.claimResults.call(currentClaim), "incorrect value");
    assert.equal(CLAIM_ENDED_STAGE, (await CGSContract.stage.call()).toNumber(), "incorrect stage");
  });

  it("Receive a voting result: false, there are issues with the project", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // To make sure that the balances are updated correctly
    assert.isFalse(await CGSContract.claimResults.call(currentClaim), "incorrect value");
    assert.equal(REDEEM_STAGE, (await CGSContract.stage.call()).toNumber(), "incorrect stage");
  });
/*
  it("Check integration between CGS and CGSBinaryVote and transition with no votes", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let numTokensToRedeem = 100;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("2", "Ether");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, CGSBinaryVoteContract.address, timestamp);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    increaseTime(TIME_TO_VOTE);
    increaseTime(TIME_TO_REVEAL);

    // Approve and transferFrom to redeem tokens
    await TestTokenContract.approve(CGSContract.address, numTokensToRedeem, {from: tokenHolder1});
    await CGSContract.redeem(numTokensToRedeem, {from: tokenHolder1});

    // To make sure that the balances are updated correctly
    let VaultContract = Vault.at(await CGSContract.vaultAddress.call());
    let weiToWithdraw = 0;
    // The tokens have move from ICO holder to ICO launcher
    assert.equal(icoInitialSupply - numTokensToDeposit - numTokensToRedeem, (await TestTokenContract.balanceOf.call(tokenHolder1)).toNumber(), "incorrect value");
    assert.equal(numTokensToRedeem, (await CGSContract.tokensInVesting.call()).toNumber(), "incorrect value");
  });
*/
  it("Redeem tokens for ether", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let numTokensToRedeem = 100;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("2", "Ether");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // To check
    let percentOfTokens = numTokensToRedeem/icoInitialSupply;
    let remainingEther = weiToDeposit - (await CGSContract.calculateWeiToWithdraw.call()).toNumber();
    
    let previousBalance = parseInt(await web3.eth.getBalance(tokenHolder1));

    // Approve and transferFrom to redeem tokens
    await TestTokenContract.approve(CGSContract.address, numTokensToRedeem, {from: tokenHolder1});
    await CGSContract.redeem(numTokensToRedeem, {from: tokenHolder1});

    // To make sure that the balances are updated correctly
    let weiReceived = parseInt(await web3.eth.getBalance(tokenHolder1)) - previousBalance;
    let VaultContract = Vault.at(await CGSContract.vaultAddress.call());

    // The % of ether corresponds with the % of tokens
    assert.approximately(percentOfTokens, weiReceived/remainingEther, 0.01, "incorrect percent of wei");
    // Correct amount of ether Redeemed
    assert.equal(percentOfTokens*remainingEther, await CGSContract.weiRedeem.call(), "incorrect value");
    // The tokens have move from ICO holder to ICO launcher
    assert.equal(icoInitialSupply - numTokensToDeposit - numTokensToRedeem, (await TestTokenContract.balanceOf.call(tokenHolder1)).toNumber(), "incorrect value");
    assert.equal(numTokensToRedeem, (await CGSContract.tokensInVesting.call()).toNumber(), "incorrect value");
  });

  it("Redeem tokens for ether multiple times", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let numTokensToRedeem = 100;
    let numTokensToRedeem2 = 50;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("2", "Ether");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // To check
    let percentOfTokens = numTokensToRedeem2/icoInitialSupply;

    // Approve and transferFrom to redeem tokens
    await TestTokenContract.approve(CGSContract.address, numTokensToRedeem, {from: tokenHolder1});
    await CGSContract.redeem(numTokensToRedeem, {from: tokenHolder1});

    // To check
    let remainingEther = weiToDeposit - (await CGSContract.calculateWeiToWithdraw.call()).toNumber();
    let previousBalance = parseInt(await web3.eth.getBalance(tokenHolder1));

    // Approve and transferFrom to redeem tokens
    await TestTokenContract.approve(CGSContract.address, numTokensToRedeem2, {from: tokenHolder1});
    await CGSContract.redeem(numTokensToRedeem2, {from: tokenHolder1});

    // To make sure that the balances are updated correctly
    let weiReceived = parseInt(await web3.eth.getBalance(tokenHolder1)) - previousBalance;

    // The % of ether corresponds with the % of tokens
    assert.approximately(percentOfTokens, weiReceived/remainingEther, 0.01, "incorrect percent of wei");
  });

  it("Redeem in a different stage should fail");

  it("Withdraw locked tokens by ICO launcher", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let numTokensToRedeem = 400;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // Approve and transferFrom to redeem tokens
    await TestTokenContract.approve(CGSContract.address, numTokensToRedeem, {from: tokenHolder1});
    await CGSContract.redeem(numTokensToRedeem, {from: tokenHolder1});

    // Withdraw the tokens when there is no ether in Vault
    await increaseTime(ONE_DAY * 20);
    await CGSContract.withdrawWei({from: icoLauncher});
    await CGSContract.withdrawLockedTokens({from: icoLauncher});

    assert.equal(0, (await CGSContract.tokensInVesting.call()).toNumber(), "incorrect value");
    assert.equal(numTokensToRedeem, (await TestTokenContract.balanceOf.call(icoLauncher)).toNumber(), "incorrect value");
  });

  it("Check the number of tokens to cash out when succeded", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // tokens to Cash out
    let tokensToCashOut = await CGSContract.tokensToCashOut.call(tokenHolder1);

    // 100% tokens to user
    assert.equal(numTokensToDeposit, tokensToCashOut[0].toNumber(), "incorrect value");
    // 0% tokens to ICo launcher
    assert.equal(0, tokensToCashOut[1].toNumber(), "incorrect value");
  });

  it("Check the number of tokens to cash out when the claim fails", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), true);

    // tokens to Cash out
    let tokensToCashOut = await CGSContract.tokensToCashOut.call(tokenHolder1);

    // 100% tokens to user
    assert.equal(numTokensToDeposit*0.99, tokensToCashOut[0].toNumber(), "incorrect value");
    // 0% tokens to ICo launcher
    assert.equal(numTokensToDeposit*0.01, tokensToCashOut[1].toNumber(), "incorrect value");
  });

  it("Cash out the last claim when succeded", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // Cash out
    await CGSContract.cashOut({from: tokenHolder1});

    assert.equal(0, (await CGSContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");
    assert.equal(0, (await CGSContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    // The tokens have move from Contract to ICO launcher
    assert.equal(0, (await TestTokenContract.balanceOf.call(CGSContract.address)).toNumber(), "incorrect value");
    assert.equal(icoInitialSupply, (await TestTokenContract.balanceOf.call(tokenHolder1)).toNumber(), "incorrect value");
  });

  it("Cash out the last claim when did not succeed", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("200", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), true);

    // Cash out
    await CGSContract.cashOut({from: tokenHolder1});

    assert.equal(0, (await CGSContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");
    assert.equal(0, (await CGSContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    // The tokens have move from Contract to ICO launcher
    assert.equal(0, (await TestTokenContract.balanceOf.call(CGSContract.address)).toNumber(), "incorrect value");
    assert.equal(icoInitialSupply - numTokensToDeposit*0.01, (await TestTokenContract.balanceOf.call(tokenHolder1)).toNumber(), "incorrect value");
    assert.equal(numTokensToDeposit*0.01, (await TestTokenContract.balanceOf.call(icoLauncher)).toNumber(), "incorrect value");
  });

  it("Cash out an old claim", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 1;
    let weiToDeposit = web3.utils.toWei("1", "ether");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);
    await TestTokenContract.mint(tokenHolder2, numTokensToDeposit);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    await increaseTime(TIME_TO_VOTE + TIME_TO_REVEAL);
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    await FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), true);

    // Open a new claim
    await increaseTime(TIME_BETWEEN_CLAIMS);
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder2});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder2});

    // Cash out an old claim
    await CGSContract.cashOut({from: tokenHolder1});

    assert.equal(0, (await CGSContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");
    assert.equal(0, (await CGSContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    // The first numTokensToDeposit tokens have move from Contract to ICO launcher
    assert.equal(numTokensToDeposit, (await TestTokenContract.balanceOf.call(CGSContract.address)).toNumber(), "incorrect value");
    assert.equal(icoInitialSupply - numTokensToDeposit*0.01, (await TestTokenContract.balanceOf.call(tokenHolder1)).toNumber(), "incorrect value");
    assert.equal(numTokensToDeposit*0.01, (await TestTokenContract.balanceOf.call(icoLauncher)).toNumber(), "incorrect value");
  });

  it("Cash out the last claim before it ends should fail");

  // Important
  it("Check wei to withdraw by the ICO launcher after the CGS ends", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("20000", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    let secondsWithFunding = weiToDeposit/weiPerSecond;

    await increaseTime(secondsWithFunding);

    assert.equal(weiToDeposit, (await CGSContract.calculateWeiToWithdraw.call()).toNumber(), "incorrect wei value");
  });

  it("Check wei to withdraw by the ICO launcher before the CGS ends", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("500000", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    await increaseTime(ONE_DAY);

    let secondsWithFunding = weiToDeposit/weiPerSecond;
    let percerntOfTime = ONE_DAY/secondsWithFunding;

    let weiToWithdraw = (await CGSContract.calculateWeiToWithdraw.call()).toNumber();

    // % of time corresponds to % of wei to withdraw
    assert.approximately(percerntOfTime, weiToWithdraw/weiToDeposit, 0.0001, "incorrect wei value");
  });

  it("Check wei to withdraw by the ICO launcher with a claim open", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("500000", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    await increaseTime(ONE_DAY);

    // Open a claim
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // This day shouldn't be taken into account
    await increaseTime(ONE_DAY);

    let secondsWithFunding = weiToDeposit/weiPerSecond;
    let percerntOfTime = ONE_DAY/secondsWithFunding;

    let weiToWithdraw = (await CGSContract.calculateWeiToWithdraw.call()).toNumber();

    // % of time corresponds to % of wei to withdraw
    assert.approximately(percerntOfTime, weiToWithdraw/weiToDeposit, 0.0001, "incorrect wei value");
  });

  it("Withdraw ether by ICO launcher", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("500000", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    await increaseTime(ONE_DAY);

    let secondsWithFunding = weiToDeposit/weiPerSecond;
    let percerntOfTime = ONE_DAY/secondsWithFunding;

    let prevBalance = parseInt(await web3.eth.getBalance(await CGSContract.vaultAddress.call()));
    await CGSContract.withdrawWei({from: icoLauncher});
    let newBalance = parseInt(await web3.eth.getBalance(await CGSContract.vaultAddress.call()));
    let etherWithdrawn = prevBalance - newBalance;

    // % of time corresponds to % of wei withdrawn
    assert.approximately(percerntOfTime, etherWithdrawn/weiToDeposit, 0.0001, "incorrect wei value");
  });

  it("Withdraw ether by non-ICO launcher should fail");

  it("Withdraw ether by the ICO launcher with a claim open", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("500000", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    await increaseTime(ONE_DAY);

    // Open a claim
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // This day shouldn't be taken into account
    await increaseTime(ONE_DAY);

    let secondsWithFunding = weiToDeposit/weiPerSecond;
    let percerntOfTime = ONE_DAY/secondsWithFunding;

    let prevBalance = parseInt(await web3.eth.getBalance(await CGSContract.vaultAddress.call()));
    await CGSContract.withdrawWei({from: icoLauncher});
    let newBalance = parseInt(await web3.eth.getBalance(await CGSContract.vaultAddress.call()));
    let etherWithdrawn = prevBalance - newBalance;

    // % of time corresponds to % of wei withdrawn
    assert.approximately(percerntOfTime, etherWithdrawn/weiToDeposit, 0.0001, "incorrect wei value");
  });

  it("Withdraw ether by the ICO launcher with a claim open multiple times", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;
    let weiToDeposit = web3.utils.toWei("2000000", "Wei");
    let timestamp = (await web3.eth.getBlock("latest")).timestamp;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, timestamp);
    await CGSContract.setCGSVoteAddress(FakeCGSBinaryVoteContract.address);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    await increaseTime(ONE_DAY);

    // Open a claim
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // This day shouldn't be taken into account
    await increaseTime(ONE_DAY);

    let secondsWithFunding = weiToDeposit/weiPerSecond;
    let percerntOfTime = ONE_DAY/secondsWithFunding;

    let prevBalance = parseInt(await web3.eth.getBalance(await CGSContract.vaultAddress.call()));
    await CGSContract.withdrawWei({from: icoLauncher});
    let newBalance = parseInt(await web3.eth.getBalance(await CGSContract.vaultAddress.call()));
    await CGSContract.withdrawWei({from: icoLauncher});
    let newBalance2 = parseInt(await web3.eth.getBalance(await CGSContract.vaultAddress.call()));

    // % of time corresponds to % of wei withdrawn
    assert.equal(newBalance, newBalance2, "incorrect wei value");
  });

  // Also test modifiers to change stage
});
