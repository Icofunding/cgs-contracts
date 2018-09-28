pragma solidity ^0.4.24;

import "./CGS.sol";

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

/// @title CGS Factory contract
/// @author Icofunding
contract CGSFactory {
  address public cgsVoteAddress; // Address of the CGS Vote smart contract

  uint public numCGS; // Number of CGS created to date
  mapping (uint => address) public cgsList; // id => address

  event ev_NewCGS(address indexed creator, uint id, address cgs);

  constructor(address _cgsVoteAddress) public {
    cgsVoteAddress = _cgsVoteAddress;
  }

  /// @notice Creates a new CGS smart contract
  /// @dev Creates a new CGS smart contract
  /// @param _weiPerSecond Amount of wei available to withdraw by the ICO lacunher per second
  /// @param _claimPrice Number of ICO tokens (plus decimals) or a percent (0...100], depending on the value of isClaimPriceVariable.
  /// @param _isClaimPriceVariable If the claimPrice depends on the totalSupply or not (a fixed amount of tokens)
  /// @param _icoLauncher Token wallet of the ICO launcher
  /// @param _tokenAddress Address of the ICO token smart contract
  /// @param _startDate Date from when the ICO launcher can start withdrawing funds
  function create(
    uint _weiPerSecond,
    uint _claimPrice,
    bool _isClaimPriceVariable,
    address _icoLauncher,
    address _tokenAddress,
    uint _startDate
  )
    public
    returns (address cgs)
  {
    cgs = new CGS(_weiPerSecond, _claimPrice, _isClaimPriceVariable, _icoLauncher, _tokenAddress, _startDate);
    CGS(cgs).setCGSVoteAddress(cgsVoteAddress);
    register(cgs);
  }

  /// @notice Registers contract in factory registry.
  /// @dev Registers contract in factory registry.
  /// @param cgs CGS smart contract address
  function register(address cgs) internal {
    cgsList[numCGS] = cgs;

    emit ev_NewCGS(msg.sender, numCGS, cgs);

    numCGS++;
  }
}
