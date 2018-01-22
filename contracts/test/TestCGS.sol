pragma solidity ^0.4.18;

/**
 * ONLY FOR TESTING
 */
contract TestCGS {
  bool public isClaimOpen;

  function openClaim() public returns (bool) {
    isClaimOpen = true;

    return true;
  }
}
