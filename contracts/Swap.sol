// SPDX-License-Identifier: UNLICENSED
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IronSwapRouter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import './libs/AddrArrayLib.sol';
pragma solidity ^0.6.12;

contract MultiRouterSwap is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    IERC20 public APOLLO;
    IERC20 public IRON;
    IERC20 public USDC;
    IronSwapRouter public IronRouter = IronSwapRouter(0x4C96C61AF64e78F848fB2Ec965C4da08430dF348);
    IUniswapV2Router02 public DFYNRouter = IUniswapV2Router02(0xA102072A4C07F06EC3B4900FDC4C7B80b6c57429);
    event Swap(address user, uint256 USDC_Amount, uint256 IRON_Amount, uint256 APOLLO_Amount);

    constructor() public {
        APOLLO = IERC20(0x577aa684B89578628941D648f1Fbd6dDE338F059);
        IRON = IERC20(0xD86b5923F3AD7b585eD81B448170ae026c65ae9a);
        USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);

        approvator(APOLLO);
        approvator(IRON);
        approvator(USDC);

    }

    function approvator( IERC20 token ) internal {
        token.approve(0x4C96C61AF64e78F848fB2Ec965C4da08430dF348, uint(0));
        token.approve(0x4C96C61AF64e78F848fB2Ec965C4da08430dF348, uint(- 1));
        token.approve(0xA102072A4C07F06EC3B4900FDC4C7B80b6c57429, uint(0));
        token.approve(0xA102072A4C07F06EC3B4900FDC4C7B80b6c57429, uint(- 1));
    }

    function buy(uint256 USDC_Amount) nonReentrant external {
        USDC.safeTransferFrom(msg.sender, address(this), USDC_Amount);
        uint256 IRON_Amount = _safeSwapIron(USDC_Amount, address(USDC), address(IRON));
        uint256 APOLLO_Amount = _safeSwapUniswap(IRON_Amount, address(IRON), address(APOLLO));
        emit Swap(msg.sender, USDC_Amount, IRON_Amount, APOLLO_Amount);
        APOLLO.safeTransfer(msg.sender, APOLLO_Amount);
    }
    function _safeSwapIron(uint256 bal, address token0, address token1) internal returns(uint256) {
        uint256 _before = IERC20(token1).balanceOf(address(this));
        IIronSwap pool = IIronSwap(0xCaEb732167aF742032D13A9e76881026f91Cd087);
        IIronSwap basePool = IIronSwap(0x837503e8A8753ae17fB8C8151B8e6f586defCb57);
        IronRouter.swapFromBase(pool, basePool, 0, 1, bal, 0, now.add(600));
        uint256 _after = IERC20(token1).balanceOf(address(this));
        return _after.sub(_before);
    }

    function _safeSwapUniswap(uint256 bal, address token0, address token1) internal returns(uint256) {
        uint256 _before = IERC20(token1).balanceOf(address(this));
        address[] memory _path = new address[](2);
        _path[0] = token0;
        _path[1] = token1;
        DFYNRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(bal, 0, _path, address(this), now.add(600));
        uint256 _after = IERC20(token1).balanceOf(address(this));
        return _after.sub(_before);
    }

    function inCaseTokensGetStuck(address _token, address to) external onlyOwner {
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(to, amount);
    }

}
