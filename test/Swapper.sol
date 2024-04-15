// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {sl} from "@solc-log/sl.sol";

import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import {MockERC20} from "./MockERC20.sol";

// Since EOA can't call swap directly on Uniswap V3 pool, we have this contract
contract Swapper is IUniswapV3SwapCallback {
  MockERC20 token0;
  MockERC20 token1;

  IUniswapV3Pool univ3Pool;

  constructor(MockERC20 token0_, MockERC20 token1_, IUniswapV3Pool univ3Pool_) {
    token0 = token0_;
    token1 = token1_;
    univ3Pool = univ3Pool_;
  }

  /*//////////////////////////////////////////////////////////////
                        UNIV3 SWAP CALLBACK
  //////////////////////////////////////////////////////////////*/

  function uniswapV3SwapCallback(
      int256 amount0Delta,
      int256 amount1Delta,
      bytes calldata
  ) external {
    sl.indent();
    sl.logLineDelimiter("Swapper::uniswapV3SwapCallback");
    sl.logInt("amount0Delta: ", amount0Delta);
    sl.logInt("amount1Delta: ", amount1Delta);

    if (amount0Delta > 0) {
      token0.transfer(address(univ3Pool), uint256(amount0Delta));
    }

    if(amount1Delta > 0) {
      token1.transfer(address(univ3Pool), uint256(amount1Delta));
    }

    sl.outdent();
  }
}