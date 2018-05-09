# CGS Smart Contracts

Smart contracts for the CGS platform.

For the first version, there will be four types of smart contracts:
- **CGSBinaryVote**: Manages the vote among CGS holders.
- **CGSFactory**: Creates new CGS smart contracts.
- **CGS**: Collects ICO tokens to create claims and manage the funds at Vault. One of these contracts is deployed per ICO.
- **Vault**: Stores the Ether collected. It is created from CGS.  One of these contracts is deployed per ICO.

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

With that command, the following contracts are going to be deployed:

As persistent contracts:
* Test CGS token
* CGSBinaryVote
* CGSFactory

As a sample ICO with CGS:
* Test ICO token
* CGS
* Vault

To deploy more CGS smart contracts, you can call the function `create()` of CGSFactory.

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

## Documentation
(Check the Wiki)[https://gitlab.com/icofunding-com/cgs-contracts/wikis/home]
