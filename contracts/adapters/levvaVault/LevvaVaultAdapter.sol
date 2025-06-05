// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {IRequestWithdrawalVault} from "./interfaces/IRequestWithdrawalVault.sol";
import {IWithdrawalQueue} from "./interfaces/IWithdrawalQueue.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";

/// @title Adapter for interaction with Levva vaults
/// @notice Should be deployed for each vault
contract LevvaVaultAdapter is AdapterBase, ERC721Holder, IExternalPositionAdapter {
    using Asserts for address;
    using SafeERC20 for IERC20;

    bytes4 public constant getAdapterId = bytes4(keccak256("LevvaVaultAdapter"));

    address private immutable i_levvaVault;

    struct PendingWithdrawal {
        uint256 shares;
        uint256 vaultPosition; // index = vaultPosition - 1;
    }

    address[] private s_vaults;
    mapping(address vault => PendingWithdrawal) private s_pendingWithdrawals;

    event RequestWithdrawal(address indexed vault, uint256 indexed requestId, uint256 shares);
    event ClaimWithdrawal(address indexed vault, uint256 indexed requestId, uint256 assets);

    error LevvaVaultAdapter__Forbidden();
    error LevvaVaultAdapter__NoAccess();

    constructor(address levvaVault) {
        levvaVault.assertNotZeroAddress();
        i_levvaVault = levvaVault;
    }

    modifier onlyVault() {
        if (msg.sender != i_levvaVault) revert LevvaVaultAdapter__NoAccess();
        _;
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IExternalPositionAdapter).interfaceId;
    }

    /// @notice Deposits assets into the levva vault
    /// @param vault Address of levva vault
    /// @param assets Amount of assets to deposit
    /// @return shares Amount of shares
    function deposit(address vault, uint256 assets) external onlyVault returns (uint256 shares) {
        shares = _deposit(vault, IERC4626(vault).asset(), assets);
    }

    /// @notice Deposits assets into the levva vault all except given amount
    /// @param vault Address of levva vault
    /// @param except Amount of assets to be left after deposit
    /// @return shares Amount of shares
    function depositAllExcept(address vault, uint256 except) external onlyVault returns (uint256 shares) {
        address asset = IERC4626(vault).asset();
        uint256 amount = IERC20(asset).balanceOf(msg.sender) - except;
        shares = _deposit(vault, asset, amount);
    }

    /// @notice Requests redeem
    /// @param vault Address of vault
    /// @param shares Amount of shares to redeem
    /// @return requestId id of the withdrawal request
    function requestRedeem(address vault, uint256 shares) external onlyVault returns (uint256 requestId) {
        requestId = _requestRedeem(vault, shares);
    }

    /// @notice Requests redeem all amount of shares except given amount
    /// @param vault Address of vault
    /// @param except Amount of shares to be left
    /// @return requestId id of the withdrawal request
    function requestRedeemAllExcept(address vault, uint256 except) external onlyVault returns (uint256 requestId) {
        uint256 shares = IERC20(vault).balanceOf(msg.sender) - except;
        requestId = _requestRedeem(vault, shares);
    }

    /// @notice Claims withdrawal
    /// @param vault Address of vault
    /// @param requestId Id of the withdrawal request
    /// @return assets Amount of assets
    function claimWithdrawal(address vault, uint256 requestId) external onlyVault returns (uint256 assets) {
        address withdrawalQueue = IRequestWithdrawalVault(vault).withdrawalQueue();
        uint256 shares = IWithdrawalQueue(withdrawalQueue).getRequestedShares(requestId);
        assets = IWithdrawalQueue(withdrawalQueue).claimWithdrawal(requestId, msg.sender);
        _removePendingWithdrawalShares(vault, shares);

        emit ClaimWithdrawal(vault, requestId, assets);
    }

    /// @notice Checks if claim is possible
    function claimPossible(address vault, uint256 requestId) external view returns (bool) {
        address withdrawalQueue = IRequestWithdrawalVault(vault).withdrawalQueue();
        return IWithdrawalQueue(withdrawalQueue).lastFinalizedRequestId() >= requestId
            && IWithdrawalQueue(withdrawalQueue).getRequestedShares(requestId) > 0;
    }

    /// @notice Returns not zero when there are pending withdrawals
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        uint256 vaultLength = s_vaults.length;
        if (vaultLength == 0) {
            return (assets, amounts);
        }

        assets = new address[](vaultLength);
        amounts = new uint256[](vaultLength);
        for (uint256 i; i < vaultLength;) {
            address vault = s_vaults[i];
            assets[i] = vault;
            amounts[i] = s_pendingWithdrawals[vault].shares;

            unchecked {
                ++i;
            }
        }
    }

    /// @notice Returns zero for this adapter
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function _deposit(address vault, address asset, uint256 assets) private returns (uint256 shares) {
        if (msg.sender == vault) revert LevvaVaultAdapter__Forbidden();

        IAdapterCallback(msg.sender).adapterCallback(address(this), asset, assets);
        IERC20(asset).forceApprove(vault, assets);

        shares = IERC4626(vault).deposit(assets, msg.sender);
    }

    function _requestRedeem(address vault, uint256 shares) private returns (uint256 requestId) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), vault, shares);
        requestId = IRequestWithdrawalVault(vault).requestRedeem(shares);
        _addPendingWithdrawalShares(vault, shares);
        emit RequestWithdrawal(vault, requestId, shares);
    }

    function _addPendingWithdrawalShares(address vault, uint256 shares) private {
        PendingWithdrawal memory pendingWithdrawal = s_pendingWithdrawals[vault];
        pendingWithdrawal.shares += shares;
        if (pendingWithdrawal.vaultPosition == 0) {
            s_vaults.push(vault);
            pendingWithdrawal.vaultPosition = s_vaults.length;
        }
        s_pendingWithdrawals[vault] = pendingWithdrawal;
    }

    function _removePendingWithdrawalShares(address vault, uint256 shares) private {
        PendingWithdrawal memory pendingWithdrawal = s_pendingWithdrawals[vault];
        if (pendingWithdrawal.vaultPosition == 0) {
            return;
        }

        pendingWithdrawal.shares -= shares;

        if (pendingWithdrawal.shares == 0) {
            uint256 vaultIndex = pendingWithdrawal.vaultPosition - 1;
            uint256 vaultLastIndex = s_vaults.length - 1;

            if (vaultIndex != vaultLastIndex) {
                s_vaults[vaultIndex] = s_vaults[vaultLastIndex];
            }

            s_vaults.pop();
            delete s_pendingWithdrawals[vault];
        }
    }
}
