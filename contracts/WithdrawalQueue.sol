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

    event WithdrawalRequested(uint256 indexed requestId, address indexed receiver, uint256 assets, uint256 shares);
    event WithdrawalClaimed(uint256 indexed requestId, address indexed receiver, uint256 claimedAssets);
    event RequestsFinalized(uint256 lastFinalizedRequest);

    error NotRequestOwner();

    constructor() {
        _disableInitializers();
    }

    function initialize(address levvaVault) external initializer {
        __UUPSUpgradeable_init();
        __Ownable_init(msg.sender);
        __WithdrawalQueueBase_init(levvaVault);
    }

    function requestWithdrawal(uint256 assets, uint256 shares, address receiver)
        external
        onlyLevvaVault
        returns (uint256 requestId)
    {
        requestId = _enqueueRequest(shares, assets);
        _safeMint(receiver, requestId);

        emit WithdrawalRequested(requestId, receiver, assets, shares);
    }

    function claimWithdrawal(uint256 requestId) external returns (uint256 claimedAssets) {
        if (msg.sender != ownerOf(requestId)) revert NotRequestOwner();
        WithdrawalRequest memory request = _removeRequest(requestId);

        IERC4626 levvaVault = _getLevvaVault();
        uint256 previewedAmount = levvaVault.convertToAssets(request.shares);
        claimedAssets = request.assets < previewedAmount ? request.assets : previewedAmount;
        levvaVault.withdraw(claimedAssets, msg.sender, address(this));

        _burn(requestId);

        emit WithdrawalClaimed(requestId, msg.sender, claimedAssets);
    }

    function finalizeRequests(uint256 requestId) external onlyOwner {
        _finalizeRequests(requestId);
        emit RequestsFinalized(requestId);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
