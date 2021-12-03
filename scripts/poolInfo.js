const Plutus = artifacts.require('Plutus');
const MasterChef = artifacts.require('MasterChef');
const UniswapV2Pair_ABI = require('./abi/UniswapV2Pair.json');

async function poolInfo(ctx) {
    try {
        const r = await ctx.poolInfo(1);
        console.log(' - ', r.lpToken);
        const lp_ctx = new web3.eth.Contract(UniswapV2Pair_ABI, r.lpToken);
        const token0_addr = await lp_ctx.methods.token0().call();
        const token1_addr = await lp_ctx.methods.token1().call();
        const token0_ctx = new web3.eth.Contract(require('./abi/BEP20_ABI.json'), token0_addr);
        const token1_ctx = new web3.eth.Contract(require('./abi/BEP20_ABI.json'), token1_addr);
        const token0_symbol = await token0_ctx.methods.symbol().call();
        const token1_symbol = await token1_ctx.methods.symbol().call();
        const pair_name = token0_symbol + "-" + token1_symbol;
        console.log(' - ', pair_name, r.lpToken);
    } catch (e) {
        console.error(e.toString());
    }
    process.exit(0);
}

module.exports = async function (deployer) {
    const ct = '0xafd37a86044528010d0e70cdc58d0a9b5eb03206';
    const ctx = await MasterChef.at(ct);
    await poolInfo(ctx);
}
