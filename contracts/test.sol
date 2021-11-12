pragma solidity >=0.4.21 <0.6.0;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract HarmonyERC20 is ERC20,
ERC20Detailed("Test", "TST", 18, 100000 ether)  {
    constructor()
    ERC20Detailed(_name, _symbols, _decimals)
    public {

        _mint(msg.sender, _amount);
    }
}
