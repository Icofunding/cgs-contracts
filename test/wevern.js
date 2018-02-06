const Wevern = artifacts.require("./Wevern.sol");
const TestToken = artifacts.require("./test/TestToken.sol");
const FakeCGSBinaryVote = artifacts.require("./test/FakeCGSBinaryVote.sol");

contract('Wevern', function(accounts) {
  const ONE_DAY = 24*3600;
  const NOW = Math.floor(Date.now() / 1000);

  let owner;
  let tokenHolder1;
  let tokenHolder2;
  let icoLauncher;

  let FakeCGSBinaryVoteContract;

  before(async () => {
    owner = accounts[0];
    tokenHolder1 = accounts[1];
    tokenHolder2 = accounts[2];
    icoLauncher = accounts[3];

    claimPrice = 500;

    FakeCGSBinaryVoteContract = await FakeCGSBinaryVote.new();
  });

  it("Deployment with initial values", async function() {
    let icoInitialSupply = 1000;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Default value for all variables
    assert.equal(weiPerSecond, (await WevernContract.weiPerSecond.call()).toNumber(), "incorrect weiPerSecond");
    assert.equal(claimPrice, (await WevernContract.claimPrice.call()).toNumber(), "incorrect price");
    assert.equal(icoLauncher, await WevernContract.icoLauncherWallet.call(), "incorrect _icoLauncherWallet");
    assert.equal(TestTokenContract.address, await WevernContract.tokenAddress.call(), "incorrect tokenAddress");
    assert.equal(FakeCGSBinaryVoteContract.address, await WevernContract.cgsVoteAddress.call(), "incorrect cgsVoteAddress");
    assert.equal(0, (await WevernContract.stage.call()).toNumber(), "incorrect stage");
    assert.equal(1, (await WevernContract.currentClaim.call()).toNumber(), "incorrect current claim");
    assert.equal(0, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect total deposit");
    assert.equal(0, (await WevernContract.lastClaim.call()).toNumber(), "incorrect lastClaim");
    assert.equal(0, (await WevernContract.weiWithdrawToDate.call()).toNumber(), "incorrect weiWithdrawToDate");
    assert.equal(NOW, (await WevernContract.startDate.call()).toNumber(), "incorrect date");

  });

  it("Deposit tokens", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(WevernContract.address, numTokensToDeposit, {from: tokenHolder1});
    // Check the event
    let event = (await WevernContract.depositTokens(numTokensToDeposit, {from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_DepositTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), numTokensToDeposit, "incorrect amount");

    // To make sure that the balances are updated correctly
    assert.equal(numTokensToDeposit, (await TestTokenContract.balanceOf.call(WevernContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(numTokensToDeposit, (await WevernContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(numTokensToDeposit, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");

    assert.equal(1, (await WevernContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");
    assert.isFalse(await FakeCGSBinaryVoteContract.isVoteOpen.call(), "incorrect value");
  });

  it("Deposit tokens until a claim is open", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(WevernContract.address, numTokensToDeposit, {from: tokenHolder1});
    await WevernContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Add more tokens
    await TestTokenContract.approve(WevernContract.address, numTokensToDeposit, {from: tokenHolder1});
    await WevernContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Still not enough
    assert.isTrue(await FakeCGSBinaryVoteContract.isVoteOpen.call(), "incorrect value");
    assert.equal(1, await WevernContract.stage.call(), "incorrect value");

    // To make sure that the balances are updated correctly
    assert.equal(numTokensToDeposit*2, (await TestTokenContract.balanceOf.call(WevernContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(numTokensToDeposit*2, (await WevernContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(numTokensToDeposit*2, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Deposit tokens in a different stage should fail");
  it("Deposit tokens while the user has deposits in previous claims should fail");

  it("Withdraw tokens", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let numTokensToWithdraw = 150;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(WevernContract.address, numTokensToDeposit, {from: tokenHolder1});
    await WevernContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Check the event
    let event = (await WevernContract.withdrawTokens(numTokensToWithdraw, {from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_WithdrawTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), numTokensToWithdraw, "incorrect amount");

    assert.equal(1, (await WevernContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");

    // To make sure that the balances are updated correctly
    assert.equal(numTokensToDeposit-numTokensToWithdraw, (await TestTokenContract.balanceOf.call(WevernContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(numTokensToDeposit-numTokensToWithdraw, (await WevernContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(numTokensToDeposit-numTokensToWithdraw, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Withdraw all the tokens", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(weiPerSecond, claimPrice, icoLauncher, TestTokenContract.address, FakeCGSBinaryVoteContract.address, NOW);

    // Approve and transferFrom to move tokens to the contract
    await TestTokenContract.approve(WevernContract.address, numTokensToDeposit, {from: tokenHolder1});
    await WevernContract.depositTokens(numTokensToDeposit, {from: tokenHolder1});

    // Check the event
    await WevernContract.withdrawTokens(numTokensToDeposit, {from: tokenHolder1});

    assert.equal(0, (await WevernContract.claimDeposited.call(tokenHolder1)).toNumber(), "incorrect claim number");

    // To make sure that the balances are updated correctly
    assert.equal(0, (await TestTokenContract.balanceOf.call(WevernContract.address)).toNumber(), "incorrect number of tokens deposited");
    assert.equal(0, (await WevernContract.userDeposits.call(tokenHolder1)).toNumber(), "incorrect number of tokens deposited by user");
    assert.equal(0, (await WevernContract.totalDeposit.call()).toNumber(), "incorrect number of tokens deposited in variable");
  });

  it("Withdraw tokens in a different stage should fail");
  it("Withdraw more tokens than deposited should fail");
  it("Withdraw tokens from previous claims should fail");

  it("Receive a claim result: true", async function() {
    let icoInitialSupply = 1000;
    let roadmapWei = [100, 200, 800, 5000];
    let roadmapDates = [NOW, NOW + ONE_DAY, NOW + ONE_DAY*2, NOW + ONE_DAY*3];

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(roadmapWei, roadmapDates, claimPrice, icoLauncher, TestTokenContract.address);

    // Check the event
    await WevernContract.claimResult(true, {from: fakeCGS});

    // To make sure that the balances are updated correctly
    let currentClaim = (await WevernContract.currentClaim.call()).toNumber();
    assert.isTrue(await WevernContract.claimResults.call(currentClaim), "incorrect value");
    assert.equal(2, (await WevernContract.stage.call()).toNumber(), "incorrect stage");
  });

  it("Receive a claim result: false", async function() {
    let icoInitialSupply = 1000;
    let roadmapWei = [100, 200, 800, 5000];
    let roadmapDates = [NOW, NOW + ONE_DAY, NOW + ONE_DAY*2, NOW + ONE_DAY*3];

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let WevernContract = await Wevern.new(claimPrice, icoLauncher, TestTokenContract.address);

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

  it("Check stages");

  // Also test modifiers to change stage
});
