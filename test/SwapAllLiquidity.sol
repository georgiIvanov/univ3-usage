// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {sl} from "@solc-log/sl.sol";

import "@uniswapv3-core/interfaces/IUniswapV3Factory.sol";
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockERC20} from "./MockERC20.sol";
import {Helpers} from "./Helpers.sol";
import {Swapper} from "./Swapper.sol";
import {BaseTest} from "./BaseTest.sol";

contract SwapAllLiquidity is BaseTest, IUniswapV3MintCallback {
  uint24 constant poolFee = 500;
  uint160 initialPrice = 1000;
  uint256 tokensToDeposit = 5000 ether;
  int24 tickLower;
  int24 tickUpper;

  function setUp() public {
    string memory rpcUrl = vm.rpcUrl("mainnet");
    vm.createSelectFork(rpcUrl);
    vm.label(address(this), "LP");

    MockERC20 ercUSDC = new MockERC20("MockUSDC", "USDC", 18);
    MockERC20 ercWETH = new MockERC20("MockWeth", "WETH", 18);

    univ3Pool = IUniswapV3Pool(uniFactory.createPool(address(ercUSDC), address(ercWETH), poolFee));

    (token0addr, token1addr) = univ3Pool.token0() == address(ercUSDC) ?
    (univ3Pool.token1(), univ3Pool.token0()) : (univ3Pool.token0(), univ3Pool.token1());
    
    token0 = MockERC20(token0addr);
    token1 = MockERC20(token1addr);
    vm.label(token0addr, token0.name());
    vm.label(token1addr, token1.name());

    assertNotEq(address(0), address(univ3Pool));

    token0.mint(address(this), 1_000_000 ether);
    token1.mint(address(this), 1_000_000 ether);

    uint160 sqrtPriceX96 = Helpers.computeSqrtPriceX96(initialPrice);
    sl.logLineDelimiter("setUp");
    sl.log("sqrtPriceX96: ", sqrtPriceX96);
    univ3Pool.initialize(sqrtPriceX96);
    sl.logInt("tick spacing: ", univ3Pool.tickSpacing());
    (, int24 currentTick,,,,,) = univ3Pool.slot0();
    sl.logInt("current tick: ", currentTick);

    int24 nearestTick = Helpers.getNearestUsableTick(currentTick, univ3Pool.tickSpacing());
    tickLower = nearestTick - univ3Pool.tickSpacing();
    tickUpper = nearestTick + univ3Pool.tickSpacing();

    uint160 sqrtRatioAX96 = Helpers.getSqrtRatioAtTick(tickLower);
    uint160 sqrtRatioBX96 = Helpers.getSqrtRatioAtTick(tickUpper);

    uint128 liquidity = Helpers.getLiquidityForAmounts(
      sqrtPriceX96,
      sqrtRatioAX96,
      sqrtRatioBX96,
      tokensToDeposit,
      tokensToDeposit
    );

    (uint256 amount0, uint256 amount1) = univ3Pool.mint(
      address(this), // To
      tickLower,     // tick lower
      tickUpper,     // tick upper
      liquidity,     // liquidity - number derived from current price; see LiquidityManagement.sol 
      "0x"           // Usually some context about the tx is abi.encoded - pool key, payer (sender)
    );
    sl.log("start amount0: ", amount0);
    sl.log("start amount1: ", amount1);

    swapper = new Swapper(token0, token1, univ3Pool);
    swapperAddr = address(swapper);
    vm.label(swapperAddr, "Swapper");
    sl.log("\n");
  }
  
  // Swaps until liquidity is depleted
  function testSwapAllLiquidityInPool() public {
    vm.startPrank(swapperAddr);
    deal(token0addr, swapperAddr, 100 ether);
    logTokenBalances(swapperAddr);
    int256 amountToSwap = 1 ether;
    int24 i = 0;

    // swap t0 for t1 until liquidity is depleted
    while(true) {
      string memory title = string.concat("Swap 1 WETH for USDC #", vm.toString(++i));
      sl.logLineDelimiter(title);
      
      uint160 sqrtPriceLimitX96 = Helpers.MIN_SQRT_RATIO + 1;
      (int256 amount0, int256 amount1) = univ3Pool.swap(
        swapperAddr, 
        true,              // swapping t0 for t1 (if false - swapping t1 for t0)
        amountToSwap,      // amount to swap
        sqrtPriceLimitX96, // if swapping t0 for t1, price can't be less than this. (Essentially slippage on price)
        "0x"
      );

      sl.logInt("amount0: ", amount0);
      sl.logInt("amount1: ", amount1);
      logTokenBalances(swapperAddr);

      (uint160 sqrtPriceX96, int24 currentTick,,,,,) = univ3Pool.slot0();
      sl.log("New sqrtPriceX96: ", sqrtPriceX96);
      sl.logInt("current tick: ", currentTick);
      sl.log("Liquidity range: ", univ3Pool.liquidity());
      logPoolInfo();

      if(univ3Pool.liquidity() == 0) {
        break;
      }
      sl.log("\n");
    }

    // swap t1 for t0 until liquidity is depleted
    sl.log("\n\n");
    sl.logLineDelimiter("Begin swapping in the other direction");
    deal(token1addr, swapperAddr, 10000 ether);
    amountToSwap = 1_000 ether;
    i = 0;
    logTokenBalances(swapperAddr);
    while(true) {
      string memory title = string.concat("Swap 1000 USDC for WETH #", vm.toString(++i));
      sl.logLineDelimiter(title);
      
      uint160 sqrtPriceLimitX96 = Helpers.MAX_SQRT_RATIO - 1;
      (int256 amount0, int256 amount1) = univ3Pool.swap(
        swapperAddr, 
        false,             // swapping t1 for t0
        amountToSwap,      // amount to swap
        sqrtPriceLimitX96, // when swapping t1 for t0, price can't be more than this. (Essentially slippage on price)
        "0x"
      );

      sl.logInt("amount0: ", amount0);
      sl.logInt("amount1: ", amount1);
      logTokenBalances(swapperAddr);

      (uint160 sqrtPriceX96, int24 currentTick,,,,,) = univ3Pool.slot0();
      sl.log("New sqrtPriceX96: ", sqrtPriceX96);
      sl.logInt("current tick: ", currentTick);
      sl.log("Liquidity range: ", univ3Pool.liquidity());
      logPoolInfo();

      if(univ3Pool.liquidity() == 0) {
        break;
      }
    }
  }


  function logPoolInfo() public view {
    sl.logLineDelimiter("Pool Info");
    sl.log(string.concat("balance token0 ", token0.name(), ": "), token0.balanceOf(address(univ3Pool)));
    sl.log(string.concat("balance token1 ", token1.name(), ": "), token1.balanceOf(address(univ3Pool)));
  }

  function logTokenBalances(address user) public view {
    sl.indent();
    sl.logLineDelimiter(string.concat("T Balances ", vm.toString(user)));
    sl.log(string.concat("balance token0 ", token0.name(), ": "), token0.balanceOf(user));
    sl.log(string.concat("balance token1 ", token1.name(), ": "), token1.balanceOf(user));
    sl.outdent();
  }

  /*//////////////////////////////////////////////////////////////
                        UNIV3 MINT CALLBACK
  //////////////////////////////////////////////////////////////*/

  function uniswapV3MintCallback(
    uint256 amount0Owed,
    uint256 amount1Owed,
    bytes calldata
  ) external override {
    // decode data and verify callback here
    
    sl.indent();
    sl.logLineDelimiter("uniswapV3MintCallback");

    sl.log("amount0Owed: ", amount0Owed);
    sl.log("amount1Owed: ", amount1Owed);
    if (amount0Owed > 0) {
      token0.transfer(address(univ3Pool), amount0Owed);
    }

    if(amount1Owed > 0) {
      token1.transfer(address(univ3Pool), amount1Owed);
    }
    sl.logLineDelimiter();
    sl.outdent();
  }
}
