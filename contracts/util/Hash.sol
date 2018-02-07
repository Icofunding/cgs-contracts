pragma solidity ^0.4.18;

contract Hash {
  function sha3Vote(bool a, bytes32 b) public pure returns (bytes32) {

    return keccak256(a, b);
  }

  function sha3String(string a) public pure returns (bytes32) {

    return keccak256(a);
  }
}
