// SPDX-License-Identifier: UNLICENSED
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import './libs/AddrArrayLib.sol';
pragma solidity ^0.6.12;

contract Bank2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using AddrArrayLib for AddrArrayLib.Addresses;
    mapping(uint256 => AddrArrayLib.Addresses) private addressByPid;
    struct UserInfo {
        uint amount;
        uint rewardDebt;//dai debt
        uint lastwithdraw;
        uint[] pids;
    }

    struct PoolInfo {
        uint initamt;
        uint amount;
        uint startTime;
        uint endTime;
        uint tokenPerSec;//X10^18
        uint accPerShare;
        IBEP20 token;
        uint lastRewardTime;
        address router;
        bool disableCompound;//in case of error
    }

    struct UserPInfo {
        uint rewardDebt;
    }

    struct stablePool {
        //daiPerSec everyweek
        uint idx;
        uint[] wkUnit; //weekly daiPerSec. 4week cycle
        uint daiPerTime;//*1e18
        uint startTime;
        uint accIronPerShare;
        uint lastRewardTime;
    }

    /**Variables */

    mapping(address => UserInfo) public userInfo;
    PoolInfo[] public poolInfo;
    mapping(uint => bool) public skipPool;//in case of stuck in one token.
    mapping(uint => mapping(address => UserPInfo)) public userPInfo;
    address[] public lotlist;
    uint public lotstart = 1;
    stablePool public wonePool;
    IBEP20 public PLUTUS = IBEP20(0xe5dFCd29dFAC218C777389E26F1060E0D0Fe856B);
    IBEP20 public DAI = IBEP20(0xEf977d2f931C1978Db5F6747666fa1eACB0d0339); // DAI
    IBEP20 public wone = IBEP20(0xcF664087a5bB0237a0BAd6742852ec6c8d69A27a); // WMATIC
    address public router = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;  // RT
    address public devaddr;
    address public winner;
    address public lotwinner;
    uint public winnum;
    uint public totalAmount;
    uint public newRepo;
    uint public currentRepo;
    uint public period;
    uint public endtime;
    uint public totalpayout;
    uint public lastpayout;
    uint public entryMin = 1 ether; //min PLUTUS to enroll lotterypot
    uint public lotsize;
    uint public lotrate = 200;//bp of total prize.
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    uint public totalBurnt;
    bool public paused;
    bool public partnerReward = true;
    mapping(address => bool) public approvedContracts;
    modifier onlyApprovedContractOrEOA() {
        require(
            tx.origin == msg.sender || approvedContracts[msg.sender],
            "onlyApprovedContractOrEOA"
        );
        _;
    }

    // use for testing only

    constructor(address _lp, address _busd, address _wone, address _router) public {
        PLUTUS = IBEP20(_lp);
        router = _router;
        DAI = IBEP20(_busd);
        wone = IBEP20(_wone);
        paused = false;
        wonePool.wkUnit = [0, 0, 0, 0];
        devaddr = address(msg.sender);
        wone.approve(router, uint(- 1));
        DAI.approve(router, uint(- 1));
        lotlist.push(burnAddress);
    }


    // mainnet
