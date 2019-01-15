pragma solidity ^0.5.0;

contract Hash {
  function sha3Vote(bool a, bytes32 b) public pure returns (bytes32) {

    return keccak256(abi.encodePacked(a, b));
  }

  function sha3String(string memory a) public pure returns (bytes32) {

    return keccak256(abi.encodePacked(a));
  }
}
