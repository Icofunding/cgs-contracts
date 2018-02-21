const CGS = artifacts.require("./CGS.sol");
const Vault = artifacts.require("./Vault.sol");
const TestToken = artifacts.require("./test/TestToken.sol");
const FakeCGSBinaryVote = artifacts.require("./test/FakeCGSBinaryVote.sol");

contract('CGS', function(accounts) {
  const ONE_DAY = 24*3600;
  const NOW = Math.floor(Date.now() / 1000);
  const CLAIM_PERIOD_STAGE = 0;
  const CLAIM_OPEN_STAGE = 1;
  const REDEEM_STAGE = 2;
  const CLAIM_ENDED_STAGE = 3;

  let owner;
  let tokenHolder1;
  let tokenHolder2;
  let icoLauncher;

  let tokenName;
  let tokenSymbol;
  let tokenDecimals;

  let claimPrice;

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

    FakeCGSBinaryVoteContract = await FakeCGSBinaryVote.new();
  });

  it("Deployment with initial values", async function() {
    let icoInitialSupply = 1000;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Default value for all variables
    assert.equal(weiPerSecond, (await CGSContract.weiPerSecond.call()).toNumber(), "incorrect weiPerSecond");
    assert.equal(claimPrice, (await CGSContract.claimPrice.call()).toNumber(), "incorrect price");
    assert.equal(icoLauncher, await CGSContract.icoLauncherWallet.call(), "incorrect _icoLauncherWallet");
    assert.equal(TestTokenContract.address, await CGSContract.tokenAddress.call(), "incorrect tokenAddress");
    assert.equal(FakeCGSBinaryVoteContract.address, await CGSContract.cgsVoteAddress.call(), "incorrect cgsVoteAddress");
    assert.equal(CLAIM_PERIOD_STAGE, (await CGSContract.stage.call()).toNumber(), "incorrect stage");
    assert.equal(1, (await CGSContract.currentClaim.call()).toNumber(), "incorrect current claim");
    assert.equal(0, (await CGSContract.totalDeposit.call()).toNumber(), "incorrect total deposit");
    assert.equal(0, (await CGSContract.lastClaim.call()).toNumber(), "incorrect lastClaim");
    assert.equal(0, (await CGSContract.weiWithdrawToDate.call()).toNumber(), "incorrect weiWithdrawToDate");
    assert.equal(NOW, (await CGSContract.startDate.call()).toNumber(), "incorrect date");

  });

  it("Deposit tokens", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

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
    assert.isFalse(await FakeCGSBinaryVoteContract.isVoteOpen.call(), "incorrect value");
  });

  it("Deposit tokens until a claim is open", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

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

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

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

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Check the event
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

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), true);

    // To make sure that the balances are updated correctly
    assert.isTrue(await CGSContract.claimResults.call(currentClaim), "incorrect value");
    assert.equal(CLAIM_ENDED_STAGE, (await CGSContract.stage.call()).toNumber(), "incorrect stage");
  });

  it("Receive a voting result: false, there are issues with the project", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // To make sure that the balances are updated correctly
    assert.isFalse(await CGSContract.claimResults.call(currentClaim), "incorrect value");
    assert.equal(REDEEM_STAGE, (await CGSContract.stage.call()).toNumber(), "incorrect stage");
  });

  it("Redeem tokens for ether", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let numTokensToRedeem = 100;
    let weiPerSecond = 5;
    let weiToDeposit = web3.toWei("2", "Ether");

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Simulate ICO deposit
    let VaultAddress = await CGSContract.vaultAddress.call();
    await web3.eth.sendTransaction({from: icoLauncher, to: VaultAddress, value: weiToDeposit});

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

    // Approve and transferFrom to redeem tokens
    await TestTokenContract.approve(CGSContract.address, numTokensToRedeem, {from: tokenHolder1});
    await CGSContract.redeem(numTokensToRedeem, {from: tokenHolder1});

    // To make sure that the balances are updated correctly
    let VaultContract = Vault.at(await CGSContract.vaultAddress.call());
    let weiToWithdraw = 0;
    // TODO: Test the amount of ether sent to the token holder from the Vault. The formula have to change.
    //assert.equal(weiToDeposit - weiToWithdraw, (await web3.eth.getBalance(VaultAddress)).toNumber(), "incorrect value");
    // The tokens have move from ICO holder to ICO launcher
    assert.equal(icoInitialSupply - numTokensToDeposit - numTokensToRedeem, (await TestTokenContract.balanceOf.call(tokenHolder1)).toNumber(), "incorrect value");
    assert.equal(numTokensToRedeem, (await CGSContract.tokensInVesting.call()).toNumber(), "incorrect value");
  });

  it("Redeem 0 tokens");

  it("Redeem in a different stage should fail");

  it("Cash out the last claim when succeded", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 500;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), false);

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

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSContract = await CGS.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(CGSContract.address, numTokensToDeposit, {from: tokenHolder1});
    await CGSContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Simulate the vote
    let currentClaim = (await CGSContract.currentClaim.call()).toNumber();
    FakeCGSBinaryVoteContract.finalizeVote((await CGSContract.voteIds.call(currentClaim)).toNumber(), true);

    // Cash out
    await CGSContract.cashOut({from: tokenHolder1});

    assert.equal(0, (await CGSContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");
    assert.equal(0, (await CGSContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    // The tokens have move from Contract to ICO launcher
    assert.equal(0, (await TestTokenContract.balanceOf.call(CGSContract.address)).toNumber(), "incorrect value");
    assert.equal(icoInitialSupply - numTokensToDeposit*0.01, (await TestTokenContract.balanceOf.call(tokenHolder1)).toNumber(), "incorrect value");
    assert.equal(numTokensToDeposit*0.01, (await TestTokenContract.balanceOf.call(icoLauncher)).toNumber(), "incorrect value");
  });

  it("Cash out an old claim");
  it("Cash out with 0 tokens deposited shouldn't return any token");
  it("Cash out the last claim before it ends should fail");

  it("Check stages");

  it("Withdraw ether by ICO launcher");
  it("Withdraw ether by non-ICO launcher should fail");
  it("Withdraw ether with a claim open should fail");

  // Also test modifiers to change stage
});
