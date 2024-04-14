// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {sl} from "@solc-log/sl.sol";

import "@uniswapv3-core/interfaces/IUniswapV3Factory.sol";
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@src/INonfungiblePositionManager.sol";
import "@src/ISwapRouter.sol";
import {MockERC20} from "./MockERC20.sol";
import {Helpers} from "./Helpers.sol";
import {Swapper} from "./Swapper.sol";

contract BaseTest is Test {
  // All addresses are on ETH mainnet
  IUniswapV3Factory uniFactory = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
  INonfungiblePositionManager npm = INonfungiblePositionManager(address(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));
  ISwapRouter swapRouter = ISwapRouter(address(0xE592427A0AEce92De3Edee1F18E0157C05861564));
  address constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  address constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  MockERC20 token0;
  MockERC20 token1;

  address token0addr;
  address token1addr;

  IUniswapV3Pool univ3Pool;

  Swapper swapper; // EOA account can't swap directly on univ3 pool, because it requires callback
  address swapperAddr;
}