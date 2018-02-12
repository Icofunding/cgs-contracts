var Wevern = artifacts.require("./Wevern.sol");
var CGSBinaryVote = artifacts.require("./CGSBinaryVote.sol");
var TestToken = artifacts.require("./test/TestToken.sol");

module.exports = async function(deployer) {
  const NOW = Math.floor(Date.now() / 1000);

  // Fake Token
  let icoInitialSupply = 1000;
  let tokenHolder = "0x627306090abaB3A6e1400e9345bC60c78a8BEf57"; // Write your ethereum address here

  // Wevern
  let weiPerSecond = 5;
  let claimPrice = 500;
  let icoLauncher = "0x627306090abaB3A6e1400e9345bC60c78a8BEf57"; // Write your ethereum address here

  await deployer.deploy(TestToken, tokenHolder, icoInitialSupply);
  await deployer.deploy(CGSBinaryVote, TestToken.address);
  await deployer.deploy(Wevern, weiPerSecond, claimPrice, icoLauncher, TestToken.address, CGSBinaryVote.address, NOW);

  console.log("==================================");
  console.log("Contracts deployed:");
  console.log("Test token:" + TestToken.address);
  console.log("CGSBinaryVote:" + CGSBinaryVote.address);
  console.log("Wevern:" + Wevern.address);
};
