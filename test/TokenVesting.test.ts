import { ethers } from "hardhat";
import { expect } from "chai";
import { TokenVesting, MockERC20 } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("TokenVesting", function () {
    let tokenVesting: TokenVesting;
    let token: MockERC20;
    let owner: HardhatEthersSigner;
    let presale: HardhatEthersSigner;
    let recipient: HardhatEthersSigner;
    let otherAccount: HardhatEthersSigner;

    const INITIAL_SUPPLY = ethers.parseEther("1000000");
    const VESTING_AMOUNT = ethers.parseEther("10000");

    const deployVestingContract = async () => {
        const [owner, presale, recipient, otherAccount] = await ethers.getSigners();

        const Token = await ethers.getContractFactory("MockERC20");
        const token = await Token.deploy(INITIAL_SUPPLY);
        await token.waitForDeployment();

        const TokenVesting = await ethers.getContractFactory("TokenVesting");
        const tokenVesting = await TokenVesting.deploy(owner.address, token.target);
        await tokenVesting.waitForDeployment();

        return { owner, presale, recipient, otherAccount, token, tokenVesting }
    }

    beforeEach(async function () {
        const fixture = await loadFixture(deployVestingContract);

        tokenVesting = fixture.tokenVesting;
        token = fixture.token;
        owner = fixture.owner;
        presale = fixture.presale;
        recipient = fixture.recipient;
        otherAccount = fixture.otherAccount;
    });

    describe("claimTokens", function () {
        it.only("Should allow recipient to claim tokens after cliff period", async function () {
            // Set up vesting schedule
            const startTime = await time.latest();
            const endTime = startTime + 10 * 24 * 3600; // 30 days
            const cliffPeriod = 5 * 24 * 3600; // 7 days
            const slicePeriod = 24 * 3600; // 1 day

            await token.approve(tokenVesting.target, VESTING_AMOUNT);
            await tokenVesting.createVesting(
                await recipient.getAddress(),
                startTime,
                endTime,
                cliffPeriod,
                slicePeriod,
                VESTING_AMOUNT,
                0, // VestingType
            );

            // Move time forward past the cliff period
            await time.increase(cliffPeriod + slicePeriod + slicePeriod + slicePeriod + slicePeriod);
            await tokenVesting.connect(recipient).claimTokens();
            console.log(await token.balanceOf(tokenVesting.target) / BigInt(1e18), "TOKEN vesting");
            console.log(await token.balanceOf(recipient.address) / BigInt(1e18));
        });
    });
});
