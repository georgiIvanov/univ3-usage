# UniV3 usage

Illustrates UniswapV3 usage in minimal examples.

Code is written with educational purpose and is unfit for production uses.

Examples are meant to be examined in the following order:
1. Factory - creation of a uniswap v3 pool
2. AddLiquidity - adding liquidity to a pool directly and via npm
3. SingleSwap - perform a swap in one direction
4. SwapAllLiquidity - perform swaps until liquidity in one side is depleted
5. TWAP - calculate TWAP for a newly created pool
6. LiveTWAP - calculate TWAP for production USDC/WETH pool

> Some explanations are omitted in later examples for brevity.

# Structure
Some of the interfaces needed to be copied to the project's `src/` folder, because of OZ import path issues.

# Tests

Run the following command in terminal:
```bash
forge test -vv
```

# Note
Working directly with the Uniswap V3 contracts brings multitude of issues:
1. They have strict compiler checks for older versions - (=0.7.6).
2. Lots of u/int casts that are not allowed in newer compiler versions.
3. They are incompatible with newer OZ versions.

All of this makes the Uniswap V3 implementation contracts difficult to work with.
This is why projects import only the univ3 interfaces and then run tests on forked blockchain state.

# Articles

- [Uniswap V3 Features Explained in Depth](https://medium.com/taipei-ethereum-meetup/uniswap-v3-features-explained-in-depth-178cfe45f223)
- [Uniswap V3 Error Codes and what they mean](https://docs.uniswap.org/contracts/v3/reference/error-codes)
