// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@uniswapv3-periphery/interfaces/ISwapRouter.sol";
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";

contract Counter {
    uint256 public number;
    ISwapRouter public router;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
