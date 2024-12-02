import { ethers } from "hardhat";
import { expect } from "chai";
import { License, MockERC20, MockQuadata, MockTreasury } from "../typechain-types";
import { HardhatEthersSigner } from "@nomicfoundation/hardhat-ethers/signers";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { time } from "@nomicfoundation/hardhat-network-helpers";

describe("License", function () {
    let license: License;
    let goilToken: MockERC20;
    let qadrataReader: MockQuadata; 
    let treasury: MockTreasury;
    let admin: HardhatEthersSigner;
    let manager: HardhatEthersSigner;
    let applicant: HardhatEthersSigner;
    let voter: HardhatEthersSigner;
    let otherAccount: HardhatEthersSigner;

    const INITIAL_SUPPLY = ethers.parseEther("1000000");
    const APPLICATION_FEE = ethers.parseEther("100");
    const LICENSE_MONTHLY_FEE = ethers.parseEther("50");
    const VOTING_PERIOD = 7 * 24 * 3600;
    const LICENSE_EXPIRATION_LIMIT = 365 * 24 * 3600;

    const deployLicenseFixture = async () => {
        const [admin, manager, applicant, voter, otherAccount] = await ethers.getSigners();

        const MockERC20 = await ethers.getContractFactory("MockERC20");
        const goilToken = await MockERC20.deploy(INITIAL_SUPPLY);
        await goilToken.waitForDeployment();

        const MockQuadReader = await ethers.getContractFactory("MockQuadata");
        const qadrataReader = await MockQuadReader.deploy();
        await qadrataReader.waitForDeployment();

        const MockTreasury = await ethers.getContractFactory("MockTreasury");
        const treasury = await MockTreasury.deploy();
        await treasury.waitForDeployment();

        const License = await ethers.getContractFactory("License");
        const license = await License.deploy(
            admin.address,
            qadrataReader.target,
            goilToken.target,
            treasury.target,
            APPLICATION_FEE,
            LICENSE_MONTHLY_FEE
        );
        await license.waitForDeployment();

        return { license, goilToken, qadrataReader, admin, manager, treasury, applicant, voter, otherAccount };
    };

    const submitLicense = async(licenseEndTime: bigint) =>{
        await qadrataReader.connect(applicant).mint(applicant.address, 1n);
        await goilToken.connect(applicant).mint(applicant.address, ethers.parseEther("3000"));
        await goilToken.connect(applicant).approve(license.target, ethers.parseEther("3000"));
        await license.connect(applicant).submitLicense(licenseEndTime);
    }

    beforeEach(async () => {
        const fixture = await loadFixture(deployLicenseFixture);
        license = fixture.license;
        goilToken = fixture.goilToken;
        qadrataReader = fixture.qadrataReader;
        admin = fixture.admin;
        manager = fixture.manager;
        treasury = fixture.treasury;
        applicant = fixture.applicant;
        voter = fixture.voter;
        otherAccount = fixture.otherAccount;

        // Grant MANAGER_ROLE to manager
        const MANAGER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE"));
        await license.connect(admin).grantRole(MANAGER_ROLE, manager.address);
    });

    describe("Deployment Functionality", function () {
        it("Should set correct quadrata reader contract", async function () {
            expect(await license.QADRATA_READER()).to.equal(qadrataReader.target);
        });

        it("Should set correct goil token contract", async function () {
            expect(await license.GOIL_TOKEN()).to.equal(goilToken.target);
        });

        it("Should set correct treasury contract", async function () {
            expect(await license.TREASURY()).to.equal(treasury.target);
        });

        it("Should set correct application fee", async function () {
            expect(await license.applicationFee()).to.equal(APPLICATION_FEE);
        });

        it("Should set correct license monthly fee", async function () {
            expect(await license.licenseMonthlyFee()).to.equal(LICENSE_MONTHLY_FEE);
        });

        it("Should set correct required votes threshold", async function () {
            const requiredVotesThreshold = BigInt((await goilToken.totalSupply()) * 66_00n / 100_00n);
            expect(await license.requiredVotesThreshold()).to.equal(requiredVotesThreshold);
        });

        it("Should set correct voting period", async function () {
            expect(await license.votingPeriod()).to.equal(7 * 24 * 3600);
        });

        it("Should set correct license expiration limit", async function () {
            expect(await license.licenseExpirationLimit()).to.equal(365 * 24 * 3600);
        });

        it("Should revert when admin address is zero", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    ethers.ZeroAddress,
                    qadrataReader.target,
                    goilToken.target,
                    treasury.target,
                    APPLICATION_FEE,
                    LICENSE_MONTHLY_FEE
                )
            ).to.be.revertedWithCustomError(license, "AdminAddressCannotBeZero");
        });

        it("Should revert when Qadrata Reader address is not a contract", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    ethers.ZeroAddress,
                    goilToken.target,
                    treasury.target,
                    APPLICATION_FEE,
                    LICENSE_MONTHLY_FEE
                )
            ).to.be.revertedWithCustomError(license, "QadrataAddressMustBeContract");
        });

        it("Should revert when GOIL Token address is not a contract", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    qadrataReader.target,
                    ethers.ZeroAddress,
                    treasury.target,
                    APPLICATION_FEE,
                    LICENSE_MONTHLY_FEE
                )
            ).to.be.revertedWithCustomError(license, "GOILTokenAddressMustBeContract");
        });

        it("Should revert when Treasury address is not a contract", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    qadrataReader.target,
                    goilToken.target,
                    ethers.ZeroAddress,
                    APPLICATION_FEE,
                    LICENSE_MONTHLY_FEE
                )
            ).to.be.revertedWithCustomError(license, "TreasuryAddressMustBeContract");
        });

        it("Should revert when application fee is zero", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    qadrataReader.target,
                    goilToken.target,
                    treasury.target,
                    0,
                    LICENSE_MONTHLY_FEE
                )
            ).to.be.revertedWithCustomError(license, "FeesCannotBeZero");
        });

        it("Should revert when license monthly fee is zero", async function () {
            const LicenseFactory = await ethers.getContractFactory("License");
            await expect(
                LicenseFactory.deploy(
                    admin.address,
                    qadrataReader.target,
                    goilToken.target,
                    treasury.target,
                    APPLICATION_FEE,
                    0
                )
            ).to.be.revertedWithCustomError(license, "FeesCannotBeZero");
        });
    });

    describe("License Submission Functionality", function () {
        it("Should successfully submit a license", async function () {
            await qadrataReader.connect(applicant).mint(applicant.address, 1n);
            await goilToken.connect(applicant).mint(applicant.address, ethers.parseEther("3000"));
            await goilToken.connect(applicant).approve(license.target, ethers.parseEther("3000"));

            const licenseStartTime = BigInt(await time.latest()) + BigInt(VOTING_PERIOD) + 1n;
            const licenseEndTime = licenseStartTime + (365n * 24n * 3600n);

            await expect(license.connect(applicant).submitLicense(licenseEndTime))
                .to.emit(license, "AppliedForLicense")
                .withArgs(applicant.address, 1, licenseStartTime, licenseEndTime);

            const licenseInfo = await license.licenses(applicant.address, 1);
            expect(licenseInfo.startTime).to.equal(licenseStartTime);
            expect(licenseInfo.endTime).to.equal(licenseEndTime);
            expect(licenseInfo.approved).to.equal(false);
            expect(await license.getLicenseVotingPercentage(applicant.address)).to.equal(0);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(APPLICATION_FEE);
            expect(await goilToken.balanceOf(license.target)).to.equal(LICENSE_MONTHLY_FEE * 12n);
        });

        it("Should successfully submit a license if previous license is rejected", async function () {
            const numberOfVotes = ethers.parseEther("100");

            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); 
            await submitLicense(licenseEndTime);
            
            await goilToken.connect(voter).mint(voter.address, numberOfVotes);
            await license.connect(voter).vote(applicant.address);

            await time.increase(10 * 24 * 3600); // 10 days
            expect(await license.getLicenseIsActive(applicant.address)).to.equal(false); 
            expect(await license.getLicenseStatus(applicant.address)).to.equal(2); // REJECTED

            const newLicenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(newLicenseEndTime);

            const licenseInfo = await license.licenses(applicant.address, 2);
            expect(licenseInfo.endTime).to.equal(newLicenseEndTime);
            expect(licenseInfo.approved).to.equal(false);
            expect(await license.getLicenseVotingPercentage(applicant.address)).to.equal(0);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(APPLICATION_FEE * 2n);
            expect(await goilToken.balanceOf(license.target)).to.equal(LICENSE_MONTHLY_FEE * 12n * 2n);
        });

        it("Should successfully submit a license if previous license is expired", async function () {
            const numberOfVotes = ethers.parseEther("100");

            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); 
            await submitLicense(licenseEndTime);
            
            await goilToken.connect(voter).mint(voter.address, numberOfVotes);
            await license.connect(voter).vote(applicant.address);

            await time.increase((365n * 24n * 3600n) + BigInt(VOTING_PERIOD)); // 1 year
            expect(await license.getLicenseIsActive(applicant.address)).to.equal(false); 
            expect(await license.getLicenseStatus(applicant.address)).to.equal(4); // EXPIRED

            const newLicenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(newLicenseEndTime);

            const licenseInfo = await license.licenses(applicant.address, 2);
            expect(licenseInfo.endTime).to.equal(newLicenseEndTime);
            expect(licenseInfo.approved).to.equal(false);
            expect(await license.getLicenseVotingPercentage(applicant.address)).to.equal(0);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(APPLICATION_FEE * 2n);
            expect(await goilToken.balanceOf(license.target)).to.equal(LICENSE_MONTHLY_FEE * 12n * 2n);
        });

        it("Should revert if applicant doesn't have the required KYB", async function () {
            // Applicant doesn't have KYB
            await goilToken.connect(applicant).mint(applicant.address, ethers.parseEther("1000"));
            await goilToken.connect(applicant).approve(license.target, APPLICATION_FEE + LICENSE_MONTHLY_FEE);

            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 1 year

            await expect(
                license.connect(applicant).submitLicense(licenseEndTime)
            ).to.be.revertedWithCustomError(license, "ApplicantMustHaveQadrataKYB");
        });

        it("Should revert if license period is too short", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (15n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 15 days

            await expect(submitLicense(licenseEndTime)).to.be.revertedWithCustomError(license, "LicensePeriodTooShort");
        });

        it("Should revert if license period is too long", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (400n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 400 days

            await expect(submitLicense(licenseEndTime)).to.be.revertedWithCustomError(license, "LicensePeriodTooLong");
        });

        it("Should revert if license is already submitted", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 1 year
            await submitLicense(licenseEndTime)

            await expect(submitLicense(licenseEndTime)).to.be.revertedWithCustomError(license, "LicenseAlreadySubmitted");

            const numberOfVotes = ethers.parseEther("700000"); // 70% of the total supply
            await goilToken.connect(voter).mint(voter.address, numberOfVotes);
            await license.connect(voter).vote(applicant.address);
            expect(await license.getLicenseStatus(applicant.address)).to.equal(3); // ACTIVE

            await expect(submitLicense(licenseEndTime)).to.be.revertedWithCustomError(license, "LicenseAlreadySubmitted");
        });
    });

    describe("Voting Functionality", function () {
        it("Should successfully approve a license when votes threshold is reached", async function () {
            const numberOfVotes = ethers.parseEther("700000"); // 70% of the total supply

            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD); // 1 year 
            await submitLicense(licenseEndTime);
            
            await goilToken.connect(voter).mint(voter.address, numberOfVotes);
            await expect(license.connect(voter).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter.address, 1, numberOfVotes);

            const licenseStatus = await license.getLicenseStatus(applicant.address);
            expect(licenseStatus).to.equal(3); // ACTIVE

            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter.address)).to.equal(numberOfVotes);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(APPLICATION_FEE + LICENSE_MONTHLY_FEE * 12n);
            expect(await goilToken.balanceOf(license.target)).to.equal(0);
        });

        it("Should successfully approve license when reach threshold with multiple voters", async function () {
            const voter1Votes = ethers.parseEther("200000"); // 20% of supply
            const voter2Votes = ethers.parseEther("150000"); // 15% of supply
            const voter3Votes = ethers.parseEther("250000"); // 25% of supply
            const voter4Votes = ethers.parseEther("100000"); // 10% of supply
            // Total 70% > threshold
    
            const [, , , , , voter1, voter2, voter3, voter4] = await ethers.getSigners();
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime);
    
            // First voter
            await goilToken.connect(voter1).mint(voter1.address, voter1Votes);
            await expect(license.connect(voter1).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter1.address, 1, voter1Votes);
    
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // Still PENDING
            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter1.address)).to.equal(voter1Votes);
    
            // Second voter
            await goilToken.connect(voter2).mint(voter2.address, voter2Votes);
            await expect(license.connect(voter2).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter2.address, 1, voter2Votes);
    
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // Still PENDING
            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter2.address)).to.equal(voter2Votes);
    
            // Third voter
            await goilToken.connect(voter3).mint(voter3.address, voter3Votes);
            await expect(license.connect(voter3).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter3.address, 1, voter3Votes);
    
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // Still PENDING
            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter3.address)).to.equal(voter3Votes);
    
            // Fourth voter - after this vote threshold should be reached
            await goilToken.connect(voter4).mint(voter4.address, voter4Votes);
            await expect(license.connect(voter4).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter4.address, 1, voter4Votes);
    
            // After fourth vote should be approved
            expect(await license.getLicenseStatus(applicant.address)).to.equal(3); // ACTIVE
            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter4.address)).to.equal(voter4Votes);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(APPLICATION_FEE + LICENSE_MONTHLY_FEE * 12n);
            expect(await goilToken.balanceOf(license.target)).to.equal(0);
        });

        it("Should not approve license when reach threshold with multiple voters", async function () {
            const voter1Votes = ethers.parseEther("150000"); // 15% of supply
            const voter2Votes = ethers.parseEther("100000"); // 10% of supply
            const voter3Votes = ethers.parseEther("200000"); // 20% of supply
            const voter4Votes = ethers.parseEther("100000"); // 10% of supply
            // Total 55% < threshold
    
            const [, , , , , voter1, voter2, voter3, voter4] = await ethers.getSigners();
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime);
    
            // First voter
            await goilToken.connect(voter1).mint(voter1.address, voter1Votes);
            await expect(license.connect(voter1).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter1.address, 1, voter1Votes);
    
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // PENDING
            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter1.address)).to.equal(voter1Votes);
    
            // Second voter
            await goilToken.connect(voter2).mint(voter2.address, voter2Votes);
            await expect(license.connect(voter2).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter2.address, 1, voter2Votes);
    
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // PENDING
            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter2.address)).to.equal(voter2Votes);
    
            // Third voter
            await goilToken.connect(voter3).mint(voter3.address, voter3Votes);
            await expect(license.connect(voter3).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter3.address, 1, voter3Votes);
    
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // PENDING
            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter3.address)).to.equal(voter3Votes);
    
            // Fourth voter
            await goilToken.connect(voter4).mint(voter4.address, voter4Votes);
            await expect(license.connect(voter4).vote(applicant.address))
                .to.emit(license, "Voted")
                .withArgs(applicant.address, voter4.address, 1, voter4Votes);
    
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // Still PENDING
            expect(await license.getLicenseVotesByUser(applicant.address, 1, voter4.address)).to.equal(voter4Votes);
    
            // After voting period ends should be rejected
            await time.increase(VOTING_PERIOD + 1);
            expect(await license.getLicenseStatus(applicant.address)).to.equal(2); // REJECTED
            
            // Check final balances - should be able to refund license fee
            const balanceBeforeRefund = await goilToken.balanceOf(applicant.address);
            await license.connect(applicant).refundLicenseFee();
            expect(await goilToken.balanceOf(applicant.address)).to.equal(balanceBeforeRefund + LICENSE_MONTHLY_FEE * 12n);
            expect(await goilToken.balanceOf(treasury.target)).to.equal(APPLICATION_FEE);
            expect(await goilToken.balanceOf(license.target)).to.equal(0);
        });

        it("Should revert if voter has no GOIL tokens", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime)

            await expect(
                license.connect(otherAccount).vote(applicant.address)
            ).to.be.revertedWithCustomError(license, "NoGOILTokensToVote");
        });

        it("Should revert if license is not in PENDING state", async function () {
            const numberOfVotes = ethers.parseEther("700000"); // 70% of the total supply

            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime)

            await goilToken.connect(otherAccount).mint(otherAccount.address, ethers.parseEther("1000"));
            await goilToken.connect(voter).mint(voter.address, numberOfVotes);
            await license.connect(voter).vote(applicant.address);

            await expect(
                license.connect(otherAccount).vote(applicant.address)
            ).to.be.revertedWithCustomError(license, "LicenseIsNotPending");
        });

        it("Should revert if voter has already voted", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime)

            await goilToken.connect(voter).mint(voter.address, ethers.parseEther("500"));
            await license.connect(voter).vote(applicant.address);

            await expect(
                license.connect(voter).vote(applicant.address)
            ).to.be.revertedWithCustomError(license, "AlreadyVoted");
        });
    });

    describe("Refund Functionality", function () {
        it("Should successfully refund license fees", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime)
            const balanceBeforeRefund = await goilToken.balanceOf(applicant.address);

            // Increase time to allow refund
            await time.increase(10 * 24 * 3600); // 10 days

            await expect(license.connect(applicant).refundLicenseFee())
                .to.emit(license, "RefundedLicenseFee")
                .withArgs(applicant.address, LICENSE_MONTHLY_FEE * 12n);

            expect(await goilToken.balanceOf(applicant.address)).to.equal(balanceBeforeRefund + LICENSE_MONTHLY_FEE * 12n);
            expect(await goilToken.balanceOf(license.target)).to.equal(0);
        });

        it("Should correctly refund license fees if applicant applied and has pending license", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime);

            // Increase time to allow refund
            await time.increase(10 * 24 * 3600); // 10 days

            expect(await license.getLicenseStatus(applicant.address)).to.equal(2); // REJECTED

            const newLicenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await license.connect(applicant).submitLicense(newLicenseEndTime);
            const balanceBeforeRefund = await goilToken.balanceOf(applicant.address);

            await expect(license.connect(applicant).refundLicenseFee())
                .to.emit(license, "RefundedLicenseFee")
                .withArgs(applicant.address, LICENSE_MONTHLY_FEE * 12n);

            expect(await goilToken.balanceOf(applicant.address)).to.equal(balanceBeforeRefund + LICENSE_MONTHLY_FEE * 12n);
            expect(await goilToken.balanceOf(license.target)).to.equal(LICENSE_MONTHLY_FEE * 12n);
        });

        it("Should revert if there are no fees to refund", async function () {
            await expect(
                license.connect(applicant).refundLicenseFee()
            ).to.be.revertedWithCustomError(license, "NoLicenseFeeToRefund");
        });
    });

    describe("Administrative Functionality", function () {
        it("Should allow manager to change application fee", async function () {
            await expect(
                license.connect(manager).setApplicationFee(ethers.parseEther("200"))
            )
                .to.emit(license, "ApplicationFeeUpdated")
                .withArgs(ethers.parseEther("200"));

            expect(await license.applicationFee()).to.equal(ethers.parseEther("200"));
        });

        it("Should allow manager to change monthly license fee", async function () {
            await expect(
                license.connect(manager).setLicenseMonthlyFee(ethers.parseEther("60"))
            )
                .to.emit(license, "LicenseMonthlyFeeUpdated")
                .withArgs(ethers.parseEther("60"));

            expect(await license.licenseMonthlyFee()).to.equal(ethers.parseEther("60"));
        });

        it("Should allow manager to change required votes percentage", async function () {
            await expect(
                license.connect(manager).setRequiredVotesPercentage(7000)
            )
                .to.emit(license, "RequiredVotesPercentageUpdated")
                .withArgs(7000);

            expect(await license.requiredVotesPercentage()).to.equal(7000);
        });

        it("Should allow manager to change voting period", async function () {
            const newVotingPeriod = 10 * 24 * 3600; // 10 days

            await expect(
                license.connect(manager).setVotingPeriod(newVotingPeriod)
            )
                .to.emit(license, "VotingPeriodUpdated")
                .withArgs(newVotingPeriod);

            expect(await license.votingPeriod()).to.equal(newVotingPeriod);
        });

        it("Should allow manager to change exipation limit for license", async function () {
            const newExpirationLimit = 500 * 24 * 3600; // 500 days

            await expect(
                license.connect(manager).setLicenseExpirationLimit(newExpirationLimit)
            )
                .to.emit(license, "LicenseExpirationLimitUpdated")
                .withArgs(newExpirationLimit);

            expect(await license.licenseExpirationLimit()).to.equal(newExpirationLimit);
        });

        it("Should revert set fee if its the same", async function () {
            const currentApplicationFee = await license.applicationFee();

            await expect(
                license.connect(manager).setApplicationFee(currentApplicationFee)
            ).to.be.revertedWithCustomError(license, "FeeCannotBeTheSame")

            const currentMothlyLicenseFee = await license.licenseMonthlyFee();

            await expect(
                license.connect(manager).setLicenseMonthlyFee(currentMothlyLicenseFee)
            ).to.be.revertedWithCustomError(license, "FeeCannotBeTheSame")
        });

        it("Should revert set required votes percentage if its the same or incorrect", async function () {
            const currentRequiredVotesPercentage = await license.requiredVotesPercentage();

            await expect(
                license.connect(manager).setRequiredVotesPercentage(currentRequiredVotesPercentage)
            ).to.be.revertedWithCustomError(license, "PercentageCannotBeTheSame");

            await expect(
                license.connect(manager).setRequiredVotesPercentage(100_01)
            ).to.be.revertedWithCustomError(license, "InvalidPercentage");

            await expect(
                license.connect(manager).setRequiredVotesPercentage(0)
            ).to.be.revertedWithCustomError(license, "InvalidPercentage")
        });

        it("Should revert set voting period if its the same or zero", async function () {
            const currentRequiredVotingPeriod = await license.votingPeriod();

            await expect(
                license.connect(manager).setVotingPeriod(currentRequiredVotingPeriod)
            ).to.be.revertedWithCustomError(license, "VotingPeriodCannotBeTheSame");

            await expect(
                license.connect(manager).setVotingPeriod(0)
            ).to.be.revertedWithCustomError(license, "VotingPeriodCannotBeZero");
        });

        it("Should revert set expiration limit for license if its the same or zero", async function () {
            const currentLicenseExpirationLimit = await license.licenseExpirationLimit();

            await expect(
                license.connect(manager).setLicenseExpirationLimit(currentLicenseExpirationLimit)
            ).to.be.revertedWithCustomError(license, "LicenseExpirationLimitCannotBeTheSame");

            await expect(
                license.connect(manager).setLicenseExpirationLimit(0)
            ).to.be.revertedWithCustomError(license, "LicenseExpirationLimitCannotBeZero");
        });

        it("Should revert if non-manager tries to change parameters", async function () {
            await expect(
                license.connect(otherAccount).setApplicationFee(ethers.parseEther("200"))
            ).to.be.revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));

            await expect(
                license.connect(otherAccount).setLicenseMonthlyFee(ethers.parseEther("60"))
            ).to.be.revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));

            await expect(
                license.connect(otherAccount).setRequiredVotesPercentage(7000)
            ).revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));
            
            await expect(
                license.connect(otherAccount).setVotingPeriod(10 * 24 * 3600)
            ).revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));

            await expect(
                license.connect(otherAccount).setLicenseExpirationLimit(500 * 24 * 3600)
            ).revertedWithCustomError(license, "AccessControlUnauthorizedAccount")
                .withArgs(otherAccount.address, ethers.keccak256(ethers.toUtf8Bytes("MANAGER_ROLE")));
        });
    });

    describe("License Information Retrieval Functionality", function () {
        it("Should return the correct license status", async function () {
            const numberOfVotes = ethers.parseEther("700000"); // 70% of the total supply

            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);

            expect(await license.getLicenseStatus(applicant.address)).to.equal(0); // UNINITIALIZED

            await submitLicense(licenseEndTime);
            expect(await license.getLicenseStatus(applicant.address)).to.equal(1); // PENDING

            await goilToken.connect(voter).mint(voter.address, numberOfVotes);
            await license.connect(voter).vote(applicant.address);
            expect(await license.getLicenseIsActive(applicant.address)).to.equal(true);
            expect(await license.getLicenseStatus(applicant.address)).to.equal(3); // ACTIVE

            await time.increase(500n * 24n * 3600n); // 500 days
            expect(await license.getLicenseStatus(applicant.address)).to.equal(4); // EXPIRED
            expect(await license.getLicenseIsActive(applicant.address)).to.equal(false);
        });

        it("Should return the correct license details by address", async function () {
            const licenseEndTime = BigInt(await time.latest()) + (365n * 24n * 3600n) + BigInt(VOTING_PERIOD);
            await submitLicense(licenseEndTime)

            const [startTime, endTime, approved] = await license.getLicenseByEntity(applicant.address);
            expect(startTime).to.equal(BigInt(await time.latest()) + 7n * 24n * 3600n);
            expect(endTime).to.equal(licenseEndTime);
            expect(approved).to.equal(false);
        });
    });
});