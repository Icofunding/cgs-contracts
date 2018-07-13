var CGSTestToken = artifacts.require("./test/CGSTestToken.sol");
var ICOTestToken = artifacts.require("./test/ICOTestToken.sol");
var CGSBinaryVote = artifacts.require("./CGSBinaryVote.sol");
var CGSFactory = artifacts.require("./CGSFactory.sol");
var CGS = artifacts.require("./CGS.sol");
var Vault = artifacts.require("./Vault.sol");

module.exports = async function(deployer, network, accounts) {
  const NOW = Math.floor(Date.now() / 1000);

  // Fake CGS Token
  let icoInitialSupply = "10000000000000000000000";
  let tokenHolder = accounts[0]; // Write your ethereum address here
  let cgsTokenName = "Coin Governance System";
  let cgsTokenSymbol = "CGS";
  let cgsTokenDecimals = 18;

  // Fake ICO Token
  let cgsInitialSupply = "10000000000000000000000";
  let cgsHolder = accounts[0]; // Write your ethereum address here
  let icoTokenName = "ICO Token";
  let icoTokenSymbol = "ICOT";
  let icoTokenDecimals = 18;

  // CGSFactory
  let weiPerSecond = 5000000;
  let claimPrice = "500000000000000000000";
  let icoLauncher = accounts[0]; // Write your ethereum address here

  await deployer.deploy(CGSTestToken, cgsHolder, cgsInitialSupply, cgsTokenName, cgsTokenSymbol, cgsTokenDecimals);
  await deployer.deploy(CGSBinaryVote, CGSTestToken.address);
  //await deployer.deploy(CGSFactory, CGSBinaryVote.address);

  await deployer.deploy(ICOTestToken, tokenHolder, icoInitialSupply, icoTokenName, icoTokenSymbol, icoTokenDecimals);

  //let CGSFactoryContract = await CGSFactory.deployed();
  //let event = (await CGSFactoryContract.create(weiPerSecond, claimPrice, icoLauncher, ICOTestToken.address, NOW, {from: icoLauncher})).logs[0];

  // Sends 10 Ether to Vault
  await deployer.deploy(CGS, weiPerSecond, claimPrice, icoLauncher, ICOTestToken.address, NOW, {from: icoLauncher});
  let CGSContract = CGS.at(CGS.address);
  await CGSContract.setCGSVoteAddress(CGSBinaryVote.address, {from: icoLauncher});
  //let CGSContract = CGS.at(event.args.cgs);
  let vaultAddress = await CGSContract.vaultAddress.call();
  await web3.eth.sendTransaction({from: accounts[0], to: vaultAddress, value: web3.toWei("10", "Ether")});

  console.log("==================================");
  console.log("Contracts deployed:");
  console.log("Test CGS token:" + CGSTestToken.address);
  console.log("CGSBinaryVote:" + CGSBinaryVote.address);
  //console.log("CGSFactory:" + CGSFactory.address);
  console.log("Test ICO token:" + ICOTestToken.address);
  console.log("CGS:" + CGSContract.address);
  console.log("Vault:" + vaultAddress);
};
