// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {sl} from "@solc-log/sl.sol";

import "@uniswapv3-core/interfaces/IUniswapV3Factory.sol";
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";

import {MockERC20} from "./MockERC20.sol";
import {BaseTest} from "./BaseTest.sol";

contract Factory is BaseTest {
  uint24 constant poolFee = 500;

  constructor() {
  }

  function setUp() public {
    string memory rpcUrl = vm.rpcUrl("mainnet");
    sl.log(string.concat("rpcUrl ", rpcUrl));
    uint256 forkId = vm.createSelectFork(rpcUrl);
    sl.log("forkId: ", forkId);
    sl.log("blockNumber: ", block.number, 0);
  }

  function testGetPool() view public {
    address pool = uniFactory.getPool(WETH, USDC, poolFee);
    sl.log("univ3 pool: ", pool);
    assertNotEq(address(0), pool);
  }

  function testCreatePool() public {
    address token0 = address(new MockERC20("MockUSDC", "USDC", 18));
    address token1 = address(new MockERC20("MockWeth", "WETH", 18));

    address newPool = uniFactory.createPool(token0, token1, poolFee);
    sl.log("newPool: ", newPool);
    assertNotEq(address(0), newPool);
    
    (address first, address second) = IUniswapV3Pool(newPool).token0() == address(token0) ?
    (token0, token1) : (token1, token0);

    assertEq(IUniswapV3Pool(newPool).token0(), first);
    assertEq(IUniswapV3Pool(newPool).token1(), second);
    // To use the pool, it needs to first be initialized
  }
}