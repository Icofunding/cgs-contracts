pragma solidity ^0.4.18;

contract ERC20 {
  uint public totalSupply;
  function balanceOf(address who) public view returns (uint);
  function allowance(address owner, address spender) public view returns (uint);

  function transfer(address to, uint value) public returns (bool ok);
  function transferFrom(address from, address to, uint value) public returns (bool ok);
  function approve(address spender, uint value) public returns (bool ok);

  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);
}


library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    require(c / a == b, "Multiplication overflow");
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return a / b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    require(b <= a, "Substraction overflow");
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    require(c >= a, "Addition overflow");
    return c;
  }
}

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

contract TestToken is ERC20, Owned {
  string public name;
  string public symbol;
  uint public decimals;

  using SafeMath for uint;

  mapping(address => uint) balances;
  mapping (address => mapping (address => uint)) allowed;

  constructor(string _name, string _symbol, uint _decimals) public {
    name = _name;
    symbol = _symbol;
    decimals = _decimals;
  }

  function mint(address recipient, uint amount) public onlyOwner {
    balances[recipient] += amount;
    totalSupply += amount;
  }

  function buy() public payable {
    balances[msg.sender] += msg.value * 1000;
    totalSupply += msg.value * 1000;
  }

  function () external payable {
    buy();
  }

  function transfer(address _to, uint _value) public returns (bool success) {

    return doTransfer(msg.sender, _to, _value);
  }

  function transferFrom(address _from, address _to, uint _value) public returns (bool success) {
    uint _allowance = allowed[_from][msg.sender];

    allowed[_from][msg.sender] = _allowance.sub(_value);

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

    emit Approval(msg.sender, _spender, _value);

    return true;
  }

  function doTransfer(address _from, address _to, uint _value) private returns (bool success) {
    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);

    emit Transfer(_from, _to, _value);

    return true;
  }

  function balanceOf(address _owner) public constant returns (uint balance) {
    return balances[_owner];
  }

  function allowance(address _owner, address _spender) public constant returns (uint remaining) {
    return allowed[_owner][_spender];
  }
}