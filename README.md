# Vault Contracts

## Overview

This repository contains Solidity smart contracts for vaults, token sale and token vesting.

## Smart Contracts

1. **VaultFactory**: Deploys vault instances as clones of a single vault implementation (OpenZeppelin `Clones`) and wires each vault with the shared License, Oracle, Scoring, Staking and Treasury contracts. It also tracks deposit tokens and keeps a registry of all deployed vaults.
2. **Vault**: An `ERC4626`-based vault (`Initializable`, deployed as a clone) that accepts deposits from an entity and its depositors, swaps between the deposit token and the protocol token through Uniswap, and interacts with Scoring, Staking and Treasury during its lifecycle.
3. **License**: Handles license applications and approvals for entities, including KYB verification through Quadrata and collecting application and monthly fees.
4. **Treasury**: Holds and manages collateral in the protocol token, tracks borrowed amounts per entity and enforces the required collateral percentage.
5. **Scoring**: Calculates an entity score from token collateral, reputation, financial health and market condition, and keeps a history of past scores.
6. **Staking**: A reward-per-block staking contract for the protocol token, used to distribute part of vault funds to stakers.
7. **Oracle**: Reads the protocol token price from a Uniswap V3 pool using a TWAP over a configurable time window.
8. **TokenSale**: Runs the public sale of the token in rounds, accepting ETH, USDC and USDT, pricing purchases through a Chainlink price feed and forwarding vesting schedules to the vesting contract.
9. **TokenVesting**: Creates and tracks vesting schedules with a cliff and linear release, and lets recipients claim unlocked tokens.

## Technologies Used

- **Solidity**: 0.8.27, with the optimizer and `viaIR` enabled.
- **Hardhat Framework**: development, testing and deployment.
- **OpenZeppelin Contracts**: access control and token standards for the sale and vesting contracts.
- **OpenZeppelin Contracts Upgradeable**: `Initializable` and a bundled `ERC4626Upgradeable` used by the vault clones.
- **Uniswap V2/V3**: swaps inside the vaults and TWAP pricing in the oracle.
- **Chainlink**: price feed used by the token sale.
- **Quadrata**: KYB verification used by the license contract.
- **Unit Tests**: TypeScript tests for the sale, vesting and vault contracts, with coverage via `.solcover.js`.

## Running the Project

1. Clone the repository.
2. Install dependencies using `npm install`.
3. Create a `.env` file from `.env.example` and fill it in.
4. Compile the smart contracts using `npx hardhat compile`.
5. Run tests using `npx hardhat test`.
6. Check coverage using `npx hardhat coverage`.
7. Deploy using `npx hardhat run scripts/deployVaults.ts --network arbitrumSepolia` (or `scripts/deploySale.ts`, `scripts/deployVesting.ts`), with `arbitrumSepolia` or `arbitrum` as the network.
