// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {WithdrawalQueueBase} from "./base/WithdrawalQueueBase.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract WithdrawalQueue is UUPSUpgradeable, ERC721Upgradeable, Ownable2StepUpgradeable, WithdrawalQueueBase {
    using SafeERC20 for IERC4626;

    error NoAccess();
    error NotRequestOwner();

    IERC4626 public levvaVault;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _levvaVault) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        levvaVault = IERC4626(_levvaVault);
    }

    function requestWithdrawal(uint256 assets, uint256 shares, address receiver) external returns (uint256) {
        if (msg.sender != address(levvaVault)) revert NoAccess();

        uint256 requestId = _enqueueRequest(shares, assets);
        _safeMint(receiver, requestId);
        return requestId;
    }

    function claimWithdrawal(uint256 requestId) external returns (uint256 claimedAssets) {
        if (msg.sender != ownerOf(requestId)) revert NotRequestOwner();
        WithdrawalRequest memory request = _removeRequest(requestId);

        uint256 previewedAmount = levvaVault.convertToAssets(request.shares);
        claimedAssets = request.assets < previewedAmount ? request.assets : previewedAmount;
        levvaVault.withdraw(claimedAssets, msg.sender, address(this));

        _burn(requestId);
    }

    function finalizeRequests(uint256 requestId) external onlyOwner {
        _finalizeRequests(requestId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
