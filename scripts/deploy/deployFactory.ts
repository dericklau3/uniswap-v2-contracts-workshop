import { ethers, run } from "hardhat";
import { readJson, deployContract, executeTx } from "../utils";

async function main() {

  const [deployer] = await ethers.getSigners();

  const path = "config/contracts.json";

  const options = { signer: deployer }
  const uniswapV2FactoryArgs = {
    feeToSetter: deployer.address
  };

  // After deploying, obtain the INIT_CODE_PAIR_HASH and proceed to modify pairFor in v2-periphery/libraries/UniswapV2Library
  await deployContract("UniswapV2Factory", "uniswapV2Factory", options, uniswapV2FactoryArgs, [[uniswapV2FactoryArgs.feeToSetter]])

  const contracts = readJson(path)

  const uniswapV2Factory = await ethers.getContractAt("UniswapV2Factory", contracts.uniswapV2Factory.address, deployer);
  const pairHash = await uniswapV2Factory.INIT_CODE_PAIR_HASH();
  console.log("pairHash: ", pairHash);
  console.log("finished");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});