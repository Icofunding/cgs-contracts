const Claim = artifacts.require("./Claim.sol");
const TestToken = artifacts.require("./test/TestToken.sol");
const TestCGS = artifacts.require("./test/TestCGS.sol");


contract('Claim', function(accounts) {
  let owner;
  let tokenHolder1;
  let tokenHolder2;
  let icoLauncher;

  let fakeVault;

  let claimPrice = 700;

  before(() => {
    owner = accounts[0];
    tokenHolder1 = accounts[1];
    tokenHolder2 = accounts[2];
    icoLauncher = accounts[3];

    fakeVault = accounts[4];
  });

  it("Deployment with initial values", async function() {
    let icoInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let TestCGSContract = await TestCGS.new();
    let ClaimContract = await Claim.new(claimPrice, icoLauncher, TestTokenContract.address, fakeVault, TestCGSContract.address);

    // Default value for all variables
    assert.equal(claimPrice, (await ClaimContract.claimPrice.call()).toNumber(), "incorrect price");
    assert.equal(icoLauncher, await ClaimContract.icoLauncherWallet.call(), "incorrect _icoLauncherWallet");
    assert.equal(TestTokenContract.address, await ClaimContract.tokenAddress.call(), "incorrect tokenAddress");
    assert.equal(fakeVault, await ClaimContract.vaultAddress.call(), "incorrect _vaultAddress");
    assert.equal(TestCGSContract.address, await ClaimContract.cgsAddress.call(), "incorrect cgsAddress");
    assert.equal(0, (await ClaimContract.stage.call()).toNumber(), "incorrect stage");
    assert.equal(1, (await ClaimContract.currentClaim.call()).toNumber(), "incorrect current claim");
    assert.equal(0, (await ClaimContract.totalDeposit.call()).toNumber(), "incorrect total deposit");
    assert.equal(0, (await ClaimContract.lastClaim.call()).toNumber(), "incorrect lastClaim");

  });

  it("Deposit tokens", async function() {
    let icoInitialSupply = 1000;
    let tokensToDeposit = 200;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let TestCGSContract = await TestCGS.new();
    let ClaimContract = await Claim.new(claimPrice, icoLauncher, TestTokenContract.address, fakeVault, TestCGSContract.address);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(ClaimContract.address, tokensToDeposit, {from: tokenHolder1});
    // Check the event
    let event = (await ClaimContract.depositTokens({from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_DepositTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), tokensToDeposit, "incorrect amount");

    // To make sure that the balances are updated correctly
    assert.equal(tokensToDeposit, (await TestTokenContract.balanceOf.call(ClaimContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(tokensToDeposit, (await ClaimContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(tokensToDeposit, (await ClaimContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");

    assert.equal(1, (await ClaimContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");
  });

  it("Deposit tokens until a claim is open", async function() {
    let icoInitialSupply = 1000;
    let tokensToDeposit = 351;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let TestCGSContract = await TestCGS.new();
    let ClaimContract = await Claim.new(claimPrice, icoLauncher, TestTokenContract.address, fakeVault, TestCGSContract.address);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(ClaimContract.address, tokensToDeposit, {from: tokenHolder1});
    await ClaimContract.depositTokens({from: tokenHolder1});
    // Still not enough
    assert.isFalse(await TestCGSContract.isClaimOpen.call(), "incorrect value");

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(ClaimContract.address, tokensToDeposit, {from: tokenHolder1});
    await ClaimContract.depositTokens({from: tokenHolder1});
    // The claim is open
    assert.isTrue(await TestCGSContract.isClaimOpen.call(), "incorrect value");
    assert.equal(1, await ClaimContract.stage.call(), "incorrect value");

    // To make sure that the balances are updated correctly
    assert.equal(tokensToDeposit*2, (await TestTokenContract.balanceOf.call(ClaimContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(tokensToDeposit*2, (await ClaimContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(tokensToDeposit*2, (await ClaimContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Deposit tokens in a different stage should fail");
  it("Deposit tokens while the user has deposits in previous claims should fail");

  it("Withdraw tokens", async function() {
    let icoInitialSupply = 1000;
    let tokensToDeposit = 200;
    let tokensToWithdraw = 150;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let TestCGSContract = await TestCGS.new();
    let ClaimContract = await Claim.new(claimPrice, icoLauncher, TestTokenContract.address, fakeVault, TestCGSContract.address);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(ClaimContract.address, tokensToDeposit, {from: tokenHolder1});
    await ClaimContract.depositTokens({from: tokenHolder1});

    // Check the event
    let event = (await ClaimContract.withdrawTokens(tokensToWithdraw, {from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_WithdrawTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), tokensToWithdraw, "incorrect amount");

    // To make sure that the balances are updated correctly
    assert.equal(tokensToDeposit-tokensToWithdraw, (await TestTokenContract.balanceOf.call(ClaimContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(tokensToDeposit-tokensToWithdraw, (await ClaimContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(tokensToDeposit-tokensToWithdraw, (await ClaimContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Withdraw all the tokens");
  it("Withdraw tokens in a different stage should fail");
  it("Withdraw more tokens than deposited should fail");
  it("Withdraw tokens from previous claims should fail");
});
