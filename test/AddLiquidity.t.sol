// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {sl} from "@solc-log/sl.sol";

import "@uniswapv3-core/interfaces/IUniswapV3Factory.sol";
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@src/INonfungiblePositionManager.sol";
import {MockERC20} from "./MockERC20.sol";
import {Helpers} from "./Helpers.sol";

contract AddLiquidity is Test, IUniswapV3MintCallback {
  IUniswapV3Factory uniFactory = IUniswapV3Factory(address(0x1F98431c8aD98523631AE4a59f267346ea31F984));
  INonfungiblePositionManager npm = INonfungiblePositionManager(address(0xC36442b4a4522E871399CD717aBDD847Ab11FE88));

  uint24 constant poolFee = 500;
  uint160 initialPrice = 1000 ether;
  int24 tickLower = 0;
  int24 tickUpper = 100;

  MockERC20 token0;
  MockERC20 token1;

  address token0addr;
  address token1addr;

  IUniswapV3Pool univ3Pool;

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

    assertNotEq(address(0), address(univ3Pool));

    // initial sqrt price: 1 WETH = 1000 USDC
    // sqrtPriceX96 = sqrt(1000 ether) * 2^96
    uint160 sqrtPriceX96 = Helpers.computeSqrtPriceX96(initialPrice);
    sl.logLineDelimiter("setUp");
    sl.log("sqrtPriceX96: ", sqrtPriceX96);
    univ3Pool.initialize(sqrtPriceX96);
  }

  // Adding liquidity to an empty pool, oversimplified example
  function testAddLiquidityToPool() public {
    sl.logLineDelimiter("Add liquidity to an empty pool");
    uint256 tokensToDeposit = 2 ether;

    token0.mint(address(this), 100 ether);
    token1.mint(address(this), 100 ether);

    (uint160 sqrtPriceX96, , , , , , ) = univ3Pool.slot0();
    uint160 sqrtRatioAX96 = Helpers.getSqrtRatioAtTick(tickLower);
    uint160 sqrtRatioBX96 = Helpers.getSqrtRatioAtTick(tickUpper);

    // liquidity param ≠ token0 + token1
    uint128 liquidity = Helpers.getLiquidityForAmounts(
      sqrtPriceX96,
      sqrtRatioAX96,
      sqrtRatioBX96,
      tokensToDeposit,
      tokensToDeposit
    );
    sl.log("sqrtPriceX96: ", sqrtPriceX96);
    sl.log("liquidity: ", liquidity);

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
  }

  function testAddLiquidityViaNPM() public {
    sl.logLineDelimiter("Add liquidity via NPM to empty pool");
    uint256 tokensToDeposit = 2 ether;

    token0.mint(address(this), 100 ether);
    token1.mint(address(this), 100 ether);

    token0.approve(address(npm), tokensToDeposit);
    token1.approve(address(npm), tokensToDeposit);

    address pool = npm.createAndInitializePoolIfNecessary(
      token0addr, 
      token1addr, 
      poolFee, 
      0 // pool is already created, so no need to specify initial sqrt price x96
    );
    assertNotEq(address(0), pool);
    sl.log("pool: ", pool);

    (uint256 tokenId,
    uint128 liquidity,
    uint256 amount0,
    uint256 amount1) = npm.mint(
        INonfungiblePositionManager.MintParams({
        token0: token0addr,
        token1: token1addr,
        fee: poolFee,
        tickLower: tickLower,
        tickUpper: tickUpper,
        amount0Desired: tokensToDeposit,
        amount1Desired: tokensToDeposit,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: block.timestamp
      })
    );

    sl.log("tokenId: ", tokenId, 0);
    sl.log("liquidity: ", liquidity);
    sl.log("amount0: ", amount0);
    sl.log("amount1: ", amount1);
    logPoolInfo();
  }

  function logPoolInfo() public view {
    sl.logLineDelimiter("Pool Info");
    sl.log(string.concat("balance token0 ", token0.name(), ": "), token0.balanceOf(address(univ3Pool)));
    sl.log(string.concat("balance token1 ", token1.name(), ": "), token1.balanceOf(address(univ3Pool)));
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