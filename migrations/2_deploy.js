var CGSTestToken = artifacts.require("./test/TestToken.sol");
var ICOTestToken = artifacts.require("./test/TestToken.sol");
var CGSBinaryVote = artifacts.require("./CGSBinaryVote.sol");
var CGSFactory = artifacts.require("./CGSFactory.sol");
var CGS = artifacts.require("./CGS.sol");

module.exports = async function(deployer, network, accounts) {
  const NOW = Math.floor(Date.now() / 1000);

  // Fake CGS Token
  let icoInitialSupply = 1000;
  let tokenHolder = accounts[0]; // Write your ethereum address here

  // Fake ICO Token
  let cgsInitialSupply = 1000;
  let cgsHolder = accounts[0]; // Write your ethereum address here

  // CGSFactory
  let weiPerSecond = 5;
  let claimPrice = 500;
  let icoLauncher = accounts[0]; // Write your ethereum address here

  await deployer.deploy(ICOTestToken, tokenHolder, icoInitialSupply);
  await deployer.deploy(CGSBinaryVote, CGSTestToken.address);
  await deployer.deploy(CGSFactory, CGSBinaryVote.address);

  await deployer.deploy(CGSTestToken, cgsHolder, cgsInitialSupply);

  let CGSFactoryContract = await CGSFactory.deployed();
  let event = (await CGSFactoryContract.create(weiPerSecond, claimPrice, icoLauncher, ICOTestToken.address, NOW, {from: icoLauncher})).logs[0];
  // Meter 10 ether en Vault
  // let VaultAddress = ;
  //await web3.eth.sendTransaction({from: accounts[0], to: VaultAddress, value: web3.toWei("10", "Ether")});

  console.log("==================================");
  console.log("Contracts deployed:");
  console.log("Test CGS token:" + CGSTestToken.address);
  console.log("CGSBinaryVote:" + CGSBinaryVote.address);
  console.log("CGSFactory:" + CGSFactory.address);
  console.log("Test ICO token:" + ICOTestToken.address);
  console.log("CGS:" + event.args.cgs);
  //console.log("Vault:" + );
};
