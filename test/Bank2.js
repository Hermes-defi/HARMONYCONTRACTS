const chalk = require('chalk');
const {accounts, contract} = require('@openzeppelin/test-environment');
const {BN, expectRevert, time, expectEvent, constants} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');
const HermesHeroes = contract.fromArtifact('HermesHeroes');
const FaucetERC20 = contract.fromArtifact('FaucetERC20');
const MasterChef = contract.fromArtifact('MasterChef');
const Bank = contract.fromArtifact('Bank2');
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

        eggPerBlock = web3.utils.toWei('1');

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

        this.bank = await Bank.new(
            this.Plutus.address,
            this.DAI.address,
            this.weth.address,
            this.router.address, {from: dev});

        await this.Plutus.setBank(this.bank.address, {from: dev});
        await this.Plutus.setMasterchef(this.farm.address, {from: dev});


    });
    describe('Bank2', async function () {
/*
        it('work with pools', async function () {
            const BANK = this.bank, DAI = this.DAI, PARTNER1 = this.Partner1, PARTNER2 = this.Partner2;

            function date(ts) {
                const pad = (n, s = 2) => (`${new Array(s).fill(0)}${n}`).slice(-s);
                const d = new Date(ts * 1000);
                return red(`${pad(d.getFullYear(), 4)}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`);
            }

            async function stats(title) {
                console.log(blue('***' + title + '***'));
                const p1Bal = await PARTNER1.balanceOf(dev);
                const p2Bal = await PARTNER2.balanceOf(dev);
                const ironBalance = await DAI.balanceOf(BANK.address);
                const ironDevBalance = await DAI.balanceOf(dev);
                const totalAmount = await BANK.totalAmount();
                const user = await BANK.userinfo(dev);
                const pendingDAI = await BANK.pendingDAI(dev);
                const pendingrewards = await BANK.pendingrewards(dev);
                const getTimestamp = parseInt( (await BANK.getTimestamp()).toString() );
                const usdcinfo = await BANK.usdcinfo();
                const lastRewardTime = parseInt(usdcinfo.lastRewardTime.toString());
                const ttl = getTimestamp-lastRewardTime;

                let rewards = [];
                for( let i in pendingrewards ){
                    rewards[i] = pendingrewards[i].toString();
                }
                let rewardsStr = rewards.join(", ");

                console.log(yellow('   PENDING DAI=['+fromWei(pendingDAI)+'] MY DAI BAL=['+fromWei(ironDevBalance)+'] BANK/DAI=' + fromWei(ironBalance))+' PIDS='+user.pids.join(','));
                console.log(yellow('   BANK TOTAL APOLLO=['+fromWei(totalAmount)+'] TTL='+ttl+" | MY PENDING REWARDS="+rewardsStr+ '   MY P1 BAL=['+fromWei(p1Bal)+'] MY P2 BAL='+fromWei(p1Bal) ));

                const endtime = await BANK.endtime();
                const seconds = endtime - getTimestamp;
                console.log(cyan('   TIME: NOW=' + date(getTimestamp) + ' END=' + date(endtime) + ' SECONDS=' + seconds ));
            }

            async function pool_stats(pid, title) {
                console.log(blue('***' + title + '***'));
                const poolLength = parseInt(await BANK.poolLength());
                const poolInfo = await BANK.poolInfo(pid);
                const endtime = poolInfo.endTime;
                const timenow = await BANK.getTimestamp();
                const seconds = endtime - timenow;
                const initamt = await poolInfo.initamt;
                const amount = fromWei(await poolInfo.amount);
                const tokenPerSec = fromWei(await poolInfo.tokenPerSec);
                for( let pid = 0 ; pid < poolLength; pid++) {
                    console.log(magenta('   PID=' + pid + ' TIME: NOW=' + date(timenow) + " END=" + date(endtime) + "  SECONDS=" + seconds));
                    console.log(magenta('   PID=' + pid + ' STARTED=' + initamt + ' DEPOSITED=' + amount+ ' TOKEN/SEC=' + tokenPerSec ));
                }
            }

            this.timeout(60000);

            await this.DAI.approve(this.bank.address, MINTED, {from: dev});
            // await this.bank.setPrize(1000, {from: dev});

            this.timeout(60000);
            const getTime = await this.bank.getTime();
            const n1 = parseInt(getTime.toString()) + 10;
            const n2 = n1 + 60;

            console.log(cyan('INTERVALE: N1=' + n1 + ' N2=' + n2));
            await stats('NO BALANCE');


            await this.Partner1.transfer(this.bank.address, QUINHENTOS, {from: dev});
            await this.bank.addpool(fromWei(QUINHENTOS), n1, n2, this.Partner1.address, this.router.address, {from: dev});

            await this.Partner2.transfer(this.bank.address, QUINHENTOS, {from: dev});
            await this.bank.addpool(fromWei(QUINHENTOS), n1, n2, this.Partner2.address, this.router.address, {from: dev});

            // await this.router.addLiquidity(this.DAI.address, this.Plutus.address, QUINHENTOS, QUINHENTOS, 0, 0, dev, now() + 60, {from: dev});
            await this.router.addLiquidityETH(this.Partner1.address, ONE, ONE, ONE, dev, now() + 60, {from: dev, value: ONE});
             await this.router.addLiquidityETH(this.Partner2.address, ONE, ONE, ONE, dev, now() + 60, {from: dev, value: ONE});
            // await this.router.addLiquidityETH(this.Plutus.address, ONE, ONE, ONE, dev, now() + 60, {from: dev, value: ONE});
            // await this.router.swapExactTokensForTokensSupportingFeeOnTransferTokens(ONE, 0, [this.Plutus.address, this.DAI.address], reserve, n2, {from: user});
            await this.Plutus.updateSwapAndLiquifyEnabled(false, {from: dev});
            await this.Plutus.transfer(reserve, TWO, {from: user});

            await this.bank.start(30, {from: dev});

            await this.Plutus.approve(this.bank.address, CEM, {from: dev});
            await this.Plutus.approve(this.bank.address, CEM, {from: user});
            await this.Plutus.approve(this.bank.address, CEM, {from: reserve});

            await stats('AFTER FIRST SWAP OF 1 APOLLO');
            await this.bank.deposit(CEM, {from: dev});
            await this.bank.deposit(CEM, {from: user});
            // await this.bank.deposit(CEM, {from: reserve});
            await stats('ENTERING ENROLLS SECTION:');
            await pool_stats(0, '> START ENROLLS!');
            await this.bank.enroll('0', {from: dev});
            await this.bank.enroll('1', {from: dev});
            await this.bank.enroll('0', {from: user});
            await this.bank.enroll('1', {from: user});
            await pool_stats(0, '< END ENROLLS! RUN DEPOSITS=0...');
            await this.bank.deposit(0,{from: user});
            await this.bank.deposit(0,{from: dev});
            await stats('AFTER ENROLLS AND BEFORE COMPOUND:');
            // await this.bank.compound({from: dev});
            await stats('AFTER COMPOUND');

        });
*/
        it('manual repo', async function () {
            this.timeout(0);
            const BANK = this.bank, DAI = this.DAI, APOLLO = this.Plutus;
            const INTERVAL = 20;

            await this.router.addLiquidityETH(this.Plutus.address, ONE, ONE, ONE, dev, now() + 60, {from: dev, value: ONE});
            await this.router.addLiquidity(this.Plutus.address, this.DAI.address, ONE, ONE, 0, 0, dev, now() + 60, {from: dev});
            await this.Plutus.updateSwapAndLiquifyEnabled(true, {from: dev});

            // await this.bank.addpool('0', n1, n2,
            //     this.Plutus.address, this.router.address, {from: dev});

            await this.DAI.approve(this.bank.address, MINTED, {from: dev});
            await this.bank.setPrize(1000, {from: dev});
            await this.bank.addManualRepo(QUINHENTOS, {from: dev});


            let balanceOfDepositedIronInTheBank = await this.DAI.balanceOf(this.bank.address);
            expect(balanceOfDepositedIronInTheBank).to.be.bignumber.equal(QUINHENTOS);

            // burn 1 token to enter lottery, default 5
            await this.bank.setMin(ONE, {from: dev});


            await this.bank.start(INTERVAL, {from: dev});

            await this.Plutus.approve(this.bank.address, CEM, {from: dev});
            await this.bank.deposit(CEM, {from: dev});

            await this.Plutus.approve(this.bank.address, CEM, {from: user});
            await this.bank.deposit(CEM, {from: user});

            let balanceOfBurned = await this.Plutus.balanceOf(DEAD_ADDR);
            expect(balanceOfBurned).to.be.bignumber.equal(DUZENTOS);

            await stats('ON DEPOSIT, BEFORE COMPOUND:');

            await BANK.compound({from: dev});
            await stats('1# COMPOUND:');

            await BANK.compound({from: dev});
            await stats('2# COMPOUND:');

            await BANK.compound({from: dev});
            await stats('3# COMPOUND:');

            await this.bank.addManualRepo(CEM, {from: dev});
            await this.bank.start(INTERVAL, {from: dev});

            await BANK.compound({from: dev});
            await stats('4# COMPOUND:  +100 +START');

            await BANK.compound({from: dev});
            await stats('5# COMPOUND:');

            await BANK.compound({from: dev});
            await stats('6# COMPOUND:');

            await BANK.compound({from: dev});
            await stats('7# COMPOUND:');

            await BANK.compound({from: dev});
            await stats('8# COMPOUND:');

            await BANK.compound({from: dev});
            await stats('9# COMPOUND:');

            async function stats(TITLE) {
                console.log(yellow(TITLE) + blue(' ---------------------------------------------------------'))
                let endtime = await BANK.endtime();
                let timenow = await BANK.getTimestamp();
                const seconds = endtime - timenow;
                let totalpayout = await BANK.totalpayout();
                let lastpayout = await BANK.lastpayout();
                let totalticket = await BANK.totalticket();
                let totalBurnt = await BANK.totalBurnt();
                let totalAmount = await BANK.totalAmount();
                let lotwinner = await BANK.lotwinner();
                let userInfo = await BANK.userinfo(dev);
                const balanceOfBankDAI = await DAI.balanceOf(BANK.address);
                let prizePoints = await BANK.lotrate(); // % of contract balance to pai to winner
                let lotsize = await BANK.lotsize(); // amount of apollo used in buy/burn and paid as prize
                const prizePct = prizePoints / 100; // just the %
                const prize = (fromWei(balanceOfBankDAI) * prizePoints) / 10000;

                const balanceOfDevDAI = await DAI.balanceOf(dev);
                const balanceOfDevAPOLLO = await APOLLO.balanceOf(dev);
                const mytickets = await BANK.mytickets(dev);
                console.log(cyan('    - LOT=' + fromWei(lotsize) + ' PRIZE=' + prize + ' %=' + prizePct + ' TIME: END=' + endtime + " NOW=" + timenow + " SECONDS=" + seconds));
                console.log(magenta('    - GLOBAL: DAI=' + fromWei(balanceOfBankDAI) + ' TOTAL BURN=' + fromWei(totalBurnt) + " DEPOSITED=" + fromWei(totalAmount) + " TICKETS=" + totalticket));
                console.log(yellowBright('    - USER: BALANCE DEPOSITED=' + fromWei(userInfo.amount) + ' DAI=' + fromWei(balanceOfDevDAI) + " APOLLO=" + fromWei(balanceOfDevAPOLLO)) + " MY TICKETS=" + mytickets.join(","));
                if (lotwinner != '0x0000000000000000000000000000000000000000') {
                    console.log(red('    - GLOBAL WINNER=' + lotwinner + " PAYOUTS: total=" + fromWei(totalpayout) + " LAST=" + fromWei(lastpayout)));
                }
            }

        });


    });


});
