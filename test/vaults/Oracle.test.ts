import { Oracle, MockERC20, Treasury, VaultFactory, MockQuadata, License, Scoring, MockPool } from "../../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { deployAllContracts, createAndRepayVault } from "../utils.test";
import { loadFixture, mineUpTo, mine } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe.only("GoilOracle", function () {
	let oracle: Oracle;
	let mockPool: MockPool;
	let vaultFactory: VaultFactory;
	let goilToken: MockERC20;
	let stableToken: MockERC20;

    const goilPrice = ethers.parseEther("1"); // 1 USD
    
	beforeEach(async () => {
		const fixture = await loadFixture(deployAllContracts);
		oracle = fixture.oracle;
		mockPool = fixture.mockPool;
		vaultFactory = fixture.vaultFactory;
		goilToken = fixture.goilToken;
		stableToken = fixture.stableToken;
	});

	describe("Deployment Functionality", function () {
		it("Should set the correct GOIL token", async function () {
			expect(await oracle.GOIL_TOKEN()).to.equal(goilToken.target);
		});

		it("Should set the correct purchase token", async function () {
			expect(await oracle.purchaseToken()).to.equal(stableToken.target);
		});

		it("Should set the correct pool", async function () {
			expect(await oracle.pool()).to.equal(mockPool.target);
		});
	});

	describe("Oracle Functionality", function () {
        it("Should return price per token", async function () {
            const price = await oracle.getPricePerToken();
            expect(price).to.be.equal(goilPrice);
        });

        it("Should calculate payment amount for tokens", async function () {
            const tokenAmount = ethers.parseEther("100");
            const payment = await oracle.getPaymentAmountForTokens(tokenAmount);
            expect(payment).to.be.equal(tokenAmount); // since price is 1 USD per token
        });

        it("Should calculate token amount for payment", async function () {
            const paymentAmount = ethers.parseEther("100");
            const tokens = await oracle.getTokenAmountForPayment(paymentAmount);
            expect(tokens).to.be.equal(paymentAmount); // since price is 1 USD per token
        });
    });
});
