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

contract TWAP is BaseTest, IUniswapV3MintCallback {
  uint24 constant poolFee = 500;
  uint160 initialPrice = 1000;
  uint256 tokensToDeposit = 5000 ether; // actual deposited tokens depend on the initial price ratio
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


    // Initially, there is only one slot for storing prices for TWAP calculation
    univ3Pool.increaseObservationCardinalityNext(20); // cardinality index wraps once it reaches the max 

    swapper = new Swapper(token0, token1, univ3Pool);
    swapperAddr = address(swapper);
    vm.label(swapperAddr, "Swapper");
    sl.log("\n");
  }
  
  // Perorm swaps and calculate TWAP
  function testCalculateTWAP() public {
    vm.startPrank(swapperAddr);
    deal(token0addr, swapperAddr, 100 ether);
    logTokenBalances(swapperAddr);
    int256 amountToSwap = 1 ether;
    int24 i = 0;
    // Observe how the TWAP sqrtPriceX96 changes when moving this value closer to 0
    uint32 twapInterval = 6 minutes;

    // swap t0 for t1 until liquidity is depleted
    while(true) {
      string memory title = string.concat("Swap 1 WETH for USDC #", vm.toString(++i));
      sl.logLineDelimiter(title);
      
      uint160 sqrtPriceLimitX96 = Helpers.MIN_SQRT_RATIO + 1;
      univ3Pool.swap(
        swapperAddr, 
        true,              // swapping t0 for t1 (if false - swapping t1 for t0)
        amountToSwap,      // amount to swap
        sqrtPriceLimitX96, // if swapping t0 for t1, price can't be less than this. (Essentially slippage on price)
        "0x"
      );

      logTokenBalances(swapperAddr);
      
      logPoolDetailedInfo();
      vm.warp(block.timestamp + 1 minutes);
      if(univ3Pool.liquidity() == 0) {
        break;
      }
      sl.log("\n");
    }

    sl.logLineDelimiter("Twap price for the last X minutes");
    vm.warp(block.timestamp + 1 minutes);
    // Reverts if twapInterval is too far to get a price
    sl.log("TWAP sqrtPriceX96: ", getSqrtTwapX96(twapInterval));
    sl.log("TWAP priceX96: ", getPriceX96FromSqrtPriceX96(getSqrtTwapX96(twapInterval)));

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
      univ3Pool.swap(
        swapperAddr, 
        false,             // swapping t1 for t0
        amountToSwap,      // amount to swap
        sqrtPriceLimitX96, // when swapping t1 for t0, price can't be more than this. (Essentially slippage on price)
        "0x"
      );

      logTokenBalances(swapperAddr);
      
      logPoolDetailedInfo();
      vm.warp(block.timestamp + 1 minutes);
      if(univ3Pool.liquidity() == 0) {
        break;
      }
      sl.log("\n");
    }

    sl.logLineDelimiter("Twap price for the last X minutes");
    vm.warp(block.timestamp + 1 minutes);
    // Reverts if twapInterval is too far to get a price
    sl.log("TWAP sqrtPriceX96: ", getSqrtTwapX96(twapInterval));
    sl.log("TWAP priceX96: ", getPriceX96FromSqrtPriceX96(getSqrtTwapX96(twapInterval)));
  }

  function getSqrtTwapX96(uint32 twapInterval) public view returns (uint160 sqrtPriceX96) {
    if (twapInterval == 0) {
      // return the current price if twapInterval == 0
      (sqrtPriceX96, , , , , , ) = univ3Pool.slot0();
    } else {
      uint32[] memory secondsAgos = new uint32[](2);
      secondsAgos[0] = twapInterval; // from (before)
      secondsAgos[1] = 0; // to (now)
      
      (int56[] memory tickCumulatives, ) = univ3Pool.observe(secondsAgos);

      // tick(imprecise as it's an integer) to price
      sqrtPriceX96 = Helpers.getSqrtRatioAtTick(
        int24((tickCumulatives[1] - tickCumulatives[0]) / int32(twapInterval))
      );
    }
  }

  function getPriceX96FromSqrtPriceX96(uint160 sqrtPriceX96) public pure returns(uint256 priceX96) {
    return Helpers.mulDiv(sqrtPriceX96, sqrtPriceX96, Helpers.Q96);
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
