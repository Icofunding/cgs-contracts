pragma solidity ^0.4.18;

import '../interfaces/ERC20.sol';
import '../util/SafeMath.sol';

/**
 * Standard ERC20 token with fake data. ONLY FOR TESTING
 */
contract TestToken is ERC20, SafeMath {
  string public name;
  string public symbol;
  uint public decimals;

  mapping(address => uint) balances;
  mapping (address => mapping (address => uint)) allowed;

  function TestToken(address recipient, uint amount, string _name, string _symbol, uint _decimals) public {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
    mint(recipient, amount);
  }

  function mint(address recipient, uint amount) public {
    balances[recipient] = amount;
    totalSupply = amount;
  }

  function transfer(address _to, uint _value) public returns (bool success) {

    return doTransfer(msg.sender, _to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) public returns (bool success) {
    var _allowance = allowed[_from][msg.sender];

    allowed[_from][msg.sender] = safeSub(_allowance, _value);

    return doTransfer(_from, _to, _value);
  }

  /// @notice Allows `_spender` to withdraw from your account multiple times up to `_value`.
  /// If this function is called again it overwrites the current allowance with `_value`.
  /// @dev Allows `_spender` to withdraw from your account multiple times up to `_value`.
  /// If this function is called again it overwrites the current allowance with `_value`.
  /// NOTE: To prevent attack vectors, clients SHOULD make sure to create user interfaces
  /// in such a way that they set the allowance first to 0 before setting it
  /// to another value for the same spender
  /// @param _spender Address that is going to be approved
  /// @param _value Number of tokens that spender is going to be able to transfer
  /// @return true if success
  function approve(address _spender, uint _value) public returns (bool success) {
    allowed[msg.sender][_spender] = _value;

    Approval(msg.sender, _spender, _value);

    return true;
  }

  function doTransfer(address _from, address _to, uint _value) private returns (bool success) {
    balances[_from] = safeSub(balances[_from], _value);
    balances[_to] = safeAdd(balances[_to], _value);

    Transfer(_from, _to, _value);

    return true;
  }

  function balanceOf(address _owner) public constant returns (uint balance) {
    return balances[_owner];
  }

  function allowance(address _owner, address _spender) public constant returns (uint remaining) {
    return allowed[_owner][_spender];
  }
}
