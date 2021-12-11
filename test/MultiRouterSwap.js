const chalk = require('chalk');
const {accounts, contract} = require('@openzeppelin/test-environment');
const {BN, expectRevert, time, expectEvent, constants} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');
const MultiRouterSwap = contract.fromArtifact('MultiRouterSwap');
const FaucetERC20 = contract.fromArtifact('FaucetERC20');
const FaucetERC20d6 = contract.fromArtifact('FaucetERC20d6');
const WSDN = contract.fromArtifact("WSDN");
const UniswapV2Factory = contract.fromArtifact("UniswapV2Factory");
const UniswapV2Router02 = contract.fromArtifact("UniswapV2Router02");
const numeral = require('numeral');

let yellowBright = chalk.yellowBright;
let magenta = chalk.magenta;
let cyan = chalk.cyan;
let yellow = chalk.yellow;
let red = chalk.red;
let blue = chalk.blue;

function now() {
    return parseInt((new Date().getTime()) / 1000);
}

function hours(total) {
    return parseInt(60 * 60 * total);
}

function fromWei(v) {
    return web3.utils.fromWei(v, 'ether').toString();
}

function fromGwei(v) {
    return web3.utils.fromWei(v, 'gwei').toString();
}

function d(v) {
    return numeral(v.toString()).format('0,0');
}

function toWei(v) {
    return web3.utils.toWei(v).toString();
}

const mintAmount = '1000';
const MINTED = toWei(mintAmount);
let eggPerBlock;
const DEAD_ADDR = '0x000000000000000000000000000000000000dEaD';
let dev, user, feeAddress, reserve;
const ONE = toWei('1');
const TWO = toWei('2');
const CEM = toWei('100');
const DUZENTOS = toWei('200');
const QUINHENTOS = toWei('500');

describe('Bank', async function () {
    beforeEach(async function () {
        this.timeout(60000);

        dev = accounts[0];
        user = accounts[1];
        devaddr = accounts[2];
        feeAddress = accounts[3];
        reserve = accounts[4];


        this.weth = await WSDN.new({from: dev});

        this.iron_factory = await UniswapV2Factory.new({from: dev});
        this.iron_router = await UniswapV2Router02.new({from: dev});
        await this.iron_router.init(this.iron_factory.address, this.weth.address, {from: dev});

        this.dfyn_factory = await UniswapV2Factory.new({from: dev});
        this.dfyn_router = await UniswapV2Router02.new({from: dev});
        await this.dfyn_router.init(this.dfyn_factory.address, this.weth.address, {from: dev});
        // 000000
        this.USDC = await FaucetERC20d6.new("USDC", "USDC", '1000000000', {from: dev});
        const usdcDecimals = (await this.USDC.decimals()).toString();
        console.log('usdcDecimals', usdcDecimals);
        this.IRON = await FaucetERC20.new("IRON", "IRON", MINTED, {from: dev});
        this.APOLLO = await FaucetERC20.new("APOLLO", "APOLLO", MINTED, {from: dev});

        this.router = await MultiRouterSwap.new({from: dev});
        await this.router.setup(this.iron_router.address, this.dfyn_router.address,
            this.APOLLO.address, this.IRON.address, this.USDC.address,
            {from: dev});

    });
    describe('Multi-Router-Swap', async function () {

        it('swap', async function () {
            this.timeout(60000);

            await this.USDC.approve(this.iron_router.address, '1000000000', {from: dev});
            await this.IRON.approve(this.iron_router.address, QUINHENTOS, {from: dev});
            await this.iron_router.addLiquidity(this.USDC.address, this.IRON.address, '500000000', QUINHENTOS, 0, 0, dev, now() + 60, {from: dev});

            await this.IRON.approve(this.dfyn_router.address, QUINHENTOS, {from: dev});
            await this.APOLLO.approve(this.dfyn_router.address, QUINHENTOS, {from: dev});
            await this.dfyn_router.addLiquidity(this.IRON.address, this.APOLLO.address, QUINHENTOS, QUINHENTOS, 0, 0, dev, now() + 60, {from: dev});

            let balanceOfApollo = (await this.APOLLO.balanceOf(dev)).toString();
            let balanceOfUSDC = (await this.USDC.balanceOf(dev)).toString();
            expect( balanceOfUSDC.toString() ).to.be.equal('500000000');

            await this.USDC.approve(this.router.address, '1000000', {from: dev});
            await this.router.buy('1000000', {from: dev});

            balanceOfUSDC = (await this.USDC.balanceOf(dev)).toString();
            balanceOfApollo = (await this.APOLLO.balanceOf(dev)).toString();
            console.log('USDC',balanceOfUSDC.toString() );
            console.log('APOLLO', fromWei(balanceOfApollo) );

            // await this.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(ONE, 0, [this.Apollo.address, this.IRON.address], reserve, n2, {from: user});
        });

    });


});
