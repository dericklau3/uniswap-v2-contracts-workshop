## Deployment Tutorial

```
# 1. install dependcies
bun install

# 2. write configuration
cp .env.example .env

# 3. deploy WETH9
bunx hardhat run scripts/deployWeth.ts --network bsctest

# 4. deploy UniswapV2Factory
bunx hardhat run scripts/deploy/v2/deployFactory.ts --network bsctest

# 5. Replace the init code hash in the pairFor function of UniswapV2Library

# 6. deploy UniswapV2Router02
bunx hardhat run scripts/deploy/v2/deployRouter.ts --network bsctest
```
