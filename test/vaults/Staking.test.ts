import { Staking, MockERC20, Treasury, VaultFactory, MockQuadata, License, Scoring } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { deployAllContracts, createAndRepayVault } from "../utils.test";
import { loadFixture, mineUpTo, mine } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("GoilStaking", function () {
    let staking: Staking;
    let vaultFactory: VaultFactory;
    let license: License;
    let scoring: Scoring;
    let treasury: Treasury;
    let goilToken: MockERC20;
    let stableToken: MockERC20;
    let qadrataReader: MockQuadata;
    let admin: HardhatEthersSigner;
    let entity: HardhatEthersSigner;
    let user1: HardhatEthersSigner;
    let user2: HardhatEthersSigner;

    beforeEach(async () => {
        const fixture = await loadFixture(deployAllContracts);
        staking = fixture.staking;

        vaultFactory = fixture.vaultFactory;
        license = fixture.license;
        scoring = fixture.scoring;
        treasury = fixture.treasury;
        qadrataReader = fixture.quadata;
        goilToken = fixture.goilToken;
        stableToken = fixture.stableToken;
        admin = fixture.admin;
        entity = fixture.entity;
        user1 = fixture.user1;
        user2 = fixture.user2;
    });

    describe("Deployment Functionality", function () {
        it("Should set correct staking token", async function () {
            expect(await staking.STAKING_TOKEN()).to.equal(goilToken.target);
        });

        it("Should set correct reward token", async function () {
            expect(await staking.REWARD_TOKEN()).to.equal(goilToken.target);
        });

        it("Should set correct treasury", async function () {
            expect(await staking.TREASURY()).to.equal(treasury.target);
        });
    });

    describe("Staking Functionality", function () {
        it("Should set correct staking period", async function () {
            const stakeAmount = ethers.parseEther("100");
            const rewardAmount = ethers.parseEther("110");

            await goilToken.connect(user1).mint(user1.address, stakeAmount);
            await goilToken.connect(user1).approve(staking.target, stakeAmount);
            await staking.connect(user1).stakeTokens(stakeAmount);

            console.log(Number(await staking.getPendingRewardByUser(user1.address)) / 1e18);

            await goilToken.approve(staking.target, rewardAmount);
            await staking.depositReward(rewardAmount);

            const totalReward = await staking.totalReward();
            await mineUpTo(await staking.endStakingBlock() / 2n);
            console.log(Number(await staking.getPendingRewardByUser(user1.address)) / 1e18);

            await goilToken.approve(staking.target, rewardAmount);
            await staking.depositReward(rewardAmount);

            await mineUpTo(await staking.endStakingBlock());
            console.log(Number(await staking.getPendingRewardByUser(user1.address)) / 1e18);


            await staking.connect(user1)["claimReward()"]();
        });
    });
});


