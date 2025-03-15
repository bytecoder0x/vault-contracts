import hre from "hardhat";

function delay(ms: number) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function main() {
    const [signer] = await hre.ethers.getSigners();
 
    // testnet
    // let saleTokenAddress = "0x9c592E91BB3360008257dEE25210285C41AeAe8F";
    // let usdcTokenAddress = "0x90D8E2c783983A8B11AddDDfcdAA862F43e83C96";
    // let usdtTokenAddress = "0xcb3567dE07596e62b9B7F05128bbeab9035310eF";
    // let wethTokenAddress = "0x3928Ad7A5F21149Da0D679f0048bFFa811f2af97";
    // let priceFeedAddress = "0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165";
    let ownerAddress = signer.address;

    // mainnet
    let saleTokenAddress = "0xE422D79FDFEb0E4AbB3efE5f413D70695a6600b2";
    let usdcTokenAddress = "0xb4f80a9Fecf326c4e820b4395DEA0bD314b4bA88"
    let usdtTokenAddress = "0x73103325266c813145B80E36D1EC6cb961A36751"
    let wethTokenAddress = "0x4aE98CBeAD29E6f04Ce0A00f79Dea247F50142Df"
    let priceFeedAddress = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612";

    // const SaleTokenFactory = await hre.ethers.getContractFactory("MockERC20", signer);
    // const saleToken = await SaleTokenFactory.deploy("GOIL", "GOIL");
    // await saleToken.waitForDeployment();
    // console.log("SaleToken contract deployed to:", saleToken.target);
    // saleTokenAddress = await saleToken.getAddress();

    // const UsdcTokenFactory = await hre.ethers.getContractFactory("MockERC20", signer);
    // const usdcToken = await UsdcTokenFactory.deploy("USDC", "USDC");
    // await usdcToken.waitForDeployment();
    // console.log("UsdcToken contract deployed to:", usdcToken.target);
    // usdcTokenAddress = await usdcToken.getAddress();
    
    // const UsdtTokenFactory = await hre.ethers.getContractFactory("MockERC20", signer);
    // const usdtToken = await UsdtTokenFactory.deploy("USDT", "USDT");
    // await usdtToken.waitForDeployment();
    // console.log("UsdtToken contract deployed to:", usdtToken.target);
    // usdtTokenAddress = await usdtToken.getAddress();

    // const WethTokenFactory = await hre.ethers.getContractFactory("MockWETH", signer);
    // const wethToken = await WethTokenFactory.deploy();
    // await wethToken.waitForDeployment();
    // console.log("WethToken contract deployed to:", wethToken.target);
    // wethTokenAddress = await wethToken.getAddress();

    // const TokenVestingFactory = await hre.ethers.getContractFactory("TokenVesting", signer);
    // const tokenVesting = await TokenVestingFactory.deploy(ownerAddress, saleTokenAddress);
    // await tokenVesting.waitForDeployment();
    // console.log("TokenVesting contract deployed to:", tokenVesting.target);

    // const TokenSaleFactory = await hre.ethers.getContractFactory("TokenSale", signer);
    // const tokenSale = await TokenSaleFactory.deploy(saleTokenAddress, usdcTokenAddress, usdtTokenAddress, wethTokenAddress, priceFeedAddress, ownerAddress);
    // await tokenSale.waitForDeployment();
    // console.log("TokenSale contract deployed to:", tokenSale.target);

    // const tokenVesting = await hre.ethers.getContractAt("TokenVesting", "0xD182E3212C9a2aeEab6fdB8Ae137Be32C582fd3A");
    // const tokenSale = await hre.ethers.getContractAt("TokenSale", "0x1CbDdA20c365f397Ca9e3816E58EE31a1A7397Ac");

    console.log("Waiting for block confirmations...");
    // await delay(30000); // Wait for 30 seconds before verifying the contract

    // await tokenSale.setVestingContract(tokenVesting.target);
    // await tokenVesting.setPresaleContract(tokenSale.target);

    await hre.run("verify:verify", {
        address: saleTokenAddress,
        constructorArguments: ["GOIL", "GOIL"],
    });
    
    await hre.run("verify:verify", {
        address: usdcTokenAddress,
        constructorArguments: ["USDC", "USDC"],
    });

    await hre.run("verify:verify", {
        address: usdtTokenAddress,
        constructorArguments: ["USDT", "USDT"],
    });

    await hre.run("verify:verify", {
        address: wethTokenAddress,
        constructorArguments: [],
    });

    await hre.run("verify:verify", {
        address: "0xC7aed5d1cfF5eB7924B0d8E9E4e562185DC5b67B",
        constructorArguments: [ownerAddress, saleTokenAddress]
    });

    await hre.run("verify:verify", {
        address: "0xe6Ba04E96c3F00D73626f7A9F957f668cD5A567C",
        constructorArguments: [saleTokenAddress, usdcTokenAddress, usdtTokenAddress, wethTokenAddress, priceFeedAddress, ownerAddress],
    });

    // const paymentAmount = await tokenSale.getPaymentAmountForTokens(1, hre.ethers.parseEther("1"), wethTokenAddress);
    // console.log((Number(paymentAmount) / 1e18).toString());
    // console.log(hre.ethers.parseEther("1") / 1e18);
    // await tokenSale.buyTokens(1, hre.ethers.parseEther("1"), wethTokenAddress, { value: paymentAmount - 1n });
}

main().then(res => res).catch(err => console.log(err));
