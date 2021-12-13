
// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./libs/ITokenReferral.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// MasterChef is the master of Token. He can make Token and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once DAI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract BankV2 is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        uint256 rewardLockedUp;  // Reward locked up.
        uint256 nextHarvestUntil; // When can the user harvest again.
        uint256 lastDepositTime; // when user deposited

        //
        // We do some fancy math here. Basically, any point in time, the amount of DAI
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTokenPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;             // Address of LP token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. DAI to distribute per block.
        uint256 lastRewardBlock;    // Last block number that DAI distribution occurs.
        uint256 accTokenPerShare;   // Accumulated DAI per share, times 1e12. See below.
        uint16 depositFeeBP;        // Deposit fee in basis points
        uint256 harvestInterval;    // Harvest interval in seconds
        uint256 withdrawLockPeriod; // lock period for this pool
        uint256 balance;            // pool token balance, allow multiple pools with same token
    }

    // The DAI TOKEN!
    IBEP20 public token;
    // Dev address.
    address public devAddress;
    // Deposit Fee address
    address public feeAddress;
    // DAI tokens created per block.
    uint256 public tokenPerBlock;
    // Bonus muliplier for early token makers.
    uint256 public constant BONUS_MULTIPLIER = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DAI mining starts.
    uint256 public startBlock;
    uint256 public endBlock;
    // Total locked up rewards
    uint256 public totalLockedUpRewards;

    // Token referral contract address.
    ITokenReferral public tokenReferral;
    // Referral commission rate in basis points.
    uint16 public referralCommissionRate = 100;
    // Max referral commission rate: 10%.
    uint16 public constant MAXIMUM_REFERRAL_COMMISSION_RATE = 1000;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmissionRateUpdated(address indexed caller, uint256 previousAmount, uint256 newAmount);
    event ReferralCommissionPaid(address indexed user, address indexed referrer, uint256 commissionAmount);
    event RewardLockedUp(address indexed user, uint256 indexed pid, uint256 amountLockedUp);


    // global stats for frontend app:
    uint256 public statsRepoAdded; // how much added to the next cycle
    uint256 public statsRepoTotalAdded; // global total asset added
    uint256 public statsRepoCount; // how many repos added in the current cycle
    uint256 public statsRepoTotalCount; // total amount of repos
    uint256 public statsRestarts; // total number of restarts
    mapping(address => bool) repos;

    uint256 public treasure; // store free tokens do distribute
    uint256 public allocated; // store distributed tokens
    uint256 public blocks; // store how many blocks the cycle is
    event Mint(address to,  uint256 amount);
    uint256 public period = 300; // the period of distribution

    uint farmingEnd; // when this app go out of service
    constructor( IBEP20 _token, address _banker) public {
        farmingEnd = block.timestamp.add( 90 days );

        token = _token;
        startBlock = block.number;
        tokenPerBlock = 1 wei;
        token.balanceOf( address(this) );
        devAddress = msg.sender;
        feeAddress = msg.sender;
        repos[msg.sender] = true;
        repos[_banker] = true; // contract that deposit here (token)
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, uint256 _harvestInterval, bool _withUpdate,
        uint256 _withdrawLockPeriod ) external onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        _lpToken.balanceOf(address(this)); // prevent adding invalid token.
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accTokenPerShare: 0,
        balance: 0,
        depositFeeBP: _depositFeeBP,
        harvestInterval: _harvestInterval,
        withdrawLockPeriod: _withdrawLockPeriod
        }));
    }

    // Update the given pool's DAI allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, uint256 _harvestInterval, bool _withUpdate,
        uint256 _withdrawLockPeriod ) external onlyOwner {
        require(_depositFeeBP <= 400, "set: invalid deposit fee basis points");
        require(_withdrawLockPeriod <= 90 days, "withdraw lock must be less than 90 days");
        require(_harvestInterval <= 90 days, "set: invalid harvest interval");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        poolInfo[_pid].harvestInterval = _harvestInterval;
        poolInfo[_pid].withdrawLockPeriod = _withdrawLockPeriod;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if( treasure == 0 ){
            // if contract has no balance, stop emission.
            return 0;
        }
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending DAI on frontend.
    function pendingToken(uint256 _pid, address _user) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTokenPerShare = pool.accTokenPerShare;
        uint256 lpSupply = pool.balance;
        uint256 myBlock = (block.number <= endBlock ) ? block.number : endBlock;
        if (myBlock > pool.lastRewardBlock && lpSupply != 0 ) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, myBlock);
            uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTokenPerShare = accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        }
        uint256 pending = user.amount.mul(accTokenPerShare).div(1e12).sub(user.rewardDebt);
        return pending.add(user.rewardLockedUp);
    }

    // View function to see if user can harvest DAI.
    function canHarvest(uint256 _pid, address _user) public view returns (bool) {
        UserInfo storage user = userInfo[_pid][_user];
        return block.timestamp >= user.nextHarvestUntil;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 myBlock = (block.number <= endBlock ) ? block.number : endBlock;
        if (myBlock <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.balance;
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = myBlock;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, myBlock);
        uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        mint(address(this), tokenReward);
        pool.accTokenPerShare = pool.accTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = myBlock;
    }

    // Deposit LP tokens to MasterChef for DAI allocation.
    function deposit(uint256 _pid, uint256 _amount, address _referrer) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (_amount > 0 && address(tokenReferral) != address(0) && _referrer != address(0) && _referrer != msg.sender) {
            tokenReferral.recordReferral(msg.sender, _referrer);
        }
        payOrLockupPendingToken(_pid);
        if (_amount > 0) {

            uint256 oldBalance = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 newBalance = pool.lpToken.balanceOf(address(this));
            _amount = newBalance.sub(oldBalance);

            pool.balance = pool.balance.add(_amount);

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
            user.lastDepositTime = block.timestamp;
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
        forward();
    }

    bool allowWithdraw = false;
    function setAllowWithdraw( bool status ) public onlyOwner{
        allowWithdraw = status;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        require(allowWithdraw,"!allowWithdraw");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        payOrLockupPendingToken(_pid);
        if (_amount > 0) {
            // check withdraw is locked:
            if( pool.withdrawLockPeriod > 0){
                bool isLocked = block.timestamp < user.lastDepositTime + pool.withdrawLockPeriod;
                require( isLocked == false, "withdraw still locked" );
            }
            user.amount = user.amount.sub(_amount);
            pool.balance = pool.balance.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accTokenPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }
    bool allowEmergencyWithdraw = false;
    function setAllowEmergencyWithdraw( bool status ) public onlyOwner{
        allowEmergencyWithdraw = status;
    }
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        require(allowEmergencyWithdraw,"!allowEmergencyWithdraw");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        pool.balance = pool.balance.sub(amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardLockedUp = 0;
        user.nextHarvestUntil = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Pay or lockup pending DAI.
    function payOrLockupPendingToken(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.nextHarvestUntil == 0) {
            user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);
        }

        uint256 pending = user.amount.mul(pool.accTokenPerShare).div(1e12).sub(user.rewardDebt);
        if (canHarvest(_pid, msg.sender)) {
            if (pending > 0 || user.rewardLockedUp > 0) {
                uint256 totalRewards = pending.add(user.rewardLockedUp);

                // reset lockup
                totalLockedUpRewards = totalLockedUpRewards.sub(user.rewardLockedUp);
                user.rewardLockedUp = 0;
                user.nextHarvestUntil = block.timestamp.add(pool.harvestInterval);

                // send rewards
                safeTokenTransfer(msg.sender, totalRewards);
                payReferralCommission(msg.sender, totalRewards);
            }
        } else if (pending > 0) {
            user.rewardLockedUp = user.rewardLockedUp.add(pending);
            totalLockedUpRewards = totalLockedUpRewards.add(pending);
            emit RewardLockedUp(msg.sender, _pid, pending);
        }
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external {
        require(msg.sender == devAddress, "setDevAddress: FORBIDDEN");
        require(_devAddress != address(0), "setDevAddress: ZERO");
        devAddress = _devAddress;
    }

    function setFeeAddress(address _feeAddress) external {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "setFeeAddress: ZERO");
        feeAddress = _feeAddress;
    }

    // Update the token referral contract address by the owner
    function setTokenReferral(ITokenReferral _tokenReferral) external onlyOwner {
        tokenReferral = _tokenReferral;
    }

    // Update referral commission rate by the owner
    function setReferralCommissionRate(uint16 _referralCommissionRate) external onlyOwner {
        require(_referralCommissionRate <= MAXIMUM_REFERRAL_COMMISSION_RATE, "setReferralCommissionRate: invalid referral commission rate basis points");
        referralCommissionRate = _referralCommissionRate;
    }

    // Pay referral commission to the referrer who referred this user.
    function payReferralCommission(address _user, uint256 _pending) internal {
        if (address(tokenReferral) != address(0) && referralCommissionRate > 0) {
            address referrer = tokenReferral.getReferrer(_user);
            uint256 commissionAmount = _pending.mul(referralCommissionRate).div(10000);

            if (referrer != address(0) && commissionAmount > 0) {
                mint(referrer, commissionAmount);
                tokenReferral.recordReferralCommission(referrer, commissionAmount);
                emit ReferralCommissionPaid(_user, referrer, commissionAmount);
            }
        }
    }


    function mint(address to,  uint256 amount ) internal {
        if( amount > treasure ){
            // treasure is 0, stop emission.
            tokenPerBlock = 0;
            amount = treasure; // last ming
        }
        treasure = treasure.sub(amount);
        allocated = allocated.add(amount);
        emit Mint(to, amount);
    }
    // Safe token transfer function, just in case if rounding error causes pool to not have enough DAI.
    function safeTokenTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        if (_amount > tokenBal) {
            token.transfer(_to, tokenBal);
        } else {
            token.transfer(_to, _amount);
        }
    }

    function getBlock() public view returns (uint256) {
        return block.number;
    }


    function setPeriod(uint256 _period) public onlyOwner{
        period = _period;
    }

    modifier onlyRepo() {
        require(repos[msg.sender], "minter: caller is not a minter");
        _;
    }
    function setRepoManager(address addr, bool status) public onlyOwner{
        repos[msg.sender] = status;
    }
    function addBalance(uint256 _amount) external onlyOwner {
        require( _amount > 0 , "err _amount=0");
        token.safeTransferFrom(msg.sender, address(this), _amount);
        statsRepoAdded += _amount;
        statsRepoTotalAdded += _amount;
        statsRepoCount++;
        statsRepoTotalCount++;
        restart();
    }
    function addRepo(uint256 amount) public onlyRepo{
        statsRepoAdded += amount;
        statsRepoTotalAdded += amount;
        statsRepoCount++;
        statsRepoTotalCount++;
        forward();
    }
    function forward() public {
        if( block.number > endBlock ) restart();
    }
    function restart() internal{
        endBlock = block.number.add(period);
        treasure += statsRepoAdded;
        startBlock = block.number;
        if( treasure == 0 || period == 0 ){
            return;
        }
        blocks = endBlock.sub(block.number);
        if( blocks > 0 )
            tokenPerBlock = treasure.div(blocks);
        else
            tokenPerBlock = 0;
        statsRepoAdded = 0;
        statsRepoCount = 0;
        statsRestarts++;
    }

    function recoverTreasure( IBEP20 recoverToken, uint256 amount) external onlyOwner{
        require(block.timestamp > farmingEnd, "can recover only after farming end.");
        recoverToken.transfer(devAddress, amount);
    }
}
