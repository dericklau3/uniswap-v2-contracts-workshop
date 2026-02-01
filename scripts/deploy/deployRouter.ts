import { ethers, run } from "hardhat";
import { readJson, deployContract, executeTx } from "../utils";

async function main() {

  const [deployer] = await ethers.getSigners();

  const path = "config/contracts.json";
  let contracts = readJson(path)

  const options = { signer: deployer }
  const uniswapV2RouterArgs = {
    factory: contracts.uniswapV2Factory.address,
    weth: contracts.weth.address
  };
  await deployContract("UniswapV2Router02", "uniswapV2Router", options, uniswapV2RouterArgs, [
    [uniswapV2RouterArgs.factory, uniswapV2RouterArgs.weth]
  ])
  console.log("finished");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});