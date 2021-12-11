/*
* This is the testcase for PlutusPreSale presale contract.
* The process is simple:
*
* - get a quote, pass the amount of Plutus you want and
*   get the cost in ONE.
*
* - Execute the buy function passing the amount of ONE
*   in value to get the pPlutus receipt token.
*
* - Later you can swap pPlutus for Plutus final token.
*
* */

const web3 = require('web3');
const {accounts, contract} = require('@openzeppelin/test-environment');
const {BN, expectRevert, time, expectEvent, constants} = require('@openzeppelin/test-helpers');
const {expect} = require('chai');
const Token = contract.fromArtifact('Plutus');
const ctx = contract.fromArtifact('PlutusPreSale');
const startBlock = 0;
const endBlock = 1999999999;
let dev, user, fee;
let amount, pPLUTUSPrice;
const fromWei = ( v ) => v ? web3.utils.fromWei(v, 'ether').toString() : '-';
const toWei = ( v ) =>  v ? web3.utils.toWei(v) : '-';

// we love colorized console
const chalk = require('chalk');
const yellow = function() { console.log(chalk.yellowBright(...arguments)) }
const magenta = function() { console.log(chalk.magenta(...arguments)) }
const cyan = function() { console.log(chalk.cyan(...arguments)) }
const red = function() { console.log(chalk.red(...arguments)) }
const blue = function() { console.log(chalk.blue(...arguments)) }
const green = function() { console.log(chalk.green(...arguments)) }


