pragma solidity ^0.4.24;

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 *
 * This code has not been reviewed.
 * Do not use or deploy this code before reviewing it personally first.
 */
contract ERC820Registry {
  function setInterfaceImplementer(address _addr, bytes32 _interfaceHash, address _implementer) external;
  function getInterfaceImplementer(address _addr, bytes32 _interfaceHash) external view returns (address);
  function setManager(address _addr, address _newManager) external;
  function getManager(address _addr) public view returns(address);
}

/// Base client to interact with the registry.
contract ERC820Client {
  ERC820Registry erc820Registry = ERC820Registry(0x820c4597Fc3E4193282576750Ea4fcfe34DdF0a7);

  function setInterfaceImplementation(string _interfaceLabel, address _implementation) internal {
    bytes32 interfaceHash = keccak256(abi.encodePacked(_interfaceLabel));
    erc820Registry.setInterfaceImplementer(this, interfaceHash, _implementation);
  }

  function interfaceAddr(address addr, string _interfaceLabel) internal view returns(address) {
    bytes32 interfaceHash = keccak256(abi.encodePacked(_interfaceLabel));
    return erc820Registry.getInterfaceImplementer(addr, interfaceHash);
  }

  function delegateManagement(address _newManager) internal {
    erc820Registry.setManager(this, _newManager);
  }
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
    assert(c / a == b);
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
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

contract ERC777Token {
  function name() public view returns (string);
  function symbol() public view returns (string);
  function totalSupply() public view returns (uint256);
  function balanceOf(address owner) public view returns (uint256);
  function granularity() public view returns (uint256);

  function defaultOperators() public view returns (address[]);
  function isOperatorFor(address operator, address tokenHolder) public view returns (bool);
  function authorizeOperator(address operator) public;
  function revokeOperator(address operator) public;

  function send(address to, uint256 amount, bytes holderData) public;
  function operatorSend(address from, address to, uint256 amount, bytes holderData, bytes operatorData) public;
  
  function burn(uint256 amount, bytes holderData) public;
  function operatorBurn(address from, uint256 amount, bytes holderData, bytes operatorData) public;
  
  event Sent(
    address indexed operator,
    address indexed from,
    address indexed to,
    uint256 amount,
    bytes holderData,
    bytes operatorData
  ); // solhint-disable-next-line separate-by-one-line-in-contract
  event Minted(address indexed operator, address indexed to, uint256 amount, bytes operatorData);
  event Burned(address indexed operator, address indexed from, uint256 amount, bytes holderData, bytes operatorData);
  event AuthorizedOperator(address indexed operator, address indexed tokenHolder);
  event RevokedOperator(address indexed operator, address indexed tokenHolder);
}

contract ERC777TokensSender {
  function tokensToSend(
    address operator,
    address from,
    address to,
    uint amount,
    bytes userData,
    bytes operatorData
  ) public;
}

contract ERC777TokensRecipient {
  function tokensReceived(
    address operator,
    address from,
    address to,
    uint amount,
    bytes userData,
    bytes operatorData
  ) public;
}

contract ERC777BaseToken is ERC777Token, ERC820Client {
  using SafeMath for uint256;

  string internal mName;
  string internal mSymbol;
  uint256 internal mGranularity;
  uint256 internal mTotalSupply;

  mapping(address => uint) internal mBalances;
  mapping(address => mapping(address => bool)) internal mAuthorized;

  address[] internal mDefaultOperators;
  mapping(address => bool) internal mIsDefaultOperator;
  mapping(address => mapping(address => bool)) internal mRevokedDefaultOperator;

  /* -- Constructor -- */
  //
  /// @notice Constructor to create a ReferenceToken
  /// @param _name Name of the new token
  /// @param _symbol Symbol of the new token.
  /// @param _granularity Minimum transferable chunk.
  constructor(string _name, string _symbol, uint256 _granularity, address[] _defaultOperators) internal {
    mName = _name;
    mSymbol = _symbol;
    mTotalSupply = 0;
    require(_granularity >= 1);
    mGranularity = _granularity;

    mDefaultOperators = _defaultOperators;
    for (uint i = 0; i < mDefaultOperators.length; i++) { mIsDefaultOperator[mDefaultOperators[i]] = true; }

    setInterfaceImplementation("ERC777Token", this);
  }

  /* -- ERC777 Interface Implementation -- */
  //
  /// @return the name of the token
  function name() public constant returns (string) { return mName; }

  /// @return the symbol of the token
  function symbol() public constant returns (string) { return mSymbol; }

  /// @return the granularity of the token
  function granularity() public constant returns (uint256) { return mGranularity; }

  /// @return the total supply of the token
  function totalSupply() public constant returns (uint256) { return mTotalSupply; }

  /// @notice Return the account balance of some account
  /// @param _tokenHolder Address for which the balance is returned
  /// @return the balance of `_tokenAddress`.
  function balanceOf(address _tokenHolder) public constant returns (uint256) { return mBalances[_tokenHolder]; }

  /// @notice Return the list of default operators
  /// @return the list of all the default operators
  function defaultOperators() public view returns (address[]) { return mDefaultOperators; }

  /// @notice Send `_amount` of tokens to address `_to` passing `_userData` to the recipient
  /// @param _to The address of the recipient
  /// @param _amount The number of tokens to be sent
  function send(address _to, uint256 _amount, bytes _userData) public {
    doSend(msg.sender, msg.sender, _to, _amount, _userData, "", true);
  }

  /// @notice Authorize a third party `_operator` to manage (send) `msg.sender`'s tokens.
  /// @param _operator The operator that wants to be Authorized
  function authorizeOperator(address _operator) public {
    require(_operator != msg.sender);
    if (mIsDefaultOperator[_operator]) {
      mRevokedDefaultOperator[_operator][msg.sender] = false;
    } else {
      mAuthorized[_operator][msg.sender] = true;
    }
    emit AuthorizedOperator(_operator, msg.sender);
  }

  /// @notice Revoke a third party `_operator`'s rights to manage (send) `msg.sender`'s tokens.
  /// @param _operator The operator that wants to be Revoked
  function revokeOperator(address _operator) public {
    require(_operator != msg.sender);
    if (mIsDefaultOperator[_operator]) {
      mRevokedDefaultOperator[_operator][msg.sender] = true;
    } else {
      mAuthorized[_operator][msg.sender] = false;
    }
    emit RevokedOperator(_operator, msg.sender);
  }

  /// @notice Check whether the `_operator` address is allowed to manage the tokens held by `_tokenHolder` address.
  /// @param _operator address to check if it has the right to manage the tokens
  /// @param _tokenHolder address which holds the tokens to be managed
  /// @return `true` if `_operator` is authorized for `_tokenHolder`
  function isOperatorFor(address _operator, address _tokenHolder) public constant returns (bool) {
    return (_operator == _tokenHolder
      || mAuthorized[_operator][_tokenHolder]
      || (mIsDefaultOperator[_operator] && !mRevokedDefaultOperator[_operator][_tokenHolder]));
  }

  /// @notice Send `_amount` of tokens on behalf of the address `from` to the address `to`.
  /// @param _from The address holding the tokens being sent
  /// @param _to The address of the recipient
  /// @param _amount The number of tokens to be sent
  /// @param _userData Data generated by the user to be sent to the recipient
  /// @param _operatorData Data generated by the operator to be sent to the recipient
  function operatorSend(address _from, address _to, uint256 _amount, bytes _userData, bytes _operatorData) public {
    require(isOperatorFor(msg.sender, _from));
    doSend(msg.sender, _from, _to, _amount, _userData, _operatorData, true);
  }

  function burn(uint256 _amount, bytes _holderData) public {
    doBurn(msg.sender, msg.sender, _amount, _holderData, "");
  }

  function operatorBurn(address _tokenHolder, uint256 _amount, bytes _holderData, bytes _operatorData) public {
    require(isOperatorFor(msg.sender, _tokenHolder));
    doBurn(msg.sender, _tokenHolder, _amount, _holderData, _operatorData);
  }

  /* -- Helper Functions -- */
  //
  /// @notice Internal function that ensures `_amount` is multiple of the granularity
  /// @param _amount The quantity that want's to be checked
  function requireMultiple(uint256 _amount) internal view {
    require(_amount.div(mGranularity).mul(mGranularity) == _amount);
  }

  /// @notice Check whether an address is a regular address or not.
  /// @param _addr Address of the contract that has to be checked
  /// @return `true` if `_addr` is a regular address (not a contract)
  function isRegularAddress(address _addr) internal constant returns(bool) {
    if (_addr == 0) { return false; }
    uint size;
    assembly { size := extcodesize(_addr) } // solhint-disable-line no-inline-assembly
    return size == 0;
  }

  /// @notice Helper function actually performing the sending of tokens.
  /// @param _operator The address performing the send
  /// @param _from The address holding the tokens being sent
  /// @param _to The address of the recipient
  /// @param _amount The number of tokens to be sent
  /// @param _userData Data generated by the user to be passed to the recipient
  /// @param _operatorData Data generated by the operator to be passed to the recipient
  /// @param _preventLocking `true` if you want this function to throw when tokens are sent to a contract not
  ///  implementing `erc777_tokenHolder`.
  ///  ERC777 native Send functions MUST set this parameter to `true`, and backwards compatible ERC20 transfer
  ///  functions SHOULD set this parameter to `false`.
  function doSend(
    address _operator,
    address _from,
    address _to,
    uint256 _amount,
    bytes _userData,
    bytes _operatorData,
    bool _preventLocking
  )
    internal
  {
    requireMultiple(_amount);

    callSender(_operator, _from, _to, _amount, _userData, _operatorData);

    require(_to != address(0));          // forbid sending to 0x0 (=burning)
    require(mBalances[_from] >= _amount); // ensure enough funds

    mBalances[_from] = mBalances[_from].sub(_amount);
    mBalances[_to] = mBalances[_to].add(_amount);

    callRecipient(_operator, _from, _to, _amount, _userData, _operatorData, _preventLocking);

    emit Sent(_operator, _from, _to, _amount, _userData, _operatorData);
  }

  /// @notice Helper function actually performing the burning of tokens.
  /// @param _operator The address performing the burn
  /// @param _tokenHolder The address holding the tokens being burn
  /// @param _amount The number of tokens to be burnt
  /// @param _holderData Data generated by the token holder
  /// @param _operatorData Data generated by the operator
  function doBurn(address _operator, address _tokenHolder, uint256 _amount, bytes _holderData, bytes _operatorData)
    internal
  {
    requireMultiple(_amount);
    require(balanceOf(_tokenHolder) >= _amount);

    mBalances[_tokenHolder] = mBalances[_tokenHolder].sub(_amount);
    mTotalSupply = mTotalSupply.sub(_amount);

    callSender(_operator, _tokenHolder, 0x0, _amount, _holderData, _operatorData);
    emit Burned(_operator, _tokenHolder, _amount, _holderData, _operatorData);
  }

  /// @notice Helper function that checks for ERC777TokensRecipient on the recipient and calls it.
  ///  May throw according to `_preventLocking`
  /// @param _operator The address performing the send or mint
  /// @param _from The address holding the tokens being sent
  /// @param _to The address of the recipient
  /// @param _amount The number of tokens to be sent
  /// @param _userData Data generated by the user to be passed to the recipient
  /// @param _operatorData Data generated by the operator to be passed to the recipient
  /// @param _preventLocking `true` if you want this function to throw when tokens are sent to a contract not
  ///  implementing `ERC777TokensRecipient`.
  ///  ERC777 native Send functions MUST set this parameter to `true`, and backwards compatible ERC20 transfer
  ///  functions SHOULD set this parameter to `false`.
  function callRecipient(
    address _operator,
    address _from,
    address _to,
    uint256 _amount,
    bytes _userData,
    bytes _operatorData,
    bool _preventLocking
  )
    internal
  {
    address recipientImplementation = interfaceAddr(_to, "ERC777TokensRecipient");
    if (recipientImplementation != 0) {
      ERC777TokensRecipient(recipientImplementation).tokensReceived(
        _operator,
        _from,
        _to,
        _amount,
        _userData,
        _operatorData
      );
    } else if (_preventLocking) {
      require(isRegularAddress(_to));
    }
  }

  /// @notice Helper function that checks for ERC777TokensSender on the sender and calls it.
  ///  May throw according to `_preventLocking`
  /// @param _from The address holding the tokens being sent
  /// @param _to The address of the recipient
  /// @param _amount The amount of tokens to be sent
  /// @param _userData Data generated by the user to be passed to the recipient
  /// @param _operatorData Data generated by the operator to be passed to the recipient
  ///  implementing `ERC777TokensSender`.
  ///  ERC777 native Send functions MUST set this parameter to `true`, and backwards compatible ERC20 transfer
  ///  functions SHOULD set this parameter to `false`.
  function callSender(
    address _operator,
    address _from,
    address _to,
    uint256 _amount,
    bytes _userData,
    bytes _operatorData
  )
    internal
  {
    address senderImplementation = interfaceAddr(_from, "ERC777TokensSender");
    if (senderImplementation == 0) { return; }
    ERC777TokensSender(senderImplementation).tokensToSend(_operator, _from, _to, _amount, _userData, _operatorData);
  }
}

interface ERC20Token {
  function name() external constant returns (string);
  function symbol() external constant returns (string);
  function decimals() external constant returns (uint8); 

  function totalSupply() external constant returns (uint256);
  function balanceOf(address owner) external constant returns (uint256);

  function transfer(address to, uint256 amount) external returns (bool);
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
  function approve(address spender, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external constant returns (uint256);

  // solhint-disable-next-line no-simple-event-func-name
  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(address indexed owner, address indexed spender, uint256 amount);
}

contract ERC777ERC20BaseToken is ERC20Token, ERC777BaseToken {
  bool internal mErc20compatible;
  mapping(address => mapping(address => bool)) internal mAuthorized;
  mapping(address => mapping(address => uint256)) internal mAllowed;

  constructor(
    string _name,
    string _symbol,
    uint256 _granularity,
    address[] _defaultOperators
  )
    internal ERC777BaseToken(_name, _symbol, _granularity, _defaultOperators)
  {
    mErc20compatible = true;

    setInterfaceImplementation("ERC20Token", this);
  }

  /// @notice This modifier is applied to erc20 obsolete methods that are
  ///  implemented only to maintain backwards compatibility. When the erc20
  ///  compatibility is disabled, this methods will fail.
  modifier erc20 () {
    require(mErc20compatible);

    _;
  }

  /// @notice For Backwards compatibility
  /// @return The decimls of the token. Forced to 18 in ERC777.
  function decimals() public erc20 constant returns (uint8) {

    return uint8(18);
  }

  /// @notice ERC20 backwards compatible transfer.
  /// @param _to The address of the recipient
  /// @param _amount The number of tokens to be transferred
  /// @return `true`, if the transfer can't be done, it should fail.
  function transfer(address _to, uint256 _amount) public erc20 returns (bool success) {
    doSend(msg.sender, msg.sender, _to, _amount, "", "", false);

    return true;
  }

  /// @notice ERC20 backwards compatible transferFrom.
  /// @param _from The address holding the tokens being transferred
  /// @param _to The address of the recipient
  /// @param _amount The number of tokens to be transferred
  /// @return `true`, if the transfer can't be done, it should fail.
  function transferFrom(address _from, address _to, uint256 _amount) public erc20 returns (bool success) {
    require(_amount <= mAllowed[_from][msg.sender]);

    // Cannot be after doSend because of tokensReceived re-entry
    mAllowed[_from][msg.sender] = mAllowed[_from][msg.sender].sub(_amount);
    doSend(msg.sender, _from, _to, _amount, "", "", false);

    return true;
  }

  /// @notice ERC20 backwards compatible approve.
  ///  `msg.sender` approves `_spender` to spend `_amount` tokens on its behalf.
  /// @param _spender The address of the account able to transfer the tokens
  /// @param _amount The number of tokens to be approved for transfer
  /// @return `true`, if the approve can't be done, it should fail.
  function approve(address _spender, uint256 _amount) public erc20 returns (bool success) {
    mAllowed[msg.sender][_spender] = _amount;
    
    emit Approval(msg.sender, _spender, _amount);

    return true;
  }

  /// @notice ERC20 backwards compatible allowance.
  ///  This function makes it easy to read the `allowed[]` map
  /// @param _owner The address of the account that owns the token
  /// @param _spender The address of the account able to transfer the tokens
  /// @return Amount of remaining tokens of _owner that _spender is allowed
  ///  to spend
  function allowance(address _owner, address _spender) public erc20 view returns (uint256 remaining) {
    return mAllowed[_owner][_spender];
  }

  function doSend(
    address _operator,
    address _from,
    address _to,
    uint256 _amount,
    bytes _userData,
    bytes _operatorData,
    bool _preventLocking
  )
    internal
  {
    super.doSend(_operator, _from, _to, _amount, _userData, _operatorData, _preventLocking);
    if (mErc20compatible) {
      emit Transfer(_from, _to, _amount);
    }
  }

  function doBurn(address _operator, address _tokenHolder, uint256 _amount, bytes _holderData, bytes _operatorData)
    internal
  {
    super.doBurn(_operator, _tokenHolder, _amount, _holderData, _operatorData);

    if (mErc20compatible) {
      emit Transfer(_tokenHolder, 0x0, _amount);
    }
  }
}

contract Owned {
  address public owner;

  modifier onlyOwner() {
    require(msg.sender == owner);

    _;
  }

  constructor() public {
    owner = msg.sender;
  }

  function changeOwner(address newOwner) public onlyOwner {
    owner = newOwner;
  }
}

/// @title Manages the minters of a token
/// @author Icofunding
contract Minted is Owned {
  uint public numMinters; // Number of minters of the token.
  bool public open; // If is possible to add new minters or not. True by default.
  mapping (address => bool) public isMinter; // If an address is a minter of the token or not

  // Log of the minters added
  event NewMinter(address who);

  modifier onlyMinters() {
    require(isMinter[msg.sender]);

    _;
  }

  modifier onlyIfOpen() {
    require(open);

    _;
  }

  constructor() public {
    open = true;
  }

  /// @notice Adds a new minter to the token.
  /// It can only be executed by the Owner if the token is open to new minters.
  /// @dev Adds a new minter to the token.
  /// It can only be executed by the Owner if the token is open to new minters.
  /// @param _minter minter address
  function addMinter(address _minter) public onlyOwner onlyIfOpen {
    if(!isMinter[_minter]) {
      isMinter[_minter] = true;
      numMinters++;

      emit NewMinter(_minter);
    }
  }

  /// @notice Removes a minter of the token.
  /// It can only be executed by the Owner.
  /// @dev Removes a minter of the token.
  /// It can only be executed by the Owner.
  /// @param _minter minter address
  function removeMinter(address _minter) public onlyOwner {
    if(isMinter[_minter]) {
      isMinter[_minter] = false;
      numMinters--;
    }
  }

  /// @notice Blocks the possibility to add new minters.
  /// It can only be executed by the Owner.
  /// @dev Blocks the possibility to add new minters
  /// It can only be executed by the Owner.
  function endMinting() public onlyOwner {
    open = false;
  }
}


/// @title Pausable
/// @author Icofunding
contract Pausable is Owned {
  bool public isPaused;

  modifier whenNotPaused() {
    require(!isPaused);

    _;
  }

  /// @notice Makes the token non-transferable
  /// @dev Makes the token non-transferable
  function pause() public onlyOwner {
    isPaused = true;
  }

  /// @notice Makes the token transferable
  /// @dev Makes the token transferable
  function unPause() public onlyOwner {
    isPaused = false;
  }
}


contract ERC777ProjectToken is ERC777ERC20BaseToken, Minted, Pausable {
  uint public transferableDate; // timestamp

  modifier lockUpPeriod() {
    require(now >= transferableDate);

    _;
  }

  /// @notice Creates a token
  /// @dev Constructor
  /// @param _name Name of the token
  /// @param _symbol Acronim of the token
  /// @param _granularity Granularity of the token
  /// @param _defaultOperators Default operators
  /// @param _transferableDate Timestamp from when the token can de transfered
  constructor(
    string _name,
    string _symbol,
    uint _granularity,
    address[] _defaultOperators,
    uint _transferableDate
  ) 
    public
    ERC777ERC20BaseToken(_name, _symbol, _granularity, _defaultOperators)
  {    
    transferableDate = _transferableDate;
  }

  /// @notice Creates `amount` tokens and sends them to `recipient` address
  /// @dev Mints new tokens. This tokens are transfered from the address 0x0
  /// @param recipient Address that receives the tokens
  /// @param amount Number of tokens created (plus decimals)
  /// @param minterData metadata provided by the Minter
  /// @return true if success
  function mint(address recipient, uint amount, bytes minterData)
    public
    onlyMinters
    returns (bool success)
  {
    requireMultiple(amount);

    require(recipient != address(0));

    mBalances[recipient] = mBalances[recipient].add(amount);
    mTotalSupply = mTotalSupply.add(amount);

    callRecipient(msg.sender, address(0), recipient, amount, "", minterData, false); // May be true in the future

    emit Minted(msg.sender, recipient, amount, minterData);

    if(mErc20compatible)
      emit Transfer(address(0), recipient, amount);

    return true;
  }

  /// @notice Transfers `value` tokens to `to`
  /// @dev Transfers `value` tokens to `to`
  /// @param to The address that will receive the tokens.
  /// @param value The amount of tokens to transfer (plus decimals)
  /// @return true if success
  function transfer(address to, uint value)
    public
    lockUpPeriod
    whenNotPaused
    returns (bool success)
  {
    return super.transfer(to, value);
  }

  /// @notice Transfers `value` tokens to `to` from `from` account
  /// @dev Transfers `value` tokens to `to` from `from` account.
  /// @param from The address of the sender
  /// @param to The address that will receive the tokens
  /// @param value The amount of tokens to transfer (plus decimals)
  /// @return true if success
  function transferFrom(address from, address to, uint value)
    public
    lockUpPeriod
    whenNotPaused
    returns (bool success)
  {
    return super.transferFrom(from, to, value);
  }

  /// @notice Transfers `value` tokens to `to`
  /// @dev Transfers `value` tokens to `to`
  /// @param to The address that will receive the tokens.
  /// @param value The amount of tokens to transfer (plus decimals)
  /// @param holderData Holder Metadata
  function send(address to, uint value, bytes holderData)
    public
    lockUpPeriod
    whenNotPaused
  {
    super.send(to, value, holderData);
  }

  /// @notice Transfers `value` tokens to `to` from `from` account
  /// @dev Transfers `value` tokens to `to` from `from` account. Updates the voting rights
  /// @param from The address of the sender
  /// @param to The address that will receive the tokens
  /// @param value The amount of tokens to transfer (plus decimals)
  /// @param holderData Holder Metadata
  /// @param operatorData Operator Metadata
  function operatorSend(address from, address to, uint value, bytes holderData, bytes operatorData)
    public
    lockUpPeriod
    whenNotPaused
  {
    super.operatorSend(from, to, value, holderData, operatorData);
  }
}

contract TestToken is ERC777ProjectToken {

  /// @notice Creates a token
  /// @dev Constructor
  /// @param _name Name of the token
  /// @param _symbol Acronim of the token
  /// @param _granularity Granularity of the token
  /// @param _defaultOperators Default operators
  /// @param _transferableDate Timestamp from when the token can de transfered
  constructor(
    string _name,
    string _symbol,
    uint _granularity,
    address[] _defaultOperators,
    uint _transferableDate
  ) 
    public
    ERC777ProjectToken(_name, _symbol, _granularity, _defaultOperators, _transferableDate)
  {
    
  }

  function buy() public payable {
    uint amount = msg.value * 1000;
    address recipient = msg.sender;
    bytes memory minterData = "Buy";
    address minterOperator = this;

    requireMultiple(amount);

    require(recipient != address(0));

    mBalances[recipient] = mBalances[recipient].add(amount);
    mTotalSupply = mTotalSupply.add(amount);

    callRecipient(minterOperator, address(0), recipient, amount, "", minterData, false); // May be true in the future

    emit Minted(minterOperator, recipient, amount, minterData);

    if(mErc20compatible)
      emit Transfer(address(0), recipient, amount);
    
    owner.transfer(msg.value);
  }

  function () external payable {
    buy();
  }
}