const chalk = require('chalk');
const {accounts, contract} = require('@openzeppelin/test-environment');
const {BN, expectRevert, time, expectEvent, constants} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');
const HermesHeroes = contract.fromArtifact('HermesHeroes');
const FaucetERC20 = contract.fromArtifact('FaucetERC20');
const MasterChef = contract.fromArtifact('MasterChef');
const BankV2 = contract.fromArtifact('BankV2');
const Plutus = contract.fromArtifact('Plutus');
const WSDN = contract.fromArtifact("WSDN");
const IUniswapV2Pair = contract.fromArtifact("IUniswapV2Pair");
const UniswapV2Factory = contract.fromArtifact("UniswapV2Factory");
const UniswapV2Router02 = contract.fromArtifact("UniswapV2Router02");
const numeral = require('numeral');

let yellowBright = chalk.yellowBright;
let magenta = chalk.magenta;
let cyan = chalk.cyan;
let yellow = chalk.yellow;
let red = chalk.red;
let blue = chalk.blue;
let green = chalk.green;

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
const DEAD_ADDR = '0x000000000000000000000000000000000000dEaD';
let dev, user, feeAddress, reserve;
const ONE = toWei('1');
const TWO = toWei('2');
const CIN = toWei('50');
const CEM = toWei('100');
const DUZENTOS = toWei('200');
const QUINHENTOS = toWei('500');

