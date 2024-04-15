// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {sl} from "@solc-log/sl.sol";

import "@uniswapv3-core/interfaces/IUniswapV3Factory.sol";
import "@uniswapv3-core/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

  function logPoolBalancesInfo() public view {
    sl.logLineDelimiter("Pool Balances Info");
    sl.log(string.concat("balance token0 ", token0.name(), ": "), token0.balanceOf(address(univ3Pool)));
    sl.log(string.concat("balance token1 ", token1.name(), ": "), token1.balanceOf(address(univ3Pool)));
  }

  function logPoolDetailedInfo() public view {
    IERC20Metadata t0 = IERC20Metadata(univ3Pool.token0());
    IERC20Metadata t1 = IERC20Metadata(univ3Pool.token1());

    sl.indent();
    sl.logLineDelimiter("Pool Info");
    sl.log(
      string.concat("balance token0 ", t0.name(), ": "), 
      t0.balanceOf(address(univ3Pool))
    );
    sl.log(
      string.concat("balance token1 ", t1.name(), ": "), 
      t1.balanceOf(address(univ3Pool))
    );
    (uint160 sqrtPriceX96, int24 currentTick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext,,) 
    = univ3Pool.slot0();
    sl.log("New sqrtPriceX96: ", sqrtPriceX96);
    sl.logInt("Current tick: ", currentTick);
    sl.log("Liquidity range: ", univ3Pool.liquidity());
    sl.log("observationIndex: ", observationIndex, 0);
    sl.log("observationCardinality: ", observationCardinality, 0);
    sl.log("observationCardinalityNext: ", observationCardinalityNext, 0);
    sl.logLineDelimiter();
    sl.outdent();
  }

  function logTokenBalances(address user) public view {
    sl.indent();
    sl.logLineDelimiter(string.concat("T Balances ", vm.toString(user)));
    sl.log(string.concat("balance token0 ", token0.name(), ": "), token0.balanceOf(user));
    sl.log(string.concat("balance token1 ", token1.name(), ": "), token1.balanceOf(user));
    sl.outdent();
  }
}