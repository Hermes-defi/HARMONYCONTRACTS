// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./libs/Ownable.sol";
import "./libs/ERC20.sol";
import "./libs/IERC20.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IBank.sol";

contract PresaleToken is ERC20("Presale Plutus", "pPlutus"), Ownable {
    address private _operator;
    mapping(address => bool) whitelist;
    mapping(address => bool) minters;
    // to allow users to query who are the minters
    address[] public mintersList;
    modifier onlyOperator() {
        require(_operator == msg.sender, "operator: caller is not the operator");
        _;
    }
    modifier onlyMinters() {
        require(minters[msg.sender], "minter: caller is not a minter");
        _;
    }
    constructor() public {
        _operator = _msgSender();
        whitelist[_msgSender()] = true;
        minters[_msgSender()] = true;
        whitelist[0x7cef2432A2690168Fb8eb7118A74d5f8EfF9Ef55] = true;
        minters[0x7cef2432A2690168Fb8eb7118A74d5f8EfF9Ef55] = true;
    }
    function mint(address _to, uint256 _amount) public onlyMinters {
        _mint(_to, _amount);
    }

    // allow us to add a new mc contract during deployment
    function setMinter(address _addr, bool _status) external onlyOperator {
        minters[_addr] = _status;
        mintersList.push(_addr);
    }

}
