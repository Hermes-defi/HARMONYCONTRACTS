// truffle migrate --f 6 --to 6 --network dev
const Plutus = artifacts.require('Plutus');
const MasterChef = artifacts.require('MasterChef');
module.exports = async function (deployer, network, accounts) {

    await deployer.deploy(Plutus);
    const token = await Plutus.deployed();


    let startBlock = '19600000';
    if( network == 'dev')
        startBlock = '1';
    const devAddr = '0x7cef2432A2690168Fb8eb7118A74d5f8EfF9Ef55';
    const feeAddr = '0x80956dCf2a4302176B0cE0c0b4fCE71081b1d6A7';
    const nft = '0x0000000000000000000000000000000000000000';
    await deployer.deploy(MasterChef, token.address,
        startBlock, devAddr, feeAddr, nft);
    const mc = await MasterChef.deployed();

    console.log(UniswapV2Router02.address, _factory.address, wsdn.address);
};
