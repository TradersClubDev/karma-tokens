// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './IBEP20.sol';

interface IToken is IBEP20 {

    struct Taxes {
        uint256 marketing;
        uint256 reflection;
    }

    struct TokenData {
        string name;
        string symbol;
        uint8 decimals;
        uint256 supply;
        uint256 maxTx;
        uint256 maxWallet;
        address routerAddress;
        address karmaDeployer;
        Taxes buyTax;
        Taxes sellTax;
        address marketingWallet;
        address rewardToken;
        address antiBot;
    }

    function initialize(TokenData memory tokenData) external;
}
