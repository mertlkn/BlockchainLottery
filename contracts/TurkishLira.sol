// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TurkishLira is ERC20 {
    constructor() ERC20("Turkish Lira", "TL") {
        _mint(msg.sender, 1000 * 10 ** decimals());
    }


    function mintForMe(uint amnt) public {
        _mint(msg.sender, amnt);
    }
}