// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./libs/ReentrancyGuard.sol";

import "./libs/Ownable.sol";

import "./libs/SafeMath.sol";

import "./libs/SafeERC20.sol";

import "./Token.sol";

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// MasterChef is the master of Apollo. He can make Apollo and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Apollo is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
// European boys play fair, don't worry.

contract MasterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of IRIS
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accApolloPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accApolloPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. IRISes to distribute per block.
        uint256 lastRewardBlock;  // Last block number that IRISes distribution occurs.
        uint256 accApolloPerShare;   // Accumulated IRISes per share, times 1e18. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint256 lpSupply;
    }

    // The IRIS TOKEN!
    Plutus public token;
    IERC721 public nft;
    address public devAddress;
    address public feeAddress;
    uint256 max_token_supply = 1_500_000 ether;

    // IRIS tokens created per block.
    uint256 public tokenPerBlock = 4.1 ether;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when IRIS mining starts.
    uint256 public startBlock;

    uint256 public constant MAXIMUM_EMISSION_RATE = 5 ether;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 tokenPerBlock);
    event PoolAdd(address indexed user, IERC20 lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint16 depositFeeBP);
    event PoolSet(address indexed user, IERC20 lpToken, uint256 allocPoint, uint256 lastRewardBlock, uint16 depositFeeBP);
    event UpdateStartBlock(address indexed user, uint256 startBlock);
    constructor(
        address _token,
        uint256 _startBlock,
        address _devAddress,
        address _feeAddress,
        address _nft
    ) public {
        token = Plutus(_token);
        nft = IERC721(_nft);
        startBlock = _startBlock;

        devAddress = _devAddress;
        feeAddress = _feeAddress;
        token.balanceOf(address(this));

    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP) external onlyOwner nonDuplicated(_lpToken) {
        _lpToken.balanceOf(address(this));
        require(_depositFeeBP <= 500, "add: invalid deposit fee basis points");
        _lpToken.balanceOf(address(this));
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardBlock : lastRewardBlock,
        accApolloPerShare : 0,
        depositFeeBP : _depositFeeBP,
        lpSupply : 0
        }));
        emit PoolAdd(msg.sender, _lpToken, _allocPoint, lastRewardBlock, _depositFeeBP);
    }

    // Update the given pool's IRIS allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP) external onlyOwner {
        require(_depositFeeBP <= 500, "set: invalid deposit fee basis points");
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
        emit PoolSet(msg.sender, poolInfo[_pid].lpToken, _allocPoint, poolInfo[_pid].lastRewardBlock, _depositFeeBP);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (token.totalSupply() >= max_token_supply) return 0;

        return _to.sub(_from);
    }

    // View function to see pending IRISes on frontend.
    function pendingApollo(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accApolloPerShare = pool.accApolloPerShare;
        if (block.number > pool.lastRewardBlock && pool.lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accApolloPerShare = accApolloPerShare.add(tokenReward.mul(1e18).div(pool.lpSupply));
        }
        return user.amount.mul(accApolloPerShare).div(1e18).sub(user.rewardDebt);
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
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(tokenPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        if (token.totalSupply().add(tokenReward.mul(105).div(100)) <= max_token_supply) {
            token.mint(address(this), tokenReward);
        } else if (token.totalSupply() < max_token_supply) {
            token.mint(address(this), max_token_supply.sub(token.totalSupply()));
        }
        pool.accApolloPerShare = pool.accApolloPerShare.add(tokenReward.mul(1e18).div(pool.lpSupply));
        pool.lastRewardBlock = block.number;
    }

    event Bonus(address to, uint256 multiplier, uint256 bonus);
    // Deposit LP tokens to MasterChef for IRIS allocation.
    function deposit(uint256 _pid, uint256 _amount) nonReentrant external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accApolloPerShare).div(1e18).sub(user.rewardDebt);

            // add additional % bonus
            uint256 multiplier = calculateBonus(msg.sender);
            if (multiplier > 0 && pending > 0) {
                uint256 bonus = pending.mul(multiplier).div(1000);
                emit Bonus(msg.sender, multiplier, bonus);
                token.mint(address(this), bonus);
                pending = pending.add(bonus);
            }

            if (pending > 0) {
                safeApolloTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);
            require(_amount > 0, "we dont accept deposits of 0");
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
                pool.lpSupply = pool.lpSupply.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
                pool.lpSupply = pool.lpSupply.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accApolloPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) nonReentrant external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accApolloPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            // add additional % bonus
            uint256 multiplier = calculateBonus(msg.sender);
            if (multiplier > 0 && pending > 0) {
                uint256 bonus = pending.mul(multiplier).div(1000);
                emit Bonus(msg.sender, multiplier, bonus);
                token.mint(address(this), bonus);
                pending = pending.add(bonus);
            }

            safeApolloTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            pool.lpSupply = pool.lpSupply.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accApolloPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) nonReentrant external {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        pool.lpSupply = pool.lpSupply.sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    event ApolloTransfer(address to, uint256 requested, uint256 amount);
    // Safe token transfer function, just in case if rounding error causes pool to not have enough IRIS.
    function safeApolloTransfer(address _to, uint256 _amount) internal {
        uint256 tokenBal = token.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > tokenBal) {
            transferSuccess = token.transfer(_to, tokenBal);
            emit ApolloTransfer(_to, _amount, tokenBal);
        } else {
            transferSuccess = token.transfer(_to, _amount);
        }
        require(transferSuccess, "safeApolloTransfer: Transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external onlyOwner {
        require(_devAddress != address(0), "!nonzero");
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "!nonzero");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function updateEmissionRate(uint256 _tokenPerBlock) external onlyOwner {
        require(_tokenPerBlock <= MAXIMUM_EMISSION_RATE, "Too High");
        massUpdatePools();
        tokenPerBlock = _tokenPerBlock;
        emit UpdateEmissionRate(msg.sender, _tokenPerBlock);
    }

    // Only update before start of farm
    function updateStartBlock(uint256 _startBlock) onlyOwner external {
        require(startBlock > block.number, "Farm already started");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardBlock = _startBlock;
        }
        startBlock = _startBlock;
        emit UpdateStartBlock(msg.sender, _startBlock);
    }


    uint256 public minNftToBoost = 5;
    uint256 public nftBoost = 50; // 5%
    function setMinNftBoost(uint256 _minNftToBoost) external onlyOwner {
        minNftToBoost = _minNftToBoost;
    }

    function setNftBoost(uint256 _nftBoost) external onlyOwner {
        nftBoost = _nftBoost;
    }
    function setNftContract(address _nft) external onlyOwner {
        nft = IERC721(_nft);
        nft.balanceOf(address(this));
    }

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    address public constant NULL_ADDRESS = 0x0000000000000000000000000000000000000000;
    function isNftHolder(address _address) public view returns (bool) {
        if( address(nft) == NULL_ADDRESS) return false;
        return nft.balanceOf(_address) >= minNftToBoost;
    }

    uint256 public constant BONUS_MULTIPLIER = 0;

    function calculateBonus(address _user) public view returns (uint256) {
        uint256 _isNftHolder = 0;
        if (isNftHolder(_user)) {
            _isNftHolder = nftBoost;
        }
        uint totalReward = _isNftHolder;
        return BONUS_MULTIPLIER.add(totalReward);
    }

    modifier onlyOperator() {
        require(devAddress == msg.sender, "caller is not dev");
        _;
    }
    function setRewardTo4() external onlyOperator {
        tokenPerBlock = 4 ether;
    }
    function setRewardTo04() external onlyOperator {
        tokenPerBlock = 0.4 ether;
    }
    function setRewardTo05() external onlyOperator {
        tokenPerBlock = 0.5 ether;
    }
    function setRewardTo06() external onlyOperator {
        tokenPerBlock = 0.6 ether;
    }
    function setMaxSupply(uint256 val) external onlyOperator {
        require(max_token_supply > val, "wrong new emission");
        max_token_supply = val;
    }

}
