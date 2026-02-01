import { ethers, run } from "hardhat";
import { readJson, deployContract } from "./utils";

async function main() {

    const [deployer] = await ethers.getSigners();
    const options = { signer: deployer }
    await deployContract("contracts/WETH9.sol:WETH9", "weth", options, null, [])

    const path = "config/contracts.json";
    const contracts = readJson(path);
    // await run("verify:verify", {
    //     address: contracts.weth.address,
    // })
    console.log("finished");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});