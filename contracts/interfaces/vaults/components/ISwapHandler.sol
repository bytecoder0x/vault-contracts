// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

interface ISwapHandler {
    enum Swap {
        V2,
        V3_500,
        V3_3000,
        V3_10000
    }

    error RouterV2MustBeContract();
    error RouterV3MustBeContract();
    error QuoterMustBeContract();
}