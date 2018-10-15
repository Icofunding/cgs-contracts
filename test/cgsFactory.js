const CGS = artifacts.require("./CGS.sol");
const CGSFactory = artifacts.require("./CGSFactory.sol");
const TestToken = artifacts.require("./test/TestToken.sol");
const FakeCGSBinaryVote = artifacts.require("./test/FakeCGSBinaryVote.sol");

contract('CGS Factory', function(accounts) {
  const NOW = web3.eth.getBlock("latest").timestamp;

  let owner;
  let tokenHolder1;
  let tokenHolder2;
  let icoLauncher;

  let FakeCGSBinaryVoteContract;

  let claimPrice;
  let isClaimPriceVariable;

  before(async () => {
    owner = accounts[0];
    tokenHolder1 = accounts[1];
    tokenHolder2 = accounts[2];
    icoLauncher = accounts[3];

    claimPrice = 500;
    isClaimPriceVariable = false;

    FakeCGSBinaryVoteContract = await FakeCGSBinaryVote.new();
  });

  it("Deployment with initial values", async function() {
    let CGSFactoryContract = await CGSFactory.new(FakeCGSBinaryVoteContract.address);

    assert.equal(FakeCGSBinaryVoteContract.address, await CGSFactoryContract.cgsVoteAddress.call(), "incorrect value");
  });

  it("Create a new CGS", async function() {
    let icoInitialSupply = 1000;
    let numTokensToDeposit = 250;
    let weiPerSecond = 5;

    let CGSFactoryContract = await CGSFactory.new(FakeCGSBinaryVoteContract.address);

    let TestTokenContract = await TestToken.new(tokenHolder1, icoInitialSupply, "TEST", "TST", 2);

    // Check the event
    let event = (await CGSFactoryContract.create(weiPerSecond, claimPrice, isClaimPriceVariable, icoLauncher, TestTokenContract.address, NOW, {from: icoLauncher})).logs[0];
    assert.equal(event.event, 'ev_NewCGS', "incorrect event name");
    assert.equal(event.args.creator, icoLauncher, "incorrect creator");
    assert.equal(event.args.id.toNumber(), 0, "incorrect id");

    // To make sure that the balances are updated correctly
    assert.equal(1, (await CGSFactoryContract.numCGS.call()).toNumber(), "incorrect number of cgs contracts");
  });
});
