// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILevvaVaultFactory {
    function isLevvaVault(address levvaVault) external view returns (bool);
}