describe('Bank', async function () {
    beforeEach(async function () {
        this.timeout(0);

        dev = accounts[0];
        user = accounts[1];
        devaddr = accounts[2];
        feeAddress = accounts[3];
        reserve = accounts[4];

        this.weth = await WSDN.new({from: dev});
        this.factory = await UniswapV2Factory.new({from: dev});
        this.router = await UniswapV2Router02.new({from: dev});
        await this.router.init(this.factory.address, this.weth.address, {from: dev});

        this.DAI = await FaucetERC20.new("DAI", "DAI", MINTED, {from: dev});
        this.nft = await HermesHeroes.new(this.DAI.address, {from: dev});


        this.Partner1 = await Plutus.new({from: dev});
            await this.Partner1.mint(dev, MINTED, {from: dev});
        this.Partner2 = await Plutus.new({from: dev});
            await this.Partner2.mint(dev, MINTED, {from: dev});

        this.Plutus = await Plutus.new({from: dev});
            await this.Plutus.mint(dev, MINTED, {from: dev});
            await this.Plutus.mint(user, MINTED, {from: dev});

        this.farm = await MasterChef.new(this.Plutus.address, 0,
            devaddr, feeAddress, this.nft.address, {from: dev});
        await this.Plutus.setMinter(this.farm.address, true, {from: dev});

        await this.factory.createPair(this.DAI.address, this.Plutus.address);
        this.pairAddr = await this.factory.getPair(this.DAI.address, this.Plutus.address);
        this.pair = await IUniswapV2Pair.at(this.pairAddr);

        await this.DAI.approve(this.router.address, MINTED, {from: dev});
        await this.Plutus.approve(this.router.address, MINTED, {from: dev});
        await this.Plutus.approve(this.router.address, MINTED, {from: user});
        await this.Partner1.approve(this.router.address, MINTED, {from: dev});
        await this.Partner2.approve(this.router.address, MINTED, {from: dev});

        await this.Plutus.setSwapToken(this.DAI.address, {from: dev});
        await this.Plutus.updateSwapRouter(this.router.address, {from: dev});

        this.bank = await BankV2.new(this.DAI.address, this.Plutus.address, {from: dev});

        await this.bank.setFeeAddress(feeAddress, {from: dev});

        await this.Plutus.setBank(this.bank.address, {from: dev});
        await this.Plutus.setMasterchef(this.farm.address, {from: dev});


    });
    
    describe('BankV2 / AddRepo', async function () {

        it('Depoist & Reward', async function () {
            this.timeout(0);

            await this.router.addLiquidityETH(this.Plutus.address, ONE, ONE, ONE, dev, now() + 60, {from: dev, value: ONE});
            await this.router.addLiquidity(this.Plutus.address, this.DAI.address, ONE, ONE, 0, 0, dev, now() + 60, {from: dev});
            await this.Plutus.updateSwapAndLiquifyEnabled(true, {from: dev});

            await this.DAI.approve(this.bank.address, MINTED, {from: dev});

            await this.bank.setPeriod(9, {from: dev});

            await this.Plutus.approve(this.bank.address, CEM, {from: dev});

            // set default pid=0 as plutus token
            await this.bank.add('100', this.Plutus.address, '100', '0', true, '3600', {from: dev});

            await this.bank.addBalance(CEM, {from: dev});
            let balanceOfDepositedDAIInTheBank = await this.DAI.balanceOf(this.bank.address);
            expect(balanceOfDepositedDAIInTheBank).to.be.bignumber.equal(CEM);

            // we deposit 50 plutus
            await this.bank.deposit(0, CIN, this.bank.address, {from: dev});

            // revert on withdraw.
            await expectRevert(this.bank.withdraw(0, CEM, {from: dev}), '!allowWithdraw');

            // revert on emergency withdraw
            await expectRevert(this.bank.emergencyWithdraw(0, {from: dev}), '!allowEmergencyWithdraw');

            await expectRevert(this.bank.setPeriod(3, {from: user}), 'Ownable: caller is not the owner');

            const balanceOfFeeAddress = await this.Plutus.balanceOf(feeAddress);
            expect( fromWei(balanceOfFeeAddress) ).to.be.equal('0.485');

            const bank = this.bank, dai = this.DAI;



            async function dump(title){
                await bank.massUpdatePools({from: dev});
                const startBlock = ((await bank.startBlock()).toString());
                const endBlock = ((await bank.endBlock()).toString());
                const treasure = fromWei((await bank.treasure()).toString());
                const allocated = fromWei((await bank.allocated()).toString());
                const blocks = (await bank.blocks()).toString();
                const bankBalance = fromWei(await dai.balanceOf(bank.address)).toString();
                const userBalance = fromWei(await dai.balanceOf(dev)).toString();
                const getBlock = ((await bank.getBlock()).toString());

                console.log(green(title)+red(' treasure='+treasure+' allocated='+allocated+' blocks='+blocks+' bankBalance='+bankBalance)+blue(' block='+getBlock)+' start='+startBlock+' end='+endBlock);
                const statsRepoAdded = fromWei((await bank.statsRepoAdded()).toString());
                const statsRepoTotalAdded = fromWei((await bank.statsRepoTotalAdded()).toString());
                const statsRepoCount = ((await bank.statsRepoCount()).toString());
                const statsRepoTotalCount = ((await bank.statsRepoTotalCount()).toString());
                const statsRestarts = ((await bank.statsRestarts()).toString());
                const pendingToken = fromWei((await bank.pendingToken('0', dev)).toString());

                const stats = ' RepoTotalCount='+statsRepoTotalCount+' RepoTotalAdded='+statsRepoTotalAdded+' Restarts='+blue(statsRestarts)+
                              ' RepoCount='+statsRepoCount+' RepoAdded='+statsRepoAdded;
                console.log(magenta(stats));
                console.log(green(' pendingToken='+pendingToken)+yellow(' userBalance='+userBalance));
            }
            await dump('a');
            await time.advanceBlock();

            await dump('b');
            await time.advanceBlock();

            await dump('c');
            await time.advanceBlock();

            await dump('d');
            await time.advanceBlock();

            await dump('e');

            await time.advanceBlock();
            await dump('e');

            await time.advanceBlock();
            await dump('f before deposit');
            await this.bank.forward({from: dev});
            await this.bank.deposit('0', '0', this.bank.address, {from: dev});
            await dump('g after deposit');
            console.log(blue('---------------------add 50--------------------'));
            await this.bank.addBalance(CIN, {from: dev});
            await dump('h aftert addBalance');
            await time.advanceBlock();
            await dump('i');
            await time.advanceBlock();
            await dump('j before deposit');
            await this.bank.deposit('0', '0', this.bank.address, {from: dev});
            await dump('j after deposit');
            await time.advanceBlock();
            await dump('1');
            await time.advanceBlock();
            await dump('2');
            await time.advanceBlock();
            await this.bank.deposit('0', '0', this.bank.address, {from: dev});
            await dump('3');

        });


    });


    describe('BankV2 / transfer', async function () {

        it('cycles via transfer', async function () {
            this.timeout(0);

            await this.router.addLiquidityETH(this.Plutus.address, ONE, ONE, ONE, dev, now() + 60, {from: dev, value: ONE});
            await this.router.addLiquidity(this.Plutus.address, this.DAI.address, ONE, ONE, 0, 0, dev, now() + 60, {from: dev});
            await this.Plutus.updateSwapAndLiquifyEnabled(true, {from: dev});

            await this.DAI.approve(this.bank.address, MINTED, {from: dev});

            await this.bank.setPeriod(9, {from: dev});

            await this.Plutus.approve(this.bank.address, CEM, {from: dev});

            // set default pid=0 as plutus token
            await this.bank.add('100', this.Plutus.address, '100', '0', true, '3600', {from: dev});

            // we deposit 50 plutus
            await this.bank.deposit(0, CIN, this.bank.address, {from: dev});

            // revert on withdraw.
            await expectRevert(this.bank.withdraw(0, CEM, {from: dev}), '!allowWithdraw');

            // revert on emergency withdraw
            await expectRevert(this.bank.emergencyWithdraw(0, {from: dev}), '!allowEmergencyWithdraw');

            await expectRevert(this.bank.setPeriod(3, {from: user}), 'Ownable: caller is not the owner');

            const balanceOfFeeAddress = await this.Plutus.balanceOf(feeAddress);
            expect( fromWei(balanceOfFeeAddress) ).to.be.equal('0.485');

            const bank = this.bank, dai = this.DAI;



            async function dump(title){
                await bank.massUpdatePools({from: dev});
                const startBlock = ((await bank.startBlock()).toString());
                const endBlock = ((await bank.endBlock()).toString());
                const treasure = fromWei((await bank.treasure()).toString());
                const allocated = fromWei((await bank.allocated()).toString());
                const blocks = (await bank.blocks()).toString();
                const bankBalance = fromWei(await dai.balanceOf(bank.address)).toString();
                const userBalance = fromWei(await dai.balanceOf(dev)).toString();
                const getBlock = ((await bank.getBlock()).toString());

                console.log(green(title)+red(' treasure='+treasure+' allocated='+allocated+' blocks='+blocks+' bankBalance='+bankBalance)+blue(' block='+getBlock)+' start='+startBlock+' end='+endBlock);
                const statsRepoAdded = fromWei((await bank.statsRepoAdded()).toString());
                const statsRepoTotalAdded = fromWei((await bank.statsRepoTotalAdded()).toString());
                const statsRepoCount = ((await bank.statsRepoCount()).toString());
                const statsRepoTotalCount = ((await bank.statsRepoTotalCount()).toString());
                const statsRestarts = ((await bank.statsRestarts()).toString());
                const pendingToken = fromWei((await bank.pendingToken('0', dev)).toString());

                const stats = ' RepoTotalCount='+statsRepoTotalCount+' RepoTotalAdded='+statsRepoTotalAdded+' Restarts='+blue(statsRestarts)+
                    ' RepoCount='+statsRepoCount+' RepoAdded='+statsRepoAdded;
                console.log(magenta(stats));
                console.log(green(' pendingToken='+pendingToken)+yellow(' userBalance='+userBalance));
            }

            await this.Plutus.transfer(user, ONE, {from: dev} );
            await this.Plutus.transfer(devaddr, ONE, {from: dev} );
            await this.Plutus.transfer(reserve, ONE, {from: dev} );

            await this.Plutus.transfer(devaddr, (await this.Plutus.balanceOf(user)), {from: user});
            await dump('a');
            await time.advanceBlock();

            await this.Plutus.transfer(user, (await this.Plutus.balanceOf(devaddr)), {from: devaddr});
            await dump('b');
            await time.advanceBlock();

            await this.Plutus.transfer(user, (await this.Plutus.balanceOf(devaddr)), {from: devaddr});
            await dump('c');
            await time.advanceBlock();

            await this.Plutus.transfer(devaddr, (await this.Plutus.balanceOf(user)), {from: user});
            await dump('d');
            await time.advanceBlock();

            await this.Plutus.transfer(user, (await this.Plutus.balanceOf(devaddr)), {from: devaddr});
            await dump('e');

            await this.Plutus.transfer(devaddr, (await this.Plutus.balanceOf(user)), {from: user});
            await time.advanceBlock();
            await dump('e');

            await this.Plutus.transfer(user, (await this.Plutus.balanceOf(devaddr)), {from: devaddr});
            await time.advanceBlock();
            await dump('f before deposit');

            await this.bank.deposit('0', '0', this.bank.address, {from: dev});

            await this.Plutus.transfer(devaddr, (await this.Plutus.balanceOf(user)), {from: user});
            await dump('g after deposit');
            console.log(blue('---------------------add 50--------------------'));

            await this.Plutus.transfer(user, (await this.Plutus.balanceOf(devaddr)), {from: devaddr});
            await dump('h aftert addBalance');

            await this.Plutus.transfer(devaddr, (await this.Plutus.balanceOf(user)), {from: user});
            await time.advanceBlock();

            await this.Plutus.transfer(user, (await this.Plutus.balanceOf(devaddr)), {from: devaddr});
            await dump('i');
            await time.advanceBlock();

            await this.Plutus.transfer(devaddr, (await this.Plutus.balanceOf(user)), {from: user});
            await dump('j before deposit');
            await this.bank.deposit('0', '0', this.bank.address, {from: dev});
            await dump('j after deposit');

            await this.Plutus.transfer(user, (await this.Plutus.balanceOf(devaddr)), {from: devaddr});
            await time.advanceBlock();
            await dump('1');

            await this.Plutus.transfer(devaddr, (await this.Plutus.balanceOf(user)), {from: user});
            await time.advanceBlock();
            await dump('2');


            await this.Plutus.transfer(user, (await this.Plutus.balanceOf(devaddr)), {from: devaddr});
            await time.advanceBlock();
            await this.bank.deposit('0', '0', this.bank.address, {from: dev});
            await dump('3');

        });


    });

});
