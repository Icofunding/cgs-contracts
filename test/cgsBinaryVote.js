const sha3 = require("solidity-sha3");
const CGSBinaryVote = artifacts.require("./CGSBinaryVote.sol");
const TestToken = artifacts.require("./test/TestToken.sol");


contract('CGSBinaryVote', function(accounts) {
  const ONE_DAY = 24*3600;
  const NOW = Math.floor(Date.now() / 1000);
  const SECRET_VOTE_STAGE = 0;
  const REVEAL_VOTE_STAGE = 1;
  const SETTLEMENT_STAGE = 2;

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
    tokenHolder3 = accounts[3];
  });

  it("Deployment with initial values", async function() {
    let cgsInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    // Default value for all variables
    assert.equal(TestTokenContract.address, await CGSBinaryVoteContract.cgsToken.call(), "incorrect value");
    assert.equal(0, (await CGSBinaryVoteContract.numVotes.call()).toNumber(), "incorrect number of votes");
  });

  it("Start a vote", async function() {
    let cgsInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    // Execute and check the event
    let event = (await CGSBinaryVoteContract.startVote(owner)).logs[0];
    assert.equal(event.event, 'ev_NewVote', "incorrect event name");
    assert.equal(event.args.voteId.toNumber(), 0, "incorrect voteId");
    assert.equal(event.args.callback, owner, "incorrect callback");

    assert.equal(1, (await CGSBinaryVoteContract.numVotes.call()).toNumber(), "incorrect numVotes");
  });

  it("Vote", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let salt = "The most secure password ever";

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await CGSBinaryVoteContract.startVote(owner);

    let hash = sha3.default(true, salt);

    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder1});
    // Execute and check the event
    let event = (await CGSBinaryVoteContract.vote(0, numTokensToVote, hash, {from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_Vote', "incorrect event name");
    assert.equal(event.args.voteId.toNumber(), 0, "incorrect voteId");
    assert.equal(event.args.who, tokenHolder1, "incorrect who");
    assert.equal(event.args.amount.toNumber(), numTokensToVote, "incorrect amount");

    let vote = await CGSBinaryVoteContract.votes.call(0);
    assert.equal(SECRET_VOTE_STAGE, vote[1].toNumber(), "incorrect stage");
    assert.equal(numTokensToVote, vote[2].toNumber(), "incorrect numVotes");
    assert.equal(0, vote[3].toNumber(), "incorrect numVotes");
    assert.equal(owner, vote[4], "incorrect callback");

    // TODO: Getters and tests for mappings inside struct
  });

});
