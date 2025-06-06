// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {IRequestWithdrawalVault} from "../../interfaces/IRequestWithdrawalVault.sol";
import {IWithdrawalQueue} from "../../interfaces/IWithdrawalQueue.sol";
import {ILevvaVaultFactory} from "../../interfaces/ILevvaVaultFactory.sol";
import {IMultiAssetVault} from "../../interfaces/IMultiAssetVault.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";

/// @title Adapter for interaction with Levva vaults
contract LevvaVaultAdapter is AdapterBase, ERC721Holder, IExternalPositionAdapter {
    using Asserts for address;
    using SafeERC20 for IERC20;

    bytes4 public constant getAdapterId = bytes4(keccak256("LevvaVaultAdapter"));
    ILevvaVaultFactory private immutable i_levvaVaultFactory;

    struct VaultWithdrawals {
        uint256 shares;
        uint256 vaultPosition; // index = vaultPosition - 1;
    }

    struct PendingWithdrawals {
        address[] vaults;
        mapping(address vault => VaultWithdrawals) vaultWithdrawals;
        mapping(uint256 requestId => bool) pendingRequests; // track owner of requestIds
    }

    mapping(address owner => PendingWithdrawals) private s_pendingWithdrawals;

    event RequestWithdrawal(address indexed vault, uint256 indexed requestId, uint256 shares);
    event ClaimWithdrawal(address indexed vault, uint256 indexed requestId, uint256 assets);

    error LevvaVaultAdapter__Forbidden();
    error LevvaVaultAdapter__UnknownVault();
    error LevvaVaultAdapter__ClaimUnauthorized();

    constructor(address levvaVaultFactory) {
        levvaVaultFactory.assertNotZeroAddress();
        i_levvaVaultFactory = ILevvaVaultFactory(levvaVaultFactory);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IExternalPositionAdapter).interfaceId;
    }

    /// @notice Deposits assets into the levva vault
    /// @param vault Address of levva vault
    /// @param assets Amount of assets to deposit
    /// @return shares Amount of shares
    function deposit(address vault, uint256 assets) external returns (uint256 shares) {
        shares = _deposit(vault, IERC4626(vault).asset(), assets);
    }

    /// @notice Deposits assets into the levva vault all except given amount
    /// @param vault Address of levva vault
    /// @param except Amount of assets to be left after deposit
    /// @return shares Amount of shares
    function depositAllExcept(address vault, uint256 except) external returns (uint256 shares) {
        address asset = IERC4626(vault).asset();
        uint256 amount = IERC20(asset).balanceOf(msg.sender) - except;
        shares = _deposit(vault, asset, amount);
    }

    /// @notice Requests redeem
    /// @param vault Address of vault
    /// @param shares Amount of shares to redeem
    /// @return requestId id of the withdrawal request
    function requestRedeem(address vault, uint256 shares) external returns (uint256 requestId) {
        requestId = _requestRedeem(vault, shares);
    }

    /// @notice Requests redeem all amount of shares except given amount
    /// @param vault Address of vault
    /// @param except Amount of shares to be left
    /// @return requestId id of the withdrawal request
    function requestRedeemAllExcept(address vault, uint256 except) external returns (uint256 requestId) {
        uint256 shares = IERC20(vault).balanceOf(msg.sender) - except;
        requestId = _requestRedeem(vault, shares);
    }

    /// @notice Claims withdrawal
    /// @param vault Address of vault
    /// @param requestId Id of the withdrawal request
    /// @return assets Amount of assets
    function claimWithdrawal(address vault, uint256 requestId) external returns (uint256 assets) {
        _ensureIsLevvaVault(vault);

        address withdrawalQueue = IRequestWithdrawalVault(vault).withdrawalQueue();
        uint256 shares = IWithdrawalQueue(withdrawalQueue).getRequestedShares(requestId);

        _removeWithdrawalRequest(msg.sender, vault, requestId, shares);

        assets = IWithdrawalQueue(withdrawalQueue).claimWithdrawal(requestId, msg.sender);

        emit ClaimWithdrawal(vault, requestId, assets);
    }

    /// @notice Checks if claim is possible
    function claimPossible(address vault, uint256 requestId) external view returns (bool) {
        address withdrawalQueue = IRequestWithdrawalVault(vault).withdrawalQueue();
        return IWithdrawalQueue(withdrawalQueue).lastFinalizedRequestId() >= requestId
            && IWithdrawalQueue(withdrawalQueue).getRequestedShares(requestId) != 0;
    }

    /// @notice Returns not zero when there are pending withdrawals
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        return getManagedAssets(msg.sender);
    }

    function getManagedAssets(address owner) public view returns (address[] memory assets, uint256[] memory amounts) {
        PendingWithdrawals storage pendingWithdrawals = s_pendingWithdrawals[owner];

        uint256 vaultLength = pendingWithdrawals.vaults.length;
        if (vaultLength == 0) {
            return (assets, amounts);
        }

        assets = new address[](vaultLength);
        amounts = new uint256[](vaultLength);
        for (uint256 i; i < vaultLength;) {
            address vault = pendingWithdrawals.vaults[i];
            assets[i] = vault;
            amounts[i] = pendingWithdrawals.vaultWithdrawals[vault].shares;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns zero for this adapter
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function _deposit(address vault, address asset, uint256 assets) private returns (uint256 shares) {
        _ensureIsLevvaVault(vault);
        _ensureNoCircularDependencies(msg.sender, vault);

        if (msg.sender == vault) revert LevvaVaultAdapter__Forbidden();

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, assets);

        IERC20(asset).forceApprove(vault, assets);
        shares = IERC4626(vault).deposit(assets, msg.sender);
    }

    function _ensureIsLevvaVault(address vault) private view {
        if (!i_levvaVaultFactory.isLevvaVault(vault)) revert LevvaVaultAdapter__UnknownVault();
    }

    function _ensureNoCircularDependencies(address owner, address vault) private view {
        if (IMultiAssetVault(vault).trackedAssetPosition(owner) != 0) revert LevvaVaultAdapter__Forbidden();
    }

    function _requestRedeem(address vault, uint256 shares) private returns (uint256 requestId) {
        _ensureIsLevvaVault(vault);

        IAdapterCallback(msg.sender).adapterCallback(address(this), vault, shares);
        requestId = IRequestWithdrawalVault(vault).requestRedeem(shares);
        _addWithdrawalRequest(msg.sender, vault, requestId, shares);
        emit RequestWithdrawal(vault, requestId, shares);
    }

    function _addWithdrawalRequest(address owner, address vault, uint256 requestId, uint256 shares) private {
        PendingWithdrawals storage pendingWithdrawals = s_pendingWithdrawals[owner];

        VaultWithdrawals memory vaultWithdrawals = pendingWithdrawals.vaultWithdrawals[vault];
        vaultWithdrawals.shares += shares;

        if (vaultWithdrawals.vaultPosition == 0) {
            pendingWithdrawals.vaults.push(vault);
            vaultWithdrawals.vaultPosition = pendingWithdrawals.vaults.length;
        }

        pendingWithdrawals.vaultWithdrawals[vault] = vaultWithdrawals;
        pendingWithdrawals.pendingRequests[requestId] = true;
    }

    function _removeWithdrawalRequest(address owner, address vault, uint256 requestId, uint256 shares) private {
        PendingWithdrawals storage pendingWithdrawals = s_pendingWithdrawals[owner];

        VaultWithdrawals memory vaultWithdrawals = pendingWithdrawals.vaultWithdrawals[vault];
        if (vaultWithdrawals.vaultPosition == 0) {
            return;
        }

        if (!pendingWithdrawals.pendingRequests[requestId]) {
            revert LevvaVaultAdapter__ClaimUnauthorized();
        }
        delete pendingWithdrawals.pendingRequests[requestId];

        vaultWithdrawals.shares -= shares;

        if (vaultWithdrawals.shares == 0) {
            uint256 vaultIndex = vaultWithdrawals.vaultPosition - 1;
            uint256 vaultLastIndex = pendingWithdrawals.vaults.length - 1;

            if (vaultIndex != vaultLastIndex) {
                pendingWithdrawals.vaults[vaultIndex] = pendingWithdrawals.vaults[vaultLastIndex];
            }

            pendingWithdrawals.vaults.pop();
            delete pendingWithdrawals.vaultWithdrawals[vault];
        }
    }
}
