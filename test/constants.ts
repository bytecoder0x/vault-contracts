import { ethers } from "hardhat";

// constants for testing
export const COLLATERAL_AMOUNT = ethers.parseEther("10000");
export const INITIAL_SUPPLY = ethers.parseEther("10000000");

export const APPLICATION_FEE = ethers.parseEther("1000");
export const LICENSE_MONTHLY_FEE = ethers.parseEther("100");

export const VOTING_PERIOD = 7 * 24 * 3600;

// threshold collateral is used for calculating collateral ratio that is used for calculating initial score
export const THRESHOLD_COLLATERAL = ethers.parseEther("10000");
// threshold capital is used for calculating max pool size
export const THRESHOLD_CAPITAL = ethers.parseEther("1000000");
export const MARKET_CONDITION_RATIO = 100_000;

export const AMOUNT_FOR_ROUTER = ethers.parseEther("100000000");
