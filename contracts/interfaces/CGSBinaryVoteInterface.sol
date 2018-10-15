pragma solidity ^0.4.24;

/*
  Copyright (C) 2018 Icofunding S.L.

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/

/// @title CGSBinaryVote interface
/// @author Icofunding
contract CGSBinaryVoteInterface {

  enum Stages {
    SecretVote,
    RevealVote,
    Settlement
  }

  struct Vote {
    uint date; // Timestamp when the claim is open
    Stages stage; // Current state of the vote
    uint votesYes; // Votes that the project is doing a proper use of the funds. Updated during Reveal stage
    uint votesNo; // Votes that the project is not doing a proper use of the funds. Updated during Reveal stage
    address callback; // The address to call when the vote ends
    bool finalized; // If the result of the project has already been informed to the callback
    uint totalVotes; // Total number of votes (at the moment of voting, no matter if revealed or not)
    mapping (address => bytes32) secretVotes; // Hashes of votes
    mapping (address => bool) revealedVotes; // Votes in plain text
    mapping (address => bool) hasRevealed; // True if the user has revealed his vote
    mapping (address => uint) userDeposits; // Amount of CGS tokens deposited for this vote.
  }

  Vote[] public votes; // Log of votes
  uint public numVotes; // Number of elements in the array votes

  address public cgsToken; // Address of the CGS token smart contract

  function startVote(address _callback) public returns(uint);

  function vote(uint voteId, uint numTokens, bytes32 secretVote) public returns(bool);
  function reveal(uint voteId, bytes32 salt) public returns(bool);
  function withdrawTokens(uint voteId) public returns(bool);

  function getStage(uint voteId) public view returns(Stages);

  function tokensToWithdraw(uint voteId, address who) public view returns(uint);

  function wake(uint voteId) public;

  function hasUserRevealed(uint voteId, address who) public view returns(bool);
  function getRevealedVote(uint voteId, address who) public view returns(bool);
  function getUserDeposit(uint voteId, address who) public view returns(uint);

  function canRevealVote(uint voteId, address user, bytes32 salt) public view returns(bool);
  function calculateRevealedVote(uint voteId, address user, bytes32 salt) public view returns(bool);
  function getVoteResult(uint voteId) public view returns(bool);

  function getVotingProcessDuration() public pure returns(uint);
  function getVotePhaseDuration() public pure returns(uint);
  function getRevealPhaseDuration() public pure returns(uint);
}
