# CGS Smart Contracts

Smart contracts for the CGS platform.

For the first version, there will be three smart contracts for each ICO:
- **CGSBinaryVote**: Manages the vote among CGS holders.
- **CGS**: Collects ICO tokens to create claims and manage the funds at Vault.
- **Vault**: Stores the Ether collected. It is created from CGS.

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


To obtain the address, you first have to deploy the CGS and the CGSBinaryVote. Its addresses are going to be written in the console.

```
Truffle migrate
```

The Vault is created from the CGS smart contract. Its address can be accessed using the public method `CGS.vaultAddress.call()`

## TODO

* Update Interface documentation
* Create CGS factory to simplify the deployment
* Fix Redeem formula

## Interface

### CGSBinaryVote methods

#### vote

Deposits CGS tokens and vote. Should be executed after Token.Approve(...) or Token.increaseApproval(...)

**Params:**
* voteId (uint): ID of the vote
* numTokens (uint): number of tokens used to vote
* secretVote (bytes32): Hash of the vote + salt. sha3(vote + sha3(salt))

```javascript
TODO
```

#### reveal

Reveal the vote

**Params:**
* voteId (uint): ID of the vote
* salt (bytes32): Random salt used to vote. sha3(salt)

```javascript
TODO
```

#### withdrawTokens

Withdraws CGS tokens after bonus/penalization

**Params:**
* voteId (uint): ID of the vote

```javascript
TODO
```

#### getStage **Constant**

Returns the actual stage of a vote.
The stages are:
* 0: SecretVote: Users deposit their CGS tokens and a hash of their vote. This stage last for TIME_TO_VOTE.
* 1: RevealVote: Users must reveal their vote in the previous stage. This stage last for TIME_TO_REVEAL.
* 2: Settlement: Users can withdraw their tokens with a bonus or penalization, depending on the outcome of the vote.

**Params:**
* voteId (uint): ID of the vote

```javascript
let voteId = 0;
contract.methods.getStage(voteId).call();
// 0
```

#### hasUserRevealed **Constant**

Returns if the user has revealed his vote

**Params:**
* voteId (uint): ID of the vote
* who (address): User address

```javascript
let voteId = 0;
let userAddress = "0x12345...";
contract.methods.hasUserRevealed(voteId, userAddress).call();
// true
```

#### getRevealedVote **Constant**

Returns the revealed vote of the user

**Params:**
* voteId (uint): ID of the vote
* who (address): User address

```javascript
let voteId = 0;
let userAddress = "0x12345...";
contract.methods.getRevealedVote(voteId, userAddress).call();
// true
```

#### getUserDeposit **Constant**

Returns amount of tokens deposited by a user in a vote

**Params:**
* voteId (uint): ID of the vote
* who (address): User address

```javascript
let voteId = 0;
let userAddress = "0x12345...";
contract.methods.getUserDeposit(voteId, userAddress).call();
// 5000000000000000000000
```

#### votes **Constant**

Returns information about a vote:
- date (uint): Timestamp when the claim is open
- stage (uint): Current state of the vote (for the actual stage, see `getStage()`)
- votesYes (uint): Votes that the project is doing a proper use of the funds. Updated during Reveal stage
- votesNo (uint): Votes that the project is not doing a proper use of the funds. Updated during Reveal stage
- callback (address): The address to call when the vote ends

**Params:**
* (uint): ID of the vote

```javascript
let voteId = 0;
contract.methods.votes(voteId).call();
// [456851454648, 2, 2500000000000000000000000, 1750000000000000000000000, 0x12345678912345679abcdef]
```

#### numVotes **Constant**

Number of elements in the array votes

**Params:**

```javascript
contract.methods.numVotes().call():
// 1
```

#### cgsToken **Constant**

Returns the address of the CGS token smart contract

**Params:**

```javascript
contract.methods.cgsToken().call():
// 0x123...
```

### CGS events

#### ev_NewStage **Constant**

Launched every time the stage of a project changes.

**Params:**
* (indexed) voteId (uint): ID of the vote
* stage (uint): New stage

#### ev_NewVote **Constant**

Launched when a new Vote is created.

**Params:**
* (indexed) voteId (uint): ID of the vote
* callback (address): Callback address

#### ev_Vote **Constant**

Launched every time a user votes.

**Params:**
* (indexed) voteId (uint): ID of the vote
* who (address): User address
* amount (uint): Number of tokens used to vote

#### ev_Reveal **Constant**

Launched every time a user reveals his vote.

**Params:**
* (indexed) voteId (uint): ID of the vote
* who (address): User address
* amount (uint): Number of tokens used to vote
* value (bool): revealed vote


### CGS methods

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