/*
    constructor() public {
        paused = false;
        wonePool.wkUnit = [0, 0, 0, 0];
        devaddr = address(msg.sender);
        wone.approve(router, uint(- 1));
        DAI.approve(router, uint(- 1));
        lotlist.push(burnAddress);
    }
*/

    modifier ispaused(){
        require(paused == false, "paused");
        _;
    }

    /**View functions  */
    function userinfo(address _user) public view returns
    (uint amount, uint rewardDebt, uint lastwithdraw, uint[] memory pids ){
        return (userInfo[_user].amount, userInfo[_user].rewardDebt,
        userInfo[_user].lastwithdraw, userInfo[_user].pids);
    }

    function daiinfo() public view returns (
        uint idx, uint[] memory wkUnit, uint daiPerTime,
        uint startTime, uint accIronPerShare, uint lastRewardTime
    ){
        return (wonePool.idx, wonePool.wkUnit, wonePool.daiPerTime,
        wonePool.startTime, wonePool.accIronPerShare, wonePool.lastRewardTime);
    }

    function poolLength() public view returns (uint){
        return poolInfo.length;
    }

    function getTime() public view returns (uint256){
        return block.timestamp;
    }

    function livepoolIndex() public view returns (uint[] memory, uint){
        uint[] memory index = new uint[](poolInfo.length);
        uint cnt;
        for (uint i = 0; i < poolInfo.length; i++) {
            if (poolInfo[i].endTime > block.timestamp) {
                index[cnt++] = i;
            }
        }
        return (index, cnt);
    }

    function pendingReward(uint _pid, address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        PoolInfo storage pool = poolInfo[_pid];
        UserPInfo storage userP = userPInfo[_pid][_user];
        uint256 _accIronPerShare = pool.accPerShare;
        if (block.timestamp <= pool.startTime) {
            return 0;
        }
        if (block.timestamp > pool.lastRewardTime && pool.amount != 0) {
            uint multiplier;
            if (block.timestamp > pool.endTime) {
                multiplier = pool.endTime.sub(pool.lastRewardTime);
            } else {
                multiplier = block.timestamp.sub(pool.lastRewardTime);
            }
            uint256 Reward = multiplier.mul(pool.tokenPerSec);
            _accIronPerShare = _accIronPerShare.add(Reward.mul(1e12).div(pool.amount));
        }
        return user.amount.mul(_accIronPerShare).div(1e12).sub(userP.rewardDebt).div(1e18);
    }

    function pendingrewards(address _user) public view returns (uint[] memory){
        uint[] memory pids = userInfo[_user].pids;
        uint[] memory rewards = new uint[](pids.length);
        for (uint i = 0; i < pids.length; i++) {
            rewards[i] = pendingReward(pids[i], _user);
        }
        return rewards;
    }

    function mytickets(address _user) public view returns (uint[] memory){
        uint[] memory my = new uint[](lotlist.length - lotstart);
        uint count;
        for (uint i = lotstart; i < lotlist.length; i++) {
            if (lotlist[i] == _user) {
                my[count++] = i;
            }
        }
        return my;
    }

    function totalticket() public view returns (uint){
        return lotlist.length - lotstart;
    }

    function getTimestamp() public view returns (uint){
        return block.timestamp;
    }

    function pendingDAI(address _user) public view returns (uint256){
        UserInfo storage user = userInfo[_user];
        uint256 _accIronPerShare = wonePool.accIronPerShare;
        if (block.timestamp > wonePool.lastRewardTime && totalAmount != 0) {
            uint256 multiplier = block.timestamp.sub(wonePool.lastRewardTime);
            uint256 IronReward = multiplier.mul(wonePool.daiPerTime);
            _accIronPerShare = _accIronPerShare.add(IronReward.mul(1e12).div(totalAmount));
        }
        return user.amount.mul(_accIronPerShare).div(1e12).sub(user.rewardDebt).div(1e18);
    }

    /**Public functions */

    function updatestablePool() internal {
        if (block.timestamp <= wonePool.lastRewardTime) {
            return;
        }
        if (totalAmount == 0) {
            wonePool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = block.timestamp.sub(wonePool.lastRewardTime);
        uint256 daiReward = multiplier.mul(wonePool.daiPerTime);
        wonePool.accIronPerShare = wonePool.accIronPerShare.add(daiReward.mul(1e12).div(totalAmount));
        wonePool.lastRewardTime = block.timestamp;
    }

    function updatePool(uint _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.lastRewardTime >= pool.endTime || block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (totalAmount == 0 || pool.amount == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint multiplier;
        if (block.timestamp > pool.endTime) {
            multiplier = pool.endTime.sub(pool.lastRewardTime);
        } else {
            multiplier = block.timestamp.sub(pool.lastRewardTime);
        }
        uint256 Reward = multiplier.mul(pool.tokenPerSec);
        pool.accPerShare = pool.accPerShare.add(Reward.mul(1e12).div(pool.amount));

        pool.lastRewardTime = block.timestamp;
        if (block.timestamp > pool.endTime) {
            pool.lastRewardTime = pool.endTime;
        }
    }

    function deposit(uint256 _amount) public onlyApprovedContractOrEOA ispaused {
        UserInfo storage user = userInfo[msg.sender];
        updatestablePool();
        for (uint i = 0; i < user.pids.length; i++) {
            uint _pid = user.pids[i];
            if (skipPool[_pid]) {continue;}
            updatePool(_pid);
            uint pendingR = user.amount.mul(poolInfo[_pid].accPerShare).div(1e12).sub(userPInfo[_pid][msg.sender].rewardDebt);
            if( ! partnerReward ) pendingR = pendingR.div(1e18);
            if (pendingR > 0) {
                poolInfo[_pid].token.safeTransfer(msg.sender, pendingR);
            }
        }
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(wonePool.accIronPerShare).div(1e12).sub(user.rewardDebt);
            pending = pending.div(1e18);
            if (pending > 0) {
                safeIronTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint before = PLUTUS.balanceOf(address(this));
            PLUTUS.safeTransferFrom(address(msg.sender), address(this), _amount);
            PLUTUS.safeTransfer(burnAddress, PLUTUS.balanceOf(address(this)).sub(before));
            user.amount = user.amount.add(_amount);
            totalBurnt += _amount;
            totalAmount = totalAmount.add(_amount);
        }

        for (uint i = 0; i < user.pids.length; i++) {
            uint _pid = user.pids[i];
            if (skipPool[_pid]) {continue;}
            poolInfo[_pid].amount += _amount;
            userPInfo[_pid][msg.sender].rewardDebt = user.amount.mul(poolInfo[_pid].accPerShare).div(1e12);
        }
        user.rewardDebt = user.amount.mul(wonePool.accIronPerShare).div(1e12);
        checkend();
    }

    function enroll(uint _pid) public onlyApprovedContractOrEOA {
        require(_pid < poolInfo.length, "wrong pid");
        require(poolInfo[_pid].endTime > block.timestamp, "time already passed");
        require(skipPool[_pid] == false, "skip pool");
        UserInfo storage user = userInfo[msg.sender];
        for (uint i = 0; i < user.pids.length; i++) {
            require(user.pids[i] != _pid, "duplicated pid");
        }
        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        pool.amount += user.amount;
        user.pids.push(_pid);
        userPInfo[_pid][msg.sender].rewardDebt = user.amount.mul(poolInfo[_pid].accPerShare).div(1e12);
    }



    /**Internal functions */



    function deletepids() internal {
        UserInfo storage user = userInfo[msg.sender];
        for (uint i = 0; i < user.pids.length; i++) {
            if (poolInfo[user.pids[i]].endTime <= block.timestamp) {
                user.pids[i] = user.pids[user.pids.length - 1];
                user.pids.pop();
                deletepids();
                break;
            }
        }
    }



    function _safeSwap(
        address _router,
        uint256 _amountIn,
        address token0, address token1
    ) internal {
        uint bal = IBEP20(token0).balanceOf(address(this));
        if (_amountIn < bal) {
            bal = _amountIn;
        }
        if (bal > 0) {
            address[] memory _path = new address[](2);
            _path[0] = token0;
            _path[1] = token1;
            IUniswapV2Router02(_router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                bal,
                0,
                _path,
                address(this),
                now.add(600)
            );
        }
    }

    function safeIronTransfer(address _to, uint256 _amount) internal {
        uint256 balance = DAI.balanceOf(address(this));
        if (_amount > balance) {
            lastpayout = balance;
            DAI.safeTransfer(_to, balance);
            totalpayout = totalpayout.add(balance);
        } else {
            DAI.safeTransfer(_to, _amount);
            totalpayout = totalpayout.add(_amount);
            lastpayout = _amount;
        }
    }

    /*governance functions*/

    function addpool(uint _amount, uint _startTime, uint _endTime, IBEP20 _token, address _router) public onlyOwner {
        require(_startTime > block.timestamp && _endTime > _startTime, "wrong time");
        poolInfo.push(PoolInfo({
        initamt : _amount,
        amount : 0,
        startTime : _startTime,
        endTime : _endTime,
        tokenPerSec : _amount.mul(1e18).div(_endTime - _startTime), //X10^18
        accPerShare : 0,
        token : _token,
        lastRewardTime : _startTime,
        router : _router,
        disableCompound : false//in case of error
        }));
        _token.approve(_router, uint(- 1));
    }

    function setPrize(uint256 _lotrate) public onlyOwner {
        lotrate = _lotrate;
        //toggle
    }
    function stopPool(uint _pid) public onlyOwner {
        skipPool[_pid] = !skipPool[_pid];
        //toggle
    }

    function allowPartnerReward(bool _partnerReward) public onlyOwner {
        partnerReward = _partnerReward;
    }


    function pause(bool _paused) public onlyOwner {
        paused = _paused;
    }

    function setPeriod(uint _period) public onlyOwner {
        period = _period;
    }

    function setMin(uint _entryMin) public onlyOwner {
        entryMin = _entryMin;
    }

    function disableCompound(uint _pid, bool _disable) public onlyOwner {
        poolInfo[_pid].disableCompound = _disable;
    }

    function setApprovedContract(address _contract, bool _status)
    external
    onlyOwner
    {
        approvedContracts[_contract] = _status;
    }

    function pickwin() internal {
        if( lotlist.length <= 2 ){
            // only if there is tickets or contract fail with revert.
            return;
        }
        uint _mod = lotlist.length - lotstart;
        bytes32 _structHash;
        uint256 _randomNumber;
        _structHash = keccak256(abi.encode(msg.sender, block.difficulty, gasleft()));
        _randomNumber = uint256(_structHash);
        assembly {_randomNumber := mod(_randomNumber, _mod)}
        winnum = lotstart + _randomNumber;
        lotwinner = lotlist[winnum];
        safeIronTransfer(lotwinner, lotsize);
        lotsize = 0;
        lotstart += _mod;


        uint myBalance = DAI.balanceOf(address(this));
        if( myBalance > 0 ){
            newRepo = myBalance;
            lotsize = myBalance;
            start(period);
        }

    }

    function checkend() internal {//already updated pool above.
        deletepids();
        if (endtime <= block.timestamp) {
            endtime = block.timestamp.add(period);
            uint256 bonus = 10 ** 19;
            if (newRepo > bonus) {//BUSD decimal 18 in bsc. should change on other chains.
                safeIronTransfer(msg.sender, bonus);
                //reward for the first resetter
                newRepo = newRepo.sub(bonus);
            }
            winner = address(msg.sender);
            currentRepo = newRepo.mul(999).div(1000);
            //in case of error by over-paying
            newRepo = 0;
            if (wonePool.idx == 3) {
                wonePool.daiPerTime -= wonePool.wkUnit[0];
                wonePool.idx = 0;
                wonePool.wkUnit[0] = currentRepo.mul(1e18).div(period * 4);
                wonePool.daiPerTime += wonePool.wkUnit[0];
            } else {
                uint idx = wonePool.idx;
                wonePool.daiPerTime = wonePool.daiPerTime.sub(wonePool.wkUnit[idx + 1]);
                wonePool.idx++;
                wonePool.wkUnit[wonePool.idx] = currentRepo.mul(1e18).div(period * 4);
                wonePool.daiPerTime += wonePool.wkUnit[wonePool.idx];
            }
            //pickwin();
        }
    }

    function compound() public onlyApprovedContractOrEOA returns (uint){
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount > 0, "amount=0");
        updatestablePool();
        uint before = wone.balanceOf(address(this));
        for (uint i = 0; i < user.pids.length; i++) {
            uint _pid = user.pids[i];
            if (skipPool[_pid]) {continue;}
            updatePool(_pid);
            PoolInfo memory pool = poolInfo[_pid];
            uint pendingR = user.amount.mul(pool.accPerShare).div(1e12).sub(userPInfo[_pid][msg.sender].rewardDebt);
            pendingR = pendingR.div(1e18);
            if (pool.disableCompound) {
                if (pendingR > 0) {
                    pool.token.safeTransfer(msg.sender, pendingR);
                }
            } else {
                _safeSwap(pool.router, pendingR, address(pool.token), address(wone));
            }
        }

        uint beforeSing = PLUTUS.balanceOf(address(this));
        //wone=>PLUTUS
        _safeSwap(router, wone.balanceOf(address(this)).sub(before), address(wone), address(PLUTUS));

        //DAI=>PLUTUS
        uint256 pending = user.amount.mul(wonePool.accIronPerShare).div(1e12).sub(user.rewardDebt);
        pending = pending.div(1e18);
        _safeSwap(router, pending, address(DAI), address(PLUTUS));
        uint burningPlutus = PLUTUS.balanceOf(address(this)).sub(beforeSing);
        user.amount += burningPlutus.mul(105).div(100);
        user.rewardDebt = user.amount.mul(wonePool.accIronPerShare).div(1e12);
        for (uint i = 0; i < user.pids.length; i++) {
            uint _pid = user.pids[i];
            if (skipPool[_pid]) {continue;}
            poolInfo[_pid].amount += burningPlutus.mul(105).div(100);
            userPInfo[_pid][msg.sender].rewardDebt = user.amount.mul(poolInfo[_pid].accPerShare).div(1e12);
        }
        PLUTUS.transfer(burnAddress, burningPlutus);
        totalBurnt += burningPlutus;
        totalAmount += burningPlutus.mul(105).div(100);

        if (burningPlutus > entryMin) {//enroll for lottery
            lotlist.push(msg.sender);
        }
        checkend();
        return burningPlutus;
    }

    function start(uint _period) public onlyOwner {
        paused = false;
        period = _period;
        endtime = block.timestamp.add(period);
        currentRepo = newRepo;
        wonePool.daiPerTime = currentRepo.mul(1e18).div(period * 4);
        wonePool.wkUnit[0] = wonePool.daiPerTime;
        newRepo = 0;
    }
    function addManualRepo(uint _amount) public {
        DAI.safeTransferFrom(msg.sender, address(this), _amount);
        addRepo(_amount);
    }
    function addRepo(uint _amount) public {
        require(msg.sender == address(PLUTUS) || msg.sender == owner() || msg.sender == devaddr, "not authorized to repo");
        // uint _lotadd = _amount.mul(lotrate).div(10000);
        lotsize = lotsize.add(_amount);
        newRepo = newRepo.add(_amount);
        // newRepo = newRepo.add(_amount.sub(_lotadd));
    }
}
