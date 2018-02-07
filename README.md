# Wevern Smart Contracts

Smart contracts for the CGS platform.

For the first version, there will be three smart contracts for each ICO:
- **CGS**: Manages the vote among CGS holders.
- **Claim**: Collects ICO tokens to create claims.
- **Vault**: Stores the Ether collected.

## Requirements

* Parity or Test RPC running in the same host
* Node installed
* Truffle installed

## Testing

```
Truffle test
```

## Deployment
```
Truffle migrate
```

## Integration
To obtain the ABI, you will need to compile the smart contract:

```
Truffle compile
```
A new folder called "build" will be created with multiple json files. One json per smart contract. Each file has a abi attribute inside with the ABI of the smart contract.


To obtain the address, you first have to deploy the CGS. Its address is going to be written in the console.
```
Truffle migrade
```

The Vault and Claim are created from CGS. Their addresses can be accessed using its public methods.

## Interface

### CGS methods

#### vote

Deposits CGS tokens and vote. Should be executed after Token.Approve(...)

**Params:**
* secretVote (bytes32): sha3(vote + sha3(salt))

```javascript
TODO
```

#### reveal

Reveal the vote

**Params:**
* salt (bytes32): sha3(salt)

```javascript
TODO
```

#### finalizeVote

Count the votes and calls Claim to inform of the result

**Params:**

```javascript
TODO
```

#### withdrawTokens

Withdraws CGS tokens after bonus/penalization

**Params:**

```javascript
TODO
```

#### userDeposits **Constant**

Returns the number of CGS tokens deposited per user

**Params:**
(address): user address

```javascript
let userAddress = "0x12345...";
contract.methods.userDeposits(userAddress).call():
// 5000000000000000000000
```

#### votes **Constant**

Returns information about a vote:
- date (uint): Timestamp when the claim is open
- stage (uint): Current state of the vote
  - SecretVote: Users deposit their CGS tokens and a hash of their vote.
  This stage last for TIME_TO_VOTE.
  - RevealVote: Users must reveal their vote in the previous stage.
  This stage last for TIME_TO_REVEAL.
  - Settlement: Users can withdraw their tokens with a bonus or penalization,
  depending on the outcome of the vote.
  This stage remains until a new claim is open
- votesYes (uint): Number of votes that the project is doing a proper use of the funds
- votesNo (uint): Number of votes that the project is not doing a proper use of the funds

**Params:**
(uint): vote id

```javascript
let voteId = 0;
contract.methods.votes(voteId).call():
// [456851454648, 2, 2500000000000000000000000, 152405450054545405405544]
```

#### currentVote **Constant**

Returns the id of the current vote

**Params:**

```javascript
contract.methods.currentVote().call():
// 1
```

#### roadMapMoney **Constant**

Returns the amounts of ether (in wei) to be released

**Params:**
(uint): position in the array

```javascript
let i = 2;
contract.methods.roadMapMoney(i).call():
// 2000000000000000000000
```

#### roadMapMoney **Constant**

Returns the dates (timestamps in seconds) when the ether is going to be released

**Params:**
(uint): position in the array

```javascript
let i = 2;
contract.methods.roadMapDates(i).call():
// 565416165456
```

#### vaultAddress **Constant**

Returns the address of the Vault smart contract

**Params:**

```javascript
contract.methods.vaultAddress().call():
// 0x123...
```

#### claimAddress **Constant**

Returns the address of the Claim smart contract

**Params:**

```javascript
contract.methods.claimAddress().call():
// 0x123...
```

#### icoLauncherWallet **Constant**

Returns the address of the ICO launcher

**Params:**

```javascript
contract.methods.icoLauncherWallet().call():
// 0x123...
```

### CGS events

TODO

### Claim methods

#### depositTokens

Deposits tokens. Should be executed after Token.Approve(...)

**Params:**

```javascript
TODO
```

#### withdrawTokens

Withdraws tokens

**Params:**
* amount (uint): Number of tokens

```javascript
TODO
```

#### redeem

Exchange tokens for ether if a claim success

**Params:**

```javascript
TODO
```

#### isWithdrawOpen **Constant**

Returns Whether withdraws are allowed or not

**Params:**

```javascript
contract.methods.isWithdrawOpen().call():
// true
```

#### userDeposits **Constant**

Returns the number of ICO tokens deposited per user

**Params:**
(address): user address

```javascript
let userAddress = "0x12345...";
contract.methods.userDeposits(userAddress).call():
// 5000000000000000000000
```

#### totalDeposit **Constant**

Returns the number of ICO tokens collected to open a claim

**Params:**

```javascript
contract.methods.totalDeposit().call():
// 50000000000000000000
```

#### claimPrice **Constant**

Returns the number of ICO tokens needed to open a claim

**Params:**

```javascript
contract.methods.claimPrice().call():
// 50000000000000000000
```

#### lastClaim **Constant**

Returns the timestamp when the last claim was open

**Params:**

```javascript
contract.methods.lastClaim().call():
// 465484615154
```

#### stage **Constant**

Returns the state of the claim:

 - ClaimPeriod: Users can deposit and withdraw tokens. If more than claimPrice tokens are deposited, a claim is open.
 - ClaimOpen: Deposits and withdrawals get blocked while the CGS holders vote the dispute. When the result of the vote is received, the state moves to the appropriate next stage.
 - ClaimSucceed: Users can exchange their tokens (using transferFrom) for ether for a limited period of time. Users with tokens deposited must withdraw them first. The state moves to ClaimPeriod if ClaimPeriod + TIME_BETWEEN_CLAIMS <= now.
 - ClaimFailed: Users can withdraw their tokens with a penalization. The state moves to ClaimPeriod if ClaimPeriod + TIME_BETWEEN_CLAIMS <= now.

**Params:**

```javascript
contract.methods.stage().call():
// 3
```

#### icoLauncherWallet **Constant**

Returns the address of the ICO launcher

**Params:**

```javascript
contract.methods.icoLauncherWallet().call():
// 0x123...
```

#### cgsAddress **Constant**

Returns the address of the CGS smart contract

**Params:**

```javascript
contract.methods.cgsAddress().call():
// 0x123...
```

#### tokenAddress **Constant**

Returns the address of the token smart contract

**Params:**

```javascript
contract.methods.icoLauncherWallet().call():
// 0x123...
```

### Claim events

TODO

### Vault methods

#### deposit **payable**

Deposits ether

**Params:**

```javascript
TODO
```

#### totalCollected **Constant**

Returns the total amount of ether collected by the smart contract (in wei)

**Params:**

```javascript
contract.methods.totalCollected().call():
// 11000000000000000000000
```

#### etherBalance **Constant**

Returns the ether left on the smart contract (un wei)

**Params:**

```javascript
contract.methods.etherBalance().call():
// 7000000000000000000000
```

#### cgsAddress **Constant**

Returns address of the CGS smart contract

**Params:**

```javascript
contract.methods.cgsAddress().call():
// 7000000000000000000000
```

## CGS events

TODO
