// https://www.plutusdefi.io/

import "./libs/ReentrancyGuard.sol";

import "./libs/Ownable.sol";

import "./libs/SafeMath.sol";

import "./libs/SafeERC20.sol";

import "./libs/IERC20.sol";

pragma solidity ^0.6.12;

// TokenToken
contract PlutusPreSale is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IERC20 tmpToken;
    IERC20 DAI; // 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    IERC20 finalToken;
    address public feeAddress = 0x80956dCf2a4302176B0cE0c0b4fCE71081b1d6A7;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 public pPLUTUSPrice;

    uint256 public maxTokenPurchase = 4000 ether;
    uint256 public maxTokenPurchaseForWL1 = 1000 ether;
    uint256 public maxTokenPurchaseForWL2 = 1000 ether;

    uint256 public startBlock;
    uint256 public endBlock;

    uint256 public swapStartBlock = 0; // swap start disabled
    uint256 public swapEndBlock = 0;

    mapping(address => bool) public userIsWL1;
    mapping(address => bool) public userIsWL2;
    mapping(address => uint256) public userTokenTally;

    event tokenPurchased(address sender, uint256 tokenReceived, uint256 DAISpent);
    event startBlockChanged(uint256 newStartBlock, uint256 newEndBlock);
    event Swap(address sender, uint256 swapAmount);

    constructor(uint256 _startBlock, uint256 _endBlock,
        uint256 _pPLUTUSPrice, address _tmpToken, address _DAI) public {
        startBlock = _startBlock;
        endBlock   = _endBlock;
        pPLUTUSPrice = _pPLUTUSPrice;
        tmpToken = IERC20(_tmpToken);
        DAI = IERC20(_DAI);
        tmpToken.balanceOf(address(this));
        DAI.balanceOf(address(this));
    }

    // return the last block for testing
    function getBlock() public view returns(uint256){
        return block.number;
    }

    // pass any pPlutus and receive the amount in DAI.
    function quoteAmountInPPlutus(uint256 amount) public view returns(uint256){
        return amount.div(1e18).mul(pPLUTUSPrice);
    }
    // pass any pPlutus and get the % amount in DAI
    function quoteAmountInDAI(uint256 amount) public view returns(uint256){
        return quoteAmountInPPlutus(amount);
    }
    function quoteAmounts(uint256 requestedAmount, address user) public view
    returns(uint256 pPlutusInDAI, uint256 inDAI, uint256 limit, uint256 tokenPurchaseAmount){
        (tokenPurchaseAmount, limit) = getUserLimit(requestedAmount, user);
        pPlutusInDAI = quoteAmountInPPlutus(tokenPurchaseAmount);
        inDAI = quoteAmountInDAI(tokenPurchaseAmount);
    }
    function getUserLimit(uint256 tokenPurchaseAmount, address user) public view returns(uint256, uint256){
        uint256 limit = maxTokenPurchase;
        if(userIsWL1[user])
            limit = limit.add(maxTokenPurchaseForWL1);
        if(userIsWL2[user])
            limit = limit.add(maxTokenPurchaseForWL2);

        if (tokenPurchaseAmount > limit)
            tokenPurchaseAmount = limit;

        if (userTokenTally[user].add(tokenPurchaseAmount) > limit)
            tokenPurchaseAmount = maxTokenPurchase.sub(userTokenTally[user]);

        // if we dont have enough left, give them the rest.
        if (tmpToken.balanceOf(address(this)) < tokenPurchaseAmount)
            tokenPurchaseAmount = tmpToken.balanceOf(address(this));

        return (tokenPurchaseAmount, limit);
    }
    function buy( uint256 amount ) external payable nonReentrant {

        require(block.number >= startBlock, "presale hasn't started yet, good things come to those that wait");
        require(block.number < endBlock, "presale has ended, come back next time!");
        require(tmpToken.balanceOf(address(this)) > 0, "No more Token left! Come back next time!");

        (uint256 pPlutusInDAI, uint256 inDAI, uint256 limit, uint256 tokenPurchaseAmount) =
            quoteAmounts(amount, msg.sender);
        require(userTokenTally[msg.sender] < limit, "user has already purchased too much Token");
        require(tokenPurchaseAmount > 0, "user cannot purchase 0 Token");
        require(inDAI > 0, "user cannot pay 0 DAI");

        userTokenTally[msg.sender] = userTokenTally[msg.sender].add(tokenPurchaseAmount);
        uint256 userDAIBalance = DAI.balanceOf(address(msg.sender));
        require(inDAI <= userDAIBalance, "DAI balance is too low");
        DAI.safeTransferFrom(msg.sender, feeAddress, inDAI);
        tmpToken.safeTransfer(msg.sender, tokenPurchaseAmount);

        emit tokenPurchased(msg.sender, tokenPurchaseAmount, inDAI);

    }

    function setStartEndBlock(uint256 _startBlock, uint256 _endBlock) external onlyOwner {
        startBlock = _startBlock;
        endBlock   = _endBlock;
    }
    function setpPLUTUSPrice(uint256 _pPLUTUSPrice) external onlyOwner {
        pPLUTUSPrice = _pPLUTUSPrice;
    }
    function setMaxTokenPurchase(uint256 _maxTokenPurchase) external onlyOwner {
        maxTokenPurchase = _maxTokenPurchase;
    }
    function setMaxTokenPurchasePantheon(uint256 _value) external onlyOwner {
        maxTokenPurchaseForWL1 = _value;
    }
    function setMaxTokenPurchaseHeroes(uint256 _value) external onlyOwner {
        maxTokenPurchaseForWL2 = _value;
    }
    function setFeeAddress(address _feeAddress) external onlyOwner {
        feeAddress = _feeAddress;
    }
    function setToken(address _token) external onlyOwner {
        tmpToken = IERC20(_token);
        tmpToken.balanceOf(address(this));
    }
    function setDAIContract(address _DAI) external onlyOwner {
        DAI = IERC20(_DAI);
        DAI.balanceOf(address(this));
    }
    function setUserIsWL1(address _user, bool _status) external onlyOwner {
        userIsWL1[_user] = _status;
    }
    function setUserIsWL2(address _user, bool _status) external onlyOwner {
        userIsWL2[_user] = _status;
    }

    function setSwapStart(uint256 _startBlock, uint256 _endBlock, address _token) external onlyOwner {
        swapStartBlock = _startBlock;
        swapEndBlock   = _endBlock;
        finalToken = IERC20(_token);
        finalToken.balanceOf(address(this));
        require( swapStartBlock > endBlock, "swap should start after token sell." );
        require( swapEndBlock > endBlock, "swap should end after token sell." );
        require( swapEndBlock > swapStartBlock, "start should > end." );
    }
    function burnUnclaimed() external onlyOwner {
        require(block.number > swapEndBlock && swapEndBlock > 0,
            "can only send excess to dead address after swap has ended");
        if (tmpToken.balanceOf(address(this)) > 0)
            tmpToken.safeTransfer(burnAddress, tmpToken.balanceOf(address(this)) );
        if (finalToken.balanceOf(address(this)) > 0)
            finalToken.safeTransfer(burnAddress, finalToken.balanceOf(address(this)) );
    }

    function swapAll() external nonReentrant {
        _swap( tmpToken.balanceOf(msg.sender) );
    }
    function swap(uint256 swapAmount) external nonReentrant {
        _swap(swapAmount);
    }
    function _swap(uint256 swapAmount) internal {
        require(swapStartBlock>0 && swapEndBlock>0, "swap redemption is disabled");
        require(block.number >= swapStartBlock, "redemption not started ");
        require(block.number <= swapEndBlock, "redemption finished");
        require(finalToken.balanceOf(address(this)) >= swapAmount, "Not Enough tokens in contract for swap");

        tmpToken.transferFrom(msg.sender, burnAddress, swapAmount);
        finalToken.safeTransfer(msg.sender, swapAmount);

        emit Swap(msg.sender, swapAmount);
    }

}
