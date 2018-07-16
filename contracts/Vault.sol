pragma solidity ^0.4.18;

import './util/SafeMath.sol';

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

/// @title Vault contract
/// @author Icofunding
contract Vault {
  uint public totalCollected; // Wei
  uint public etherBalance; // Wei

  address public cgsAddress;

  using SafeMath for uint;

  event ev_Deposit(address indexed sender, uint amount);
  event ev_Withdraw(address indexed to, uint amount);

  modifier onlyCGS() {
    require(msg.sender == cgsAddress);

      _;
  }

  constructor(address _cgsAddress) public {
    cgsAddress = _cgsAddress;
  }

  /// @notice Deposits ether
  /// @dev Deposits ether
  function deposit() public payable returns(bool) {
    totalCollected = totalCollected.add(msg.value);
    etherBalance = etherBalance.add(msg.value);

    emit ev_Deposit(msg.sender, msg.value);

    return true;
  }

  /// @notice Sends ether to the ICO launcher/token holders
  /// @dev Sends ether to the ICO launcher/token holders
  /// @param to Account where the funds are going to be sent
  /// @param amount Amount of Wei to withdraw
  function withdraw(address to, uint amount) public onlyCGS returns(bool) {
    etherBalance = etherBalance.sub(amount);
    to.transfer(amount);

    emit ev_Withdraw(to, amount);

    return true;
  }

  /// @notice Forwards to deposit()
  /// @dev Forwards to deposit(). Consumes more than the standard gas.
  function () public payable {
    assert(deposit());
  }
}
