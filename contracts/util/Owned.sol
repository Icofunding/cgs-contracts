pragma solidity ^0.4.24;

/**
 * Manages the ownership of a contract
 * Standard Owned contract.
 */
contract Owned {
  address public owner;

  modifier onlyOwner() {
    require(msg.sender == owner, "Only the owner can execute it");

    _;
  }

  constructor() public {
    owner = msg.sender;
  }

  function changeOwner(address newOwner) public onlyOwner {
    owner = newOwner;
  }
}
