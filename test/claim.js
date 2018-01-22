const Claim = artifacts.require("./Claim.sol");
const TestToken = artifacts.require("./test/TestToken.sol");


contract('Claim', function(accounts) {
  let owner;
  let tokenHolder1;
  let tokenHolder2;
  let icoLauncher;

  let fakeCGS;
  let fakeVault;

  let claimPrice = 700;

  before(() => {
    owner = accounts[0];
    tokenHolder1 = accounts[1];
    tokenHolder2 = accounts[2];
    icoLauncher = accounts[3];

    fakeCGS = accounts[4];
    fakeVault = accounts[5];
  });

  it("Deployment with initial values", async function() {
    let icoInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let ClaimContract = await Claim.new(claimPrice, icoLauncher, TestTokenContract.address, fakeVault, fakeCGS);

    assert.equal(claimPrice, (await ClaimContract.claimPrice.call()).toNumber(), "incorrect price");
    assert.equal(icoLauncher, await ClaimContract.icoLauncherWallet.call(), "incorrect _icoLauncherWallet");
    assert.equal(TestTokenContract.address, await ClaimContract.tokenAddress.call(), "incorrect tokenAddress");
    assert.equal(fakeVault, await ClaimContract.vaultAddress.call(), "incorrect _vaultAddress");
    assert.equal(fakeCGS, await ClaimContract.cgsAddress.call(), "incorrect cgsAddress");
    assert.equal(0, (await ClaimContract.stage.call()).toNumber(), "incorrect stage");
  });

  it("Deposit tokens", async function() {
    let icoInitialSupply = 1000;
    let tokensToDeposit = 200;

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply);
    let ClaimContract = await Claim.new(claimPrice, icoLauncher, TestTokenContract.address, fakeVault, fakeCGS);

    await TestTokenContract.approve(ClaimContract.address, tokensToDeposit, {from: tokenHolder1});
    let event = (await ClaimContract.depositTokens({from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_DepositTokens', "incorrect event name");
    assert.equal(event.args.who, tokenHolder1, "incorrect sender");
    assert.equal(event.args.amount.toNumber(), tokensToDeposit, "incorrect amount");

    assert.equal(tokensToDeposit, (await TestTokenContract.balanceOf.call(ClaimContract.address)).toNumber(), "incorrect number of tokens deposited");
  });
});

function handleException(error) {
  assert(error.toString().indexOf("invalid JUMP") != -1 || error.toString().indexOf("out of gas") != -1 || error.toString().indexOf("invalid opcode") != -1, error.toString());
}
