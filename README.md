# UniV3 usage

Illustrates UniswapV3 usage in minimal examples.

Code is written with educational purpose and is unfit for production uses.

# Structure
Some of the interfaces needed to be copied to the project's `src/` folder, because of OZ import path issues.

# Note
Working directly with the Uniswap V3 contracts brings multitude of issues:
1. They have strict compiler checks for older versions - (=0.7.6)
2. Lots of u/int casts that are not allowed in newer compiler versions.

This is why projects import univ3 interfaces and then run tests on forked blockchain state.