describe('PlutusPreSale', function () {
    beforeEach(async function () {
        dev = accounts[0];
        user = accounts[1];
        fee = accounts[2];
        amount = web3.utils.toWei('120000');
        this.PresaleToken = await Token.new({from: dev});
        this.Final = await Token.new({from: dev});
        this.dai = await Token.new({from: dev});
    });

    it('Test quoteAmounts', async function () {
        this.timeout(0);

        pPLUTUSPrice = '1.4'; // 1.4
        this.ctx = await ctx.new(startBlock, endBlock, toWei(pPLUTUSPrice),
            this.PresaleToken.address, this.dai.address, {from: dev});
        await this.ctx.setFeeAddress(fee, {from: dev});

        await this.ctx.setUserIsWL1(dev, true, {from: dev});
        await this.ctx.setUserIsWL2(dev, true, {from: dev});



        await this.PresaleToken.mint(this.ctx.address, toWei('200'), {from: dev});
        await this.dai.mint(dev, toWei('20000'), {from: dev});
        await this.dai.approve(this.ctx.address, toWei('20000'), {from: dev});

        let quote = toWei('100');
        let quoteAmounts = await this.ctx.quoteAmounts(quote, dev);

        const price = pPLUTUSPrice;
        yellow('1) User want to buy '+fromWei(quoteAmounts.tokenPurchaseAmount)+' of '+fromWei(quoteAmounts.limit)+' pPlutus at $'+price  );
        yellow('Total to be paid in DAI: $'+fromWei(quoteAmounts.pPlutusInDAI) );
        yellow('- Sub-total to be paid in DAI '+fromWei(quoteAmounts.inDAI) );

        let pPlutusBalanceOfDevAddr = await this.PresaleToken.balanceOf(dev);
        let daiBalanceOfTaxAddr = await this.dai.balanceOf(fee);

        expect(pPlutusBalanceOfDevAddr).to.be.bignumber.equal('0');
        expect(daiBalanceOfTaxAddr).to.be.bignumber.equal('0');

        await this.ctx.buy(quote, {from: dev});

        pPlutusBalanceOfDevAddr = await this.PresaleToken.balanceOf(dev);
        daiBalanceOfTaxAddr = await this.dai.balanceOf(fee);

red('pPlutusBalanceOfDevAddr='+fromWei(pPlutusBalanceOfDevAddr));
red('quote='+fromWei(quote));

        expect(pPlutusBalanceOfDevAddr).to.be.bignumber.equal(quote);
        expect(daiBalanceOfTaxAddr).to.be.bignumber.equal(quoteAmounts.inDAI);

        quote = toWei('100');
        quoteAmounts = await this.ctx.quoteAmounts(quote, dev);
        magenta('2) User want to buy '+fromWei(quoteAmounts.tokenPurchaseAmount)+' of '+fromWei(quoteAmounts.limit)+' pPlutus at $'+price  );
        magenta('Total to be paid in DAI: $'+quoteAmounts.pPlutusInDAI.toString() );
        magenta('- Sub-total to be paid in DAI '+quoteAmounts.inDAI.toString() );

        await this.ctx.buy(quote, {from: dev});

        pPlutusBalanceOfDevAddr = await this.PresaleToken.balanceOf(dev);
        expect(pPlutusBalanceOfDevAddr).to.be.bignumber.equal( toWei('200') );
        magenta('User pPlutus balance: '+fromWei(pPlutusBalanceOfDevAddr));


        await this.Final.mint(this.ctx.address, toWei('200'), {from: dev});

        // we need to approve contract to burn my presale tokens in swap for tokens:
        await this.PresaleToken.approve(this.ctx.address, toWei('10000'), {from: dev});

        let getBlock = (await this.ctx.getBlock()).toString();
        await this.ctx.setStartEndBlock(startBlock, getBlock, {from: dev});
        const swapStartBlock = parseInt(getBlock) + 1;
        const swapEndBlock = swapStartBlock + 10;
        await this.ctx.setSwapStart(swapStartBlock, swapEndBlock, this.Final.address, {from: dev});
        await this.ctx.swapAll({from: dev});

        magenta('getBlock', getBlock, swapStartBlock, swapEndBlock);
        const tempBalanceOfDevAddr = await this.PresaleToken.balanceOf(dev);
        const finalBalanceOfDevAddr = await this.Final.balanceOf(dev);
        expect(tempBalanceOfDevAddr).to.be.bignumber.equal( new BN('0') );
        expect(finalBalanceOfDevAddr).to.be.bignumber.equal( toWei('200') );
        magenta('User token balance: '+fromWei(finalBalanceOfDevAddr));

        getBlock = (await this.ctx.getBlock()).toString();
        await this.ctx.setSwapStart(swapStartBlock, getBlock, this.Final.address, {from: dev});
        await this.ctx.burnUnclaimed({from: dev});

    });










    describe('buy', function () {
        /*
        it('PRESALE 50%/$1.2/$0.7', async function () {
            this.timeout(60000);

            ratio = '50'; // 50%
            pPLUTUSPrice = '2.2'; // 1.2
            this.ctx = await ctx.new(startBlock, endBlock, toWei(pPLUTUSPrice),
                this.PresaleToken.address, this.dai.address, {from: dev});
            await this.ctx.setFeeAddress(fee, {from: dev});

            const pPLUTUS_first_round = toWei('46875');

            await this.PresaleToken.mint(this.ctx.address, pPLUTUS_first_round, {from: dev});

            await this.dai.mint(dev, '10000000000', {from: dev}); // 1,000
            await this.dai.approve(this.ctx.address, toWei('100000'), {from: dev});

            let quoteAmountInDAIC = await this.ctx.quoteAmountInDAIC( toWei('100') );
            console.log('quoteAmountInDAIC', quoteAmountInDAIC.toString() )

            let quote = toWei('1000');
            let quoteAmounts = await this.ctx.quoteAmounts(quote, dev);

            const price = pPLUTUSPrice;
            console.log('1) User want to buy '+fromWei(quoteAmounts.tokenPurchaseAmount)+' of '+fromWei(quoteAmounts.limit)+' pPlutus at $'+price  );
            console.log('Total to be paid in DAI: $'+quoteAmounts.pPlutusInDAI.toString() );
            console.log('- Sub-total to be paid in DAIC     ('+ratio+'%)', quoteAmounts.inDAI.toString() );

            await this.ctx.buy(quote, {from: dev});

            let pPlutusBalanceOfDevAddr = await this.PresaleToken.balanceOf(dev);
            let daiBalanceOfTaxAddr = await this.dai.balanceOf(fee);

            expect(pPlutusBalanceOfDevAddr).to.be.bignumber.equal(quote);
            expect(daiBalanceOfTaxAddr).to.be.bignumber.equal(quoteAmounts.inDAI);

            quote = toWei('5000');
            quoteAmounts = await this.ctx.quoteAmounts(quote, dev);
            console.log('2) User want to buy '+fromWei(quoteAmounts.tokenPurchaseAmount)+' of '+fromWei(quoteAmounts.limit)+' pPlutus at $'+price  );
            console.log('Total to be paid in DAI: $'+quoteAmounts.pPlutusInDAI.toString() );
            console.log('- Sub-total to be paid in DAIC ('+ratio+'%)', quoteAmounts.inDAI.toString() );

            await this.ctx.buy(quote, {from: dev});

            pPlutusBalanceOfDevAddr = await this.PresaleToken.balanceOf(dev);
            expect(pPlutusBalanceOfDevAddr).to.be.bignumber.equal( toWei('4000') );
            console.log('User pPlutus balance: '+fromWei(pPlutusBalanceOfDevAddr));

            await this.Final.mint(this.ctx.address, pPLUTUS_first_round, {from: dev});
            await this.PresaleToken.approve(this.ctx.address, toWei('10000'), {from: dev});
            let getBlock = (await this.ctx.getBlock()).toString();
            await this.ctx.setStartEndBlock(startBlock, getBlock, {from: dev});
            const swapStartBlock = parseInt(getBlock) + 1;
            const swapEndBlock = swapStartBlock + 10;
            await this.ctx.setSwapStart(swapStartBlock, swapEndBlock, this.Final.address, {from: dev});
            await this.ctx.swapAll({from: dev});

            console.log('getBlock', getBlock, swapStartBlock, swapEndBlock);
            const tempBalanceOfDevAddr = await this.PresaleToken.balanceOf(dev);
            const finalBalanceOfDevAddr = await this.Final.balanceOf(dev);
            expect(tempBalanceOfDevAddr).to.be.bignumber.equal( new BN('0') );
            expect(finalBalanceOfDevAddr).to.be.bignumber.equal( toWei('4000') );
            console.log('User token balance: '+fromWei(finalBalanceOfDevAddr));

            getBlock = (await this.ctx.getBlock()).toString();
            await this.ctx.setSwapStart(swapStartBlock, getBlock, this.Final.address, {from: dev});
            await this.ctx.burnUnclaimed({from: dev});

            // await this.ctx.setSwapStart(quote, {from: dev});

        });
        */


    });

});
