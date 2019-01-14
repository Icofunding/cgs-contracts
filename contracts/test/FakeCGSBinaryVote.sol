pragma solidity ^0.5.0;

import "../interfaces/BinaryVoteCallback.sol";

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

  function finalizeVote(uint voteId, bool result) public {
    assert(BinaryVoteCallback(callback).binaryVoteResult(voteId, result));
  }

  function wake(uint /* voteId */) public {
    isVoteOpen = false;
  }

  function getVotingProcessDuration()
    public
    pure
    returns(uint)
  {
    return 10 days;
  }
}
