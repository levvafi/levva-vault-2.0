// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {IWithdrawalQueue} from "../../interfaces/IWithdrawalQueue.sol";
import {ILevvaVaultFactory} from "../../interfaces/ILevvaVaultFactory.sol";
import {ILevvaVault} from "../../interfaces/ILevvaVault.sol";
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
        mapping(uint256 requestId => bool) pendingRequests; // track owner of requestIds
    }

    struct PendingWithdrawals {
        address[] vaults;
        mapping(address vault => VaultWithdrawals) vaultWithdrawals;
    }

    mapping(address owner => PendingWithdrawals) private s_pendingWithdrawals;

    event LevvaVaultRequestWithdrawal(
        address indexed vault, address indexed target, uint256 indexed requestId, uint256 shares
    );
    event LevvaVaultClaimWithdrawal(
        address indexed vault, address indexed target, uint256 indexed requestId, uint256 assets
    );

    error LevvaVaultAdapter__Forbidden();
    error LevvaVaultAdapter__UnknownVault();
    error LevvaVaultAdapter__ClaimUnauthorized();
    error LevvaVaultAdapter__NoRequestId();

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

        address withdrawalQueue = ILevvaVault(vault).withdrawalQueue();
        uint256 shares = IWithdrawalQueue(withdrawalQueue).getRequestedShares(requestId);

        _removeWithdrawalRequest(msg.sender, vault, requestId, shares);

        assets = IWithdrawalQueue(withdrawalQueue).claimWithdrawal(requestId, msg.sender);

        emit LevvaVaultClaimWithdrawal(msg.sender, vault, requestId, assets);
    }

    /// @notice Checks if claim is possible.
    /// @dev Check request finalized and belongs to this adapter
    function claimPossible(address vault, uint256 requestId) external view returns (bool) {
        address withdrawalQueue = ILevvaVault(vault).withdrawalQueue();
        return IWithdrawalQueue(withdrawalQueue).lastFinalizedRequestId() >= requestId
            && IWithdrawalQueue(withdrawalQueue).ownerOf(requestId) == address(this);
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

    function getLevvaVaultFactory() external view returns (address) {
        return address(i_levvaVaultFactory);
    }

    function getPendingWithdrawalsVaults(address owner) external view returns (address[] memory) {
        return s_pendingWithdrawals[owner].vaults;
    }

    function getPendingWithdrawalsVaultPosition(address owner, address vault) external view returns (uint256) {
        return s_pendingWithdrawals[owner].vaultWithdrawals[vault].vaultPosition;
    }

    function getPendingWithdrawalsShares(address owner, address vault) external view returns (uint256) {
        return s_pendingWithdrawals[owner].vaultWithdrawals[vault].shares;
    }

    function isRequestIdOwner(address owner, address vault, uint256 requestId) external view returns (bool) {
        return s_pendingWithdrawals[owner].vaultWithdrawals[vault].pendingRequests[requestId];
    }

    function _deposit(address vault, address asset, uint256 assets) private returns (uint256 shares) {
        _ensureIsLevvaVault(vault);

        if (msg.sender == vault) revert LevvaVaultAdapter__Forbidden();

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, assets);

        IERC20(asset).forceApprove(vault, assets);
        shares = IERC4626(vault).deposit(assets, msg.sender);

        emit Swap(msg.sender, asset, assets, address(vault), shares);
    }

    function _ensureIsLevvaVault(address vault) private view {
        if (!i_levvaVaultFactory.isLevvaVault(vault)) revert LevvaVaultAdapter__UnknownVault();
    }

    function _requestRedeem(address vault, uint256 shares) private returns (uint256 requestId) {
        _ensureIsLevvaVault(vault);

        IAdapterCallback(msg.sender).adapterCallback(address(this), vault, shares);
        requestId = ILevvaVault(vault).requestRedeem(shares);
        _addWithdrawalRequest(msg.sender, vault, requestId, shares);
        emit LevvaVaultRequestWithdrawal(msg.sender, vault, requestId, shares);
    }

    function _addWithdrawalRequest(address owner, address vault, uint256 requestId, uint256 shares) internal {
        PendingWithdrawals storage pendingWithdrawals = s_pendingWithdrawals[owner];
        VaultWithdrawals storage vaultWithdrawals = pendingWithdrawals.vaultWithdrawals[vault];

        vaultWithdrawals.shares += shares;

        if (vaultWithdrawals.vaultPosition == 0) {
            pendingWithdrawals.vaults.push(vault);
            vaultWithdrawals.vaultPosition = pendingWithdrawals.vaults.length;
        }

        vaultWithdrawals.pendingRequests[requestId] = true;
    }

    function _removeWithdrawalRequest(address owner, address vault, uint256 requestId, uint256 shares) internal {
        PendingWithdrawals storage pendingWithdrawals = s_pendingWithdrawals[owner];
        VaultWithdrawals storage vaultWithdrawals = pendingWithdrawals.vaultWithdrawals[vault];

        uint256 position = vaultWithdrawals.vaultPosition;
        if (position == 0) {
            revert LevvaVaultAdapter__NoRequestId();
        }

        if (!vaultWithdrawals.pendingRequests[requestId]) {
            revert LevvaVaultAdapter__ClaimUnauthorized();
        }

        delete vaultWithdrawals.pendingRequests[requestId];
        vaultWithdrawals.shares -= shares;

        if (vaultWithdrawals.shares == 0) {
            uint256 vaultCount = pendingWithdrawals.vaults.length;
            if (position != vaultCount) {
                address replacement = pendingWithdrawals.vaults[vaultCount - 1];
                pendingWithdrawals.vaults[position - 1] = replacement;
                pendingWithdrawals.vaultWithdrawals[replacement].vaultPosition = position;
            }

            pendingWithdrawals.vaults.pop();
            delete pendingWithdrawals.vaultWithdrawals[vault];
        }
    }
}
