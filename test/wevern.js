const Wevern = artifacts.require("./Wevern.sol");
const TestToken = artifacts.require("./test/TestToken.sol");
const TestCGS = artifacts.require("./test/TestCGS.sol");


contract('Wevern', function(accounts) {
  let owner;
  let tokenHolder1;
  let tokenHolder2;
  let icoLauncher;

  let fakeCGS;

  let claimPrice = 700;

  before(() => {
    owner = accounts[0];
    tokenHolder1 = accounts[1];
    tokenHolder2 = accounts[2];
    icoLauncher = accounts[3];

    fakeCGS = accounts[5];
  });

  it("Deployment with initial values", async function() {
    let icoInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let TestCGSContract = await TestCGS.new();
    let WevernContract = await Wevern.new(claimPrice, icoLauncher, TestTokenContract.address, TestCGSContract.address);

    // Default value for all variables
    assert.equal(claimPrice, (await WevernContract.claimPrice.call()).toNumber(), "incorrect price");
    assert.equal(icoLauncher, await WevernContract.icoLauncherWallet.call(), "incorrect _icoLauncherWallet");
    assert.equal(TestTokenContract.address, await WevernContract.tokenAddress.call(), "incorrect tokenAddress");
    assert.equal(TestCGSContract.address, await WevernContract.cgsVoteAddress.call(), "incorrect cgsAddress");
    assert.equal(0, (await WevernContract.stage.call()).toNumber(), "incorrect stage");
    assert.equal(1, (await WevernContract.currentClaim.call()).toNumber(), "incorrect current claim");
    assert.equal(0, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect total deposit");
    assert.equal(0, (await WevernContract.lastClaim.call()).toNumber(), "incorrect lastClaim");

  });

  it("Deposit tokens", async function() {
    let icoInitialSupply = 1000;
    let tokensToDeposit = 200;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let TestCGSContract = await TestCGS.new();
    let WevernContract = await Wevern.new(claimPrice, icoLauncher, TestTokenContract.address, TestCGSContract.address);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(WevernContract.address, tokensToDeposit, {from: tokenHolder1});
    // Check the event
    let event = (await WevernContract.depositTokens({from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_DepositTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), tokensToDeposit, "incorrect amount");

    // To make sure that the balances are updated correctly
    assert.equal(tokensToDeposit, (await TestTokenContract.balanceOf.call(WevernContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(tokensToDeposit, (await WevernContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(tokensToDeposit, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");

    assert.equal(1, (await WevernContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");
  });

  it("Deposit tokens until a claim is open", async function() {
    let icoInitialSupply = 1000;
    let tokensToDeposit = 351;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let TestCGSContract = await TestCGS.new();
    let WevernContract = await Wevern.new(claimPrice, icoLauncher, TestTokenContract.address, TestCGSContract.address);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(WevernContract.address, tokensToDeposit, {from: tokenHolder1});
    await WevernContract.depositTokens({from: tokenHolder1});
    // Still not enough
    assert.isFalse(await TestCGSContract.isClaimOpen.call(), "incorrect value");

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(WevernContract.address, tokensToDeposit, {from: tokenHolder1});
    await WevernContract.depositTokens({from: tokenHolder1});
    // The claim is open
    assert.isTrue(await TestCGSContract.isClaimOpen.call(), "incorrect value");
    assert.equal(1, await WevernContract.stage.call(), "incorrect value");

    // To make sure that the balances are updated correctly
    assert.equal(tokensToDeposit*2, (await TestTokenContract.balanceOf.call(WevernContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(tokensToDeposit*2, (await WevernContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(tokensToDeposit*2, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Deposit tokens in a different stage should fail");
  it("Deposit tokens while the user has deposits in previous claims should fail");

  it("Withdraw tokens", async function() {
    let icoInitialSupply = 1000;
    let tokensToDeposit = 200;
    let tokensToWithdraw = 150;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let TestCGSContract = await TestCGS.new();
    let WevernContract = await Wevern.new(claimPrice, icoLauncher, TestTokenContract.address, TestCGSContract.address);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(WevernContract.address, tokensToDeposit, {from: tokenHolder1});
    await WevernContract.depositTokens({from: tokenHolder1});

    // Check the event
    let event = (await WevernContract.withdrawTokens(tokensToWithdraw, {from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_WithdrawTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), tokensToWithdraw, "incorrect amount");

    // To make sure that the balances are updated correctly
    assert.equal(tokensToDeposit-tokensToWithdraw, (await TestTokenContract.balanceOf.call(WevernContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(tokensToDeposit-tokensToWithdraw, (await WevernContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(tokensToDeposit-tokensToWithdraw, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Withdraw all the tokens");
  it("Withdraw tokens in a different stage should fail");
  it("Withdraw more tokens than deposited should fail");
  it("Withdraw tokens from previous claims should fail");

  it("Receive a claim result: true", async function() {
    let icoInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(claimPrice, icoLauncher, TestTokenContract.address, fakeCGS);

    // Check the event
    await WevernContract.claimResult(true, {from: fakeCGS});

    // To make sure that the balances are updated correctly
    let currentClaim = (await WevernContract.currentClaim.call()).toNumber();
    assert.isTrue(await WevernContract.claimResults.call(currentClaim), "incorrect value");
    assert.equal(2, (await WevernContract.stage.call()).toNumber(), "incorrect stage");
  });

  it("Receive a claim result: false", async function() {
    let icoInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(claimPrice, icoLauncher, TestTokenContract.address, fakeCGS);

    // Check the event
    await WevernContract.claimResult(false, {from: fakeCGS});

    // To make sure that the balances are updated correctly
    let currentClaim = (await WevernContract.currentClaim.call()).toNumber();
    assert.isFalse(await WevernContract.claimResults.call(currentClaim), "incorrect value");
    assert.equal(3, (await WevernContract.stage.call()).toNumber(), "incorrect stage");
  });

  it("Cash out the last claim when succeded");
  it("Cash out the last claim when did not succeed");
  it("Cash out an old claim");
  it("Cash out with 0 tokens deposited shouldn't return any token");
  it("Cash out the last claim before it ends should fail");

  it("Redeem tokens for ether");
  it("Redeem 0 tokens");
  it("Redeem in a different stage should fail");

  // Also test modifiers to change stage
});
