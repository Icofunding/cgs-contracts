const increaseTime = require("./helpers/increaseTime.js");
const mineBlock = require("./helpers/mineBlock.js");
const { assertRevert } = require('./helpers/assertThrow')
const CGSBinaryVote = artifacts.require("./CGSBinaryVote.sol");
const TestToken = artifacts.require("./test/TestToken.sol");
const VoteReceiver = artifacts.require("./test/VoteReceiver.sol");
const Hash = artifacts.require("./util/Hash.sol");


contract('CGSBinaryVote', function(accounts) {
  const ONE_DAY = 24*60*60;
  // const NOW = Math.floor(Date.now() / 1000);
  const NOW = web3.eth.getBlock("latest").timestamp;
  const SECRET_VOTE_STAGE = 0;
  const REVEAL_VOTE_STAGE = 1;
  const SETTLEMENT_STAGE = 2;

  const TIME_TO_VOTE = 7*ONE_DAY;
  const TIME_TO_REVEAL = 3*ONE_DAY;

  let owner;
  let tokenHolder1;
  let tokenHolder2;

  let fakeCGS;
  let HashContract;
  let VoteReceiverContract;

  let tokenName;
  let tokenSymbol;
  let tokenDecimals;

  before(async () => {
    owner = accounts[0];
    tokenHolder1 = accounts[1];
    tokenHolder2 = accounts[2];
    tokenHolder3 = accounts[3];
    tokenHolder4 = accounts[4];

    tokenName = "Coin Governance System";
    tokenSymbol = "CGS";
    tokenDecimals = 18;

    HashContract = await Hash.new();
    VoteReceiverContract = await VoteReceiver.new();
  });

  it("Deployment with initial values", async function() {
    let cgsInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    // Default value for all variables
    assert.equal(TestTokenContract.address, await CGSBinaryVoteContract.cgsToken.call(), "incorrect value");
    assert.equal(0, (await CGSBinaryVoteContract.numVotes.call()).toNumber(), "incorrect number of votes");

    // Constants
    assert.equal(TIME_TO_VOTE, (await CGSBinaryVoteContract.getVotePhaseDuration.call()).toNumber(), "incorrect time");
    assert.equal(TIME_TO_REVEAL, (await CGSBinaryVoteContract.getRevealPhaseDuration.call()).toNumber(), "incorrect time");
    assert.equal(TIME_TO_VOTE + TIME_TO_REVEAL, (await CGSBinaryVoteContract.getVotingProcessDuration.call()).toNumber(), "incorrect time");
  });

  it("Start a vote", async function() {
    let cgsInitialSupply = 1000;

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    // Execute and check the event
    let event = (await CGSBinaryVoteContract.startVote(owner)).logs[0];
    assert.equal(event.event, 'ev_NewVote', "incorrect event name");
    assert.equal(event.args.voteId.toNumber(), 0, "incorrect voteId");
    assert.equal(event.args.callback, owner, "incorrect callback");

    assert.equal(1, (await CGSBinaryVoteContract.numVotes.call()).toNumber(), "incorrect numVotes");
  });

  // TODO: Use web3 v1 to hash like Solidity
  it("Hash", async function() {
    let voteValue = true;
    let salt = await HashContract.sha3String("The most secure password ever");

    let hashS = await HashContract.sha3Vote(voteValue, salt);
    // web3 v1 ...

    assert.equal(hashS, hashS, "incorrect hash");
  });

  it("Stage", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let voteId = 0;
    let voteValue = true;
    let salt = await HashContract.sha3String("The most secure password ever");

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await CGSBinaryVoteContract.startVote(owner);

    assert.equal(SECRET_VOTE_STAGE, (await CGSBinaryVoteContract.getStage.call(voteId)).toNumber(), "incorrect stage");;

    increaseTime(TIME_TO_VOTE);
    mineBlock();
    assert.equal(REVEAL_VOTE_STAGE, (await CGSBinaryVoteContract.getStage.call(voteId)).toNumber(), "incorrect stage");;

    increaseTime(TIME_TO_REVEAL);
    mineBlock();
    assert.equal(SETTLEMENT_STAGE, (await CGSBinaryVoteContract.getStage.call(voteId)).toNumber(), "incorrect stage");;
  });


  it("Vote", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let voteId = 0;
    let voteValue = true;
    let salt = await HashContract.sha3String("The most secure password ever");
    let hash = await HashContract.sha3Vote(voteValue, salt);

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await CGSBinaryVoteContract.startVote(owner);

    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder1});
    // Execute and check the event
    let event = (await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash, {from: tokenHolder1})).logs[0];
    assert.equal(event.event, 'ev_Vote', "incorrect event name");
    assert.equal(event.args.voteId.toNumber(), voteId, "incorrect voteId");
    assert.equal(event.args.who, tokenHolder1, "incorrect who");
    assert.equal(event.args.amount.toNumber(), numTokensToVote, "incorrect amount");

    let voteData = await CGSBinaryVoteContract.votes.call(0);
    assert.isAtMost(NOW, voteData[0].toNumber(), "incorrect date");
    assert.equal(SECRET_VOTE_STAGE, voteData[1].toNumber(), "incorrect stage");
    assert.equal(0, voteData[2].toNumber(), "incorrect true numVotes");
    assert.equal(0, voteData[3].toNumber(), "incorrect false numVotes");
    assert.equal(owner, voteData[4], "incorrect callback");
    assert.equal(numTokensToVote, voteData[5].toNumber(), "incorrect number of total votes");

    assert.equal(numTokensToVote, (await CGSBinaryVoteContract.getUserDeposit.call(voteId, tokenHolder1)).toNumber(), "incorrect amount");
    assert.isFalse(await CGSBinaryVoteContract.hasUserRevealed.call(voteId, tokenHolder1), "incorrect value");
  });

  it("Check if a vote can be revealed", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let voteId = 0;
    let salt = await HashContract.sha3String("The most secure password ever");
    let hash = await HashContract.sha3Vote(true, salt);
    let hash2 = await HashContract.sha3Vote(false, salt);

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await TestTokenContract.mint(tokenHolder2, numTokensToVote);

    await CGSBinaryVoteContract.startVote(owner);

    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder1});
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder2});

    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash, {from: tokenHolder1}) // True
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash2, {from: tokenHolder2}) // False

    assert.isTrue(await CGSBinaryVoteContract.canRevealVote.call(voteId, tokenHolder1, salt), "incorrect vote revelation"); // True, voted true
    assert.isTrue(await CGSBinaryVoteContract.canRevealVote.call(voteId, tokenHolder2, salt), "incorrect vote revelation"); // True, voted false
    assert.isFalse(await CGSBinaryVoteContract.canRevealVote.call(voteId, tokenHolder3, salt), "incorrect vote revelation"); // False, didn't vote
  });

  it("Check revelation of votes", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let voteId = 0;
    let salt = await HashContract.sha3String("The most secure password ever");
    let hash = await HashContract.sha3Vote(true, salt);
    let hash2 = await HashContract.sha3Vote(false, salt);
    let hash3 = await HashContract.sha3Vote(true, salt);

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await TestTokenContract.mint(tokenHolder2, numTokensToVote);
    await TestTokenContract.mint(tokenHolder3, numTokensToVote);

    await CGSBinaryVoteContract.startVote(owner);

    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder1});
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder2});
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder3});

    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash, {from: tokenHolder1}) // True
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash2, {from: tokenHolder2}) // False
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash3, {from: tokenHolder3}) // True

    assert.isTrue(await CGSBinaryVoteContract.calculateRevealedVote.call(voteId, tokenHolder1, salt), "incorrect vote revelation"); // True
    assert.isFalse(await CGSBinaryVoteContract.calculateRevealedVote.call(voteId, tokenHolder2, salt), "incorrect vote revelation"); // False

    await assertRevert(async () => {
      await CGSBinaryVoteContract.calculateRevealedVote.call(voteId, tokenHolder3, "Potato")
    })
    // await expectThrow(await CGSBinaryVoteContract.calculateRevealedVote.call(voteId, tokenHolder3, "Potato")); // Fail
  });

  it("Reveal", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let voteId = 0;
    let voteValue = true;
    let salt = await HashContract.sha3String("The most secure password ever");
    let hash = await HashContract.sha3Vote(voteValue, salt);

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await CGSBinaryVoteContract.startVote(owner);

    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder1});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash, {from: tokenHolder1});

    increaseTime(TIME_TO_VOTE);
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder1});

    let voteData = await CGSBinaryVoteContract.votes.call(0);
    assert.equal(REVEAL_VOTE_STAGE, voteData[1].toNumber(), "incorrect stage");
    assert.equal(numTokensToVote, voteData[2].toNumber(), "incorrect true numVotes");
    assert.equal(0, voteData[3].toNumber(), "incorrect false numVotes");

    assert.isTrue(await CGSBinaryVoteContract.hasUserRevealed.call(voteId, tokenHolder1), "incorrect value");
    assert.equal(voteValue, await CGSBinaryVoteContract.getRevealedVote.call(voteId, tokenHolder1), "incorrect value");
  });

  it("Withdraw", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let numTokensToVote2 = 100;
    let voteId = 0;
    let voteValue = true;
    let voteValue2 = false;
    let salt = await HashContract.sha3String("The most secure password ever");
    let hash = await HashContract.sha3Vote(voteValue, salt);
    let hash2 = await HashContract.sha3Vote(voteValue2, salt);

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await TestTokenContract.mint(tokenHolder2, numTokensToVote2);

    await CGSBinaryVoteContract.startVote(VoteReceiverContract.address);

    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder1});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash, {from: tokenHolder1});

    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote2, {from: tokenHolder2});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote2, hash2, {from: tokenHolder2});

    increaseTime(TIME_TO_VOTE);
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder1});
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder2});

    increaseTime(TIME_TO_REVEAL);

    await CGSBinaryVoteContract.withdrawTokens(voteId, {from: tokenHolder1});
    await CGSBinaryVoteContract.withdrawTokens(voteId, {from: tokenHolder2});

    assert.equal(cgsInitialSupply + numTokensToVote2*0.2, await TestTokenContract.balanceOf.call(tokenHolder1), "incorrect value");
    assert.equal(numTokensToVote2 - numTokensToVote2*0.2, await TestTokenContract.balanceOf.call(tokenHolder2), "incorrect value");
  });

  it("Check tokens to withdraw with 4 voters and positive outcome", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let numTokensToVote2 = 100;
    let numTokensToVote3 = 150;
    let numTokensToVote4 = 250;
    let voteId = 0;
    let voteValue = true;
    let voteValue2 = false;
    let salt = await HashContract.sha3String("The most secure password ever");
    let hash = await HashContract.sha3Vote(voteValue, salt);
    let hash2 = await HashContract.sha3Vote(voteValue2, salt);

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await TestTokenContract.mint(tokenHolder2, numTokensToVote2);
    await TestTokenContract.mint(tokenHolder3, numTokensToVote3);
    await TestTokenContract.mint(tokenHolder4, numTokensToVote4);

    await CGSBinaryVoteContract.startVote(VoteReceiverContract.address);

    // Vote yes
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder1});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash, {from: tokenHolder1});

    // Vote no
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote2, {from: tokenHolder2});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote2, hash2, {from: tokenHolder2});

    // Vote yes but will not reveal
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote3, {from: tokenHolder3});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote3, hash, {from: tokenHolder3});

    // Vote yes
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote4, {from: tokenHolder4});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote4, hash, {from: tokenHolder4});

    increaseTime(TIME_TO_VOTE);
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder1});
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder2});
    // token holder 3 does not reveal
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder4});

    increaseTime(TIME_TO_REVEAL);

    let voteData = await CGSBinaryVoteContract.votes.call(0);
    assert.equal(numTokensToVote + numTokensToVote4, voteData[2].toNumber(), "incorrect true numVotes");
    assert.equal(numTokensToVote2, voteData[3].toNumber(), "incorrect false numVotes");
    assert.equal(numTokensToVote + numTokensToVote2 + numTokensToVote3 + numTokensToVote4, voteData[5].toNumber(), "incorrect number of total votes");

    // Apply penalizations (2 & 3) and bonuses (1 & 4)
    let tokensToVoter1 = numTokensToVote + parseInt(   parseInt(  ( (voteData[5].toNumber() - voteData[2].toNumber()) * 0.2 ) * numTokensToVote  ) / voteData[2].toNumber()   );
    let tokensToVoter2 = numTokensToVote2 - numTokensToVote2*0.2;
    let tokensToVoter3 = numTokensToVote3 - numTokensToVote3*0.2;
    let tokensToVoter4 = numTokensToVote4 + parseInt(   parseInt(  ( (voteData[5].toNumber() - voteData[2].toNumber()) * 0.2 ) * numTokensToVote4  ) / voteData[2].toNumber()   );

    assert.equal(tokensToVoter1, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, tokenHolder1)).toNumber(), "incorrect number of tokens to withdraw");
    assert.equal(tokensToVoter2, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, tokenHolder2)).toNumber(), "incorrect number of tokens to withdraw");
    assert.equal(tokensToVoter3, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, tokenHolder3)).toNumber(), "incorrect number of tokens to withdraw");
    assert.equal(tokensToVoter4, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, tokenHolder4)).toNumber(), "incorrect number of tokens to withdraw");

    // No tokens
    assert.equal(0, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, owner)).toNumber(), "incorrect number of tokens to withdraw");

    // The number of tokens remains the same
    assert.approximately(tokensToVoter1 + tokensToVoter2 + tokensToVoter3 + tokensToVoter4, voteData[5].toNumber(), 2, "incorrect value");
  });

  it("Check tokens to withdraw with 4 voters and negative outcome", async function() {
    let cgsInitialSupply = 1000;
    let numTokensToVote = 200;
    let numTokensToVote2 = 100;
    let numTokensToVote3 = 150;
    let numTokensToVote4 = 250;
    let voteId = 0;
    let voteValue = false;
    let voteValue2 = true;
    let salt = await HashContract.sha3String("The most secure password ever");
    let hash = await HashContract.sha3Vote(voteValue, salt);
    let hash2 = await HashContract.sha3Vote(voteValue2, salt);

    let TestTokenContract = await TestToken.new(tokenHolder1, cgsInitialSupply, tokenName, tokenSymbol, tokenDecimals);
    let CGSBinaryVoteContract = await CGSBinaryVote.new(TestTokenContract.address);

    await TestTokenContract.mint(tokenHolder2, numTokensToVote2);
    await TestTokenContract.mint(tokenHolder3, numTokensToVote3);
    await TestTokenContract.mint(tokenHolder4, numTokensToVote4);

    await CGSBinaryVoteContract.startVote(VoteReceiverContract.address);

    // Vote no
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote, {from: tokenHolder1});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote, hash, {from: tokenHolder1});

    // Vote yes
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote2, {from: tokenHolder2});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote2, hash2, {from: tokenHolder2});

    // Vote no but will not reveal
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote3, {from: tokenHolder3});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote3, hash, {from: tokenHolder3});

    // Vote no
    await TestTokenContract.approve(CGSBinaryVoteContract.address, numTokensToVote4, {from: tokenHolder4});
    await CGSBinaryVoteContract.vote(voteId, numTokensToVote4, hash, {from: tokenHolder4});

    increaseTime(TIME_TO_VOTE);
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder1});
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder2});
    // token holder 3 does not reveal
    await CGSBinaryVoteContract.reveal(voteId, salt, {from: tokenHolder4});

    increaseTime(TIME_TO_REVEAL);

    let voteData = await CGSBinaryVoteContract.votes.call(0);
    assert.equal(numTokensToVote2, voteData[2].toNumber(), "incorrect true numVotes");
    assert.equal(numTokensToVote + numTokensToVote4, voteData[3].toNumber(), "incorrect false numVotes");
    assert.equal(numTokensToVote + numTokensToVote2 + numTokensToVote3 + numTokensToVote4, voteData[5].toNumber(), "incorrect number of total votes");

    // Apply penalizations (2 & 3) and bonuses (1 & 4)
    let tokensToVoter1 = numTokensToVote + parseInt(   parseInt(  ( (voteData[5].toNumber() - voteData[3].toNumber()) * 0.2 ) * numTokensToVote  ) / voteData[3].toNumber()   );
    let tokensToVoter2 = numTokensToVote2 - numTokensToVote2*0.2;
    let tokensToVoter3 = numTokensToVote3 - numTokensToVote3*0.2;
    let tokensToVoter4 = numTokensToVote4 + parseInt(   parseInt(  ( (voteData[5].toNumber() - voteData[3].toNumber()) * 0.2 ) * numTokensToVote4  ) / voteData[3].toNumber()   );

    assert.equal(tokensToVoter1, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, tokenHolder1)).toNumber(), "incorrect number of tokens to withdraw");
    assert.equal(tokensToVoter2, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, tokenHolder2)).toNumber(), "incorrect number of tokens to withdraw");
    assert.equal(tokensToVoter3, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, tokenHolder3)).toNumber(), "incorrect number of tokens to withdraw");
    assert.equal(tokensToVoter4, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, tokenHolder4)).toNumber(), "incorrect number of tokens to withdraw");

    // No tokens
    assert.equal(0, (await CGSBinaryVoteContract.tokensToWithdraw.call(voteId, owner)).toNumber(), "incorrect number of tokens to withdraw");

    // The number of tokens remains the same
    assert.approximately(tokensToVoter1 + tokensToVoter2 + tokensToVoter3 + tokensToVoter4, voteData[5].toNumber(), 2, "incorrect value");
  });

});
