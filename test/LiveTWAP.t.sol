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
  uint256 blockNumber = 19_660_300;
  function setUp() public {
    string memory rpcUrl = vm.rpcUrl("mainnet");
    vm.createSelectFork(rpcUrl, blockNumber); // mainnet @ block number (19_760_700)
    vm.label(address(this), "LP");

    univ3Pool = IUniswapV3Pool(uniFactory.getPool(
      address(0xdAC17F958D2ee523a2206206994597C13D831ec7), // usdt
      address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), // usdc
      poolFee
    ));

    logPoolDetailedInfo();
  }

  // In some situations tick should be rounded down
  // https://github.com/Uniswap/v3-periphery/blob/697c2474757ea89fec12a4e6db16a574fe259610/contracts/libraries/OracleLibrary.sol#L27-L36
  // This test aims to showcase the issue
  // Set pool and starting block number, test will run until it finds appropriate block and twap interval.
  function testSearchForNegativeTickRoundDownIssue() public {
    uint32 twapInterval = 10 minutes;
    uint32[] memory secondsAgos = new uint32[](2);

    while(true) {
      secondsAgos[0] = twapInterval; // from (before)
      secondsAgos[1] = 0; // to (now)
      sl.log("twapInterval: ", twapInterval, 0);
      
      (int56[] memory tickCumulatives, ) = univ3Pool.observe(secondsAgos);

      int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
      sl.logInt("tickCumulativesDelta: ", tickCumulativesDelta, 0);
      
      int24 tick = int24(tickCumulativesDelta / int32(twapInterval));
      int24 tickRounedDown = tick;
      // Always round to negative infinity
      if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(twapInterval) != 0)) tickRounedDown--;

      if (tick != tickRounedDown) {
        sl.logInt("tick: ", tick, 0);
        sl.logInt("tickRoundedDown: ", tickRounedDown, 0);
        return;
      }

      twapInterval += 10 minutes;

      if (twapInterval > 180 minutes) {
        blockNumber -= 10_000; // fork ~1.3 days back
        vm.createSelectFork(vm.rpcUrl("mainnet"), blockNumber);
        sl.log("roll fork to block: ", blockNumber, 0);
        twapInterval = 10 minutes;
        if (blockNumber < 19_520_300) {
          // Try another pool (change addresses)
          break;
        }
      }
      sl.logLineDelimiter();

    }

    fail();
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
