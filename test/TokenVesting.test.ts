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

        return { owner, presale, recipient, otherAccount, token, tokenVesting };
    };

    const createVesting = async (overrides = {}) => {
        const defaultParams = {
            recipient: recipient.address,
            startTime: await time.latest(), // now
            endTime: (await time.latest()) + 10 * 24 * 3600, // 10 days
            cliffPeriod: 5 * 24 * 3600, // 5 days
            slicePeriod: 24 * 3600, // 1 day
            amount: VESTING_AMOUNT,
            vestingType: 0, // PUBLIC type
            sender: owner,
        };

        const params = { ...defaultParams, ...overrides };

        await token.approve(tokenVesting.target, params.amount);
        await tokenVesting
            .connect(params.sender)
            .createVesting(
                params.recipient,
                params.startTime,
                params.endTime,
                params.cliffPeriod,
                params.slicePeriod,
                params.amount,
                params.vestingType,
            );

        return params;
    };

    beforeEach(async () => {
        const fixture = await loadFixture(deployVestingContract);

        tokenVesting = fixture.tokenVesting;
        token = fixture.token;
        owner = fixture.owner;
        presale = fixture.presale;
        recipient = fixture.recipient;
        otherAccount = fixture.otherAccount;
    });

    describe("Deployment functionality", function () {
        it("Should set the correct token and owner addresses", async function () {
            expect(await tokenVesting.TOKEN()).to.equal(token.target);
            expect(await tokenVesting.owner()).to.equal(owner.address);
        });

        it("Should correctly set the presale", async function () {
            // Our tests don't require separate presale contract
            // For this test we just need the address of any contract, so we can do that:
            const mockPresaleAddress = token.target;

            await tokenVesting.setPresaleContract(mockPresaleAddress);

            expect(await tokenVesting.presaleContract()).to.be.eq(mockPresaleAddress);
        });

        it("Should prevent set presale If it is not called by the owner", async function () {
            const mockPresaleAddress = token.target;

            await expect(tokenVesting.connect(otherAccount).setPresaleContract(mockPresaleAddress)).to.be.revertedWithCustomError(
                tokenVesting,
                "OwnableUnauthorizedAccount",
            );
        });

        it("Should prevent set presale if it is non-contract address", async function () {
            await expect(tokenVesting.setPresaleContract(ethers.ZeroAddress)).to.be.revertedWithCustomError(
                tokenVesting,
                "PresaleIsNotContract",
            );
        });

        it("Should prevent set presale if it is already set", async function () {
            const mockPresaleAddress = token.target;

            await tokenVesting.setPresaleContract(mockPresaleAddress);
            await expect(tokenVesting.setPresaleContract(mockPresaleAddress)).to.be.revertedWithCustomError(
                tokenVesting,
                "PresaleAlreadySet",
            );
        });

        it("Should prevent deploy with non-contract address for token", async function () {
            const TokenVesting = await ethers.getContractFactory("TokenVesting");
            await expect(TokenVesting.deploy(owner.address, ethers.ZeroAddress)).to.be.revertedWithCustomError(
                tokenVesting,
                "TokenIsNotContract",
            );
        });
    });

    describe("Create vesting functionality", function () {
        it("Should correctly create vesting for user", async function () {
            const vestingParams = await createVesting();

            const vestings = await tokenVesting.getVestings(recipient.address);
            const vestingsCount = await tokenVesting.getVestingsCount(recipient.address);
            const vesting = vestings[0];

            expect(vestings.length).to.be.eq(vestingsCount);
            expect(vesting.startTime).to.be.eq(vestingParams.startTime);
            expect(vesting.endTime).to.be.eq(vestingParams.endTime);
            expect(vesting.cliffTime).eq(vestingParams.startTime + vestingParams.cliffPeriod);
            expect(vesting.slicePeriod).to.be.eq(vestingParams.slicePeriod);
            expect(vesting.amount).to.be.eq(VESTING_AMOUNT);
            expect(vesting.claimed).to.be.eq(0);
            expect(await token.balanceOf(tokenVesting.target)).to.be.eq(VESTING_AMOUNT);
            expect(await token.balanceOf(owner.address)).to.be.eq(INITIAL_SUPPLY - VESTING_AMOUNT);
        });

        it("Should prevent non-owner and non-presale from creating vesting", async function () {
            await expect(createVesting({ sender: otherAccount })).to.be.revertedWithCustomError(tokenVesting, "OnlyOwnerOrPresaleAllowed");
        });

        it("Should prevent create vesting for user with zero address", async function () {
            await expect(createVesting({ recipient: ethers.ZeroAddress })).to.be.revertedWithCustomError(
                tokenVesting,
                "RecipientIsZeroAddress",
            );
        });

        it("Should prevent create vesting if slice period is zero", async function () {
            await expect(createVesting({ slicePeriod: 0 })).to.be.revertedWithCustomError(tokenVesting, "SlicePeriodIsZero");
        });

        it("Should prevent create vesting if start time is zero", async function () {
            await expect(createVesting({ startTime: 0 })).to.be.revertedWithCustomError(tokenVesting, "StartTimeIsZero");
        });

        it("Should prevent create vesting if no tokens to vesting", async function () {
            await expect(createVesting({ amount: 0 })).to.be.revertedWithCustomError(tokenVesting, "NoTokensToVesting");
        });

        it("Should prevent create vesting if end time in past", async function () {
            const startTime = await time.latest();
            await expect(createVesting({ startTime, endTime: startTime - 1 })).to.be.revertedWithCustomError(tokenVesting, "EndTimeInPast");
        });

        it("Should prevent create vesting if end time before start time", async function () {
            const startTime = (await time.latest()) + 24 * 3600; // in 1 day
            await expect(createVesting({ startTime, endTime: startTime - 1 })).to.be.revertedWithCustomError(
                tokenVesting,
                "EndTimeBeforeStartTime",
            );
        });

        it("Should prevent create vesting if cliff and slice period larger than total vesting duration", async function () {
            const cliffPeriod = 30 * 24 * 3600; // 30 days
            await expect(createVesting({ cliffPeriod })).to.be.revertedWithCustomError(tokenVesting, "CliffAndSlicePeriodTooLong");
        });
    });
    describe("Claim tokens functionality", function () {
        it("Should correctly claim all tokens after the end of vesting", async function () {
            const vestingParams = await createVesting();

            await time.increase(vestingParams.endTime);
            await tokenVesting.connect(recipient).claimTokens();

            expect(await token.balanceOf(recipient.address)).to.be.eq(VESTING_AMOUNT);
            expect(await token.balanceOf(tokenVesting.target)).to.be.eq(0);
        });

        it("Should correctly claim tokens if some slices completed", async function () {
            const vestingParams = await createVesting();

            await time.increase(vestingParams.cliffPeriod + vestingParams.slicePeriod + vestingParams.slicePeriod);

            const avaiableAmountToClaim = (VESTING_AMOUNT * 2n) / 5n; // total slices is 5, completed - 2
            const claimableAmount = await tokenVesting.getClaimableAmount(recipient.address);

            await tokenVesting.connect(recipient).claimTokens();
            expect(avaiableAmountToClaim).to.be.eq(claimableAmount);
            expect(await token.balanceOf(recipient.address)).to.be.eq(claimableAmount);
            expect(await token.balanceOf(tokenVesting.target)).to.be.eq(VESTING_AMOUNT - claimableAmount);
        });

        it("Should prevent claim tokens if no tokens to claim", async function () {
            await createVesting();
            const claimableAmount = await tokenVesting.getClaimableAmount(recipient.address);

            expect(claimableAmount).to.be.eq(0);
            await expect(tokenVesting.connect(recipient).claimTokens()).to.be.revertedWithCustomError(tokenVesting, "NoTokensToClaim");
        });
    });
});
