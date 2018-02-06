pragma solidity ^0.4.18;

import '../interfaces/BinaryVoteCallback.sol';

/**
 * ONLY FOR TESTING
 */
contract FakeCGSBinaryVote {
  address public callback;
  bool public isVoteOpen;

  function startVote(address _callback) public returns (uint) {
    callback = _callback;
    isVoteOpen = true;

    return 1;
  }

  function finalizeVote(bool result) public {
    BinaryVoteCallback(callback).binaryVoteResult(1, result);
  }
}
