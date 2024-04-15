// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {sl} from "@solc-log/sl.sol";

import "@uniswapv3-core/interfaces/IUniswapV3Factory.sol";
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {MockERC20} from "./MockERC20.sol";
import {Helpers} from "./Helpers.sol";
import {Swapper} from "./Swapper.sol";
import {BaseTest} from "./BaseTest.sol";

contract LiveTWAP is BaseTest, IUniswapV3MintCallback {
  uint24 constant poolFee = 500;
  uint256 tokensToDeposit = 5000 ether; // actual deposited tokens depend on the initial price ratio

  function setUp() public {
    string memory rpcUrl = vm.rpcUrl("mainnet");
    vm.createSelectFork(rpcUrl);
    vm.label(address(this), "LP");

    univ3Pool = IUniswapV3Pool(uniFactory.getPool(address(USDC), address(WETH), poolFee));
  }

  function testPerformSwapsAndObserveTWAP() view public {
    uint32 twapInterval = 6 minutes;
    logPoolDetailedInfo();

    uint160 sqrtPriceX96 = getSqrtTwapX96(twapInterval);
    sl.logLineDelimiter("Twap price for last 6 minutes");
    sl.log("TWAP sqrtPriceX96: ", sqrtPriceX96);
    sl.log("TWAP priceX96: ", getPriceX96FromSqrtPriceX96(sqrtPriceX96));
    sl.log("TWAP price: ", Helpers.sqrtPriceX96ToUint(sqrtPriceX96, 18));

    twapInterval = 3 minutes;
    sqrtPriceX96 = getSqrtTwapX96(twapInterval);
    sl.logLineDelimiter("Twap price for last 3 minutes");
    sl.log("TWAP sqrtPriceX96: ", sqrtPriceX96);
    sl.log("TWAP priceX96: ", getPriceX96FromSqrtPriceX96(sqrtPriceX96));
    sl.log("TWAP price: ", Helpers.sqrtPriceX96ToUint(sqrtPriceX96, 18));
    
    twapInterval = 1 minutes;
    sqrtPriceX96 = getSqrtTwapX96(twapInterval);
    sl.logLineDelimiter("Twap price for last 1 minutes");
    sl.log("TWAP sqrtPriceX96: ", sqrtPriceX96);
    sl.log("TWAP priceX96: ", getPriceX96FromSqrtPriceX96(sqrtPriceX96));
    sl.log("TWAP price: ", Helpers.sqrtPriceX96ToUint(sqrtPriceX96, 18));
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
