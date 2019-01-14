pragma solidity ^0.5.0;

import "../interfaces/BinaryVoteCallback.sol";

/**
 * ONLY FOR TESTING
 */
contract VoteReceiver is BinaryVoteCallback {

  function binaryVoteResult(uint /* voteId */, bool /* result */) public returns (bool) {

    return true;
  }
}
