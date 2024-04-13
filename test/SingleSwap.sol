// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {sl} from "@solc-log/sl.sol";

import "@uniswapv3-core/interfaces/IUniswapV3Factory.sol";
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@src/ISwapRouter.sol";
import {MockERC20} from "./MockERC20.sol";
import {Helpers} from "./Helpers.sol";
import {Swapper} from "./Swapper.sol";

contract SingleSwap is Test, IUniswapV3MintCallback {
  IUniswapV3Factory uniFactory = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
  ISwapRouter swapRouter = ISwapRouter(address(0xE592427A0AEce92De3Edee1F18E0157C05861564));

  uint24 constant poolFee = 500;
  uint160 initialPrice = 1000;
  uint256 tokensToDeposit = 10000 ether;
  int24 tickLower;
  int24 tickUpper;
  int24 currentTick;

  MockERC20 token0;
  MockERC20 token1;

  address token0addr;
  address token1addr;

  IUniswapV3Pool univ3Pool;
  Swapper swapper; // EOA account can't swap directly on univ3 pool, because it requires callback
  address swapperAddr;

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
    (, currentTick,,,,,) = univ3Pool.slot0();
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
    sl.log("amount0: ", amount0);
    sl.log("amount1: ", amount1);
    logPoolInfo();

    swapper = new Swapper(token0, token1, univ3Pool);
    swapperAddr = address(swapper);
    vm.label(swapperAddr, "Swapper");
  }
  
  function testSwapInPool() public {
    vm.startPrank(swapperAddr);
    deal(token0addr, swapperAddr, 100 ether);
    logTokenBalances(swapperAddr);

    sl.logLineDelimiter("Swap 1 WETH for USDC");

    // In production, this value can be used to set the limit for the price the swap will push the pool to, which can help protect against price impact or for setting up logic in a variety of price-relevant mechanisms.
    uint160 sqrtPriceLimitX96 = Helpers.MIN_SQRT_RATIO + 1; // Here we essentially accept any price for the swap
    (int256 amount0, int256 amount1) = univ3Pool.swap(
      swapperAddr, 
      true,              // swapping t0 for t1 (if false - swapping t1 for t0)
      1 ether,           // amount to swap
      sqrtPriceLimitX96, // if swapping t0 for t1, price can't be less than this. (Essentially slippage on price)
      "0x"
    );

    sl.logInt("amount0: ", amount0);
    sl.logInt("amount1: ", amount1);
    logTokenBalances(swapperAddr);

  }

  function testSwapTokensViaRouter() public {
    // EOA accounts can use the swap router
    address eoaSwapper = makeAddr("eoaSwapper");
    vm.startPrank(eoaSwapper);
    deal(token0addr, eoaSwapper, 100 ether);
    logTokenBalances(eoaSwapper);

    sl.logLineDelimiter("Swap 1 WETH for USDC");
    token0.approve(address(swapRouter), 1 ether);
    token1.approve(address(swapRouter), 1 ether);

    uint256 amountOut = swapRouter.exactInputSingle(
      ISwapRouter.ExactInputSingleParams({
        tokenIn: token0addr,
        tokenOut: token1addr,
        fee: poolFee,
        recipient: eoaSwapper,
        deadline: block.timestamp,
        amountIn: 1 ether,
        amountOutMinimum: 0, // No amount out slippage
        sqrtPriceLimitX96: 0 // We don't care how much the price changes on this trade
      })
    );

    sl.log("amount out: ", amountOut);
    logTokenBalances(eoaSwapper);
  }

  function logPoolInfo() public view {
    sl.logLineDelimiter("Pool Info");
    sl.log(string.concat("balance token0 ", token0.name(), ": "), token0.balanceOf(address(univ3Pool)));
    sl.log(string.concat("balance token1 ", token1.name(), ": "), token1.balanceOf(address(univ3Pool)));
  }

  function logTokenBalances(address user) public view {
    sl.logLineDelimiter(string.concat("T Balances ", vm.toString(user)));
    sl.log(string.concat("balance token0 ", token0.name(), ": "), token0.balanceOf(user));
    sl.log(string.concat("balance token1 ", token1.name(), ": "), token1.balanceOf(user));
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
