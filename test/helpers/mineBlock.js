const mineBlock = (addSeconds) => {
    return web3.currentProvider.send({
        jsonrpc: "2.0",
        method: "evm_mine",
        params: [],
        id: 0
    })
};

module.exports = mineBlock;
