// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {WithdrawalQueueBase} from "./base/WithdrawalQueueBase.sol";

/// @custom:oz-upgrades-unsafe-allow constructor
contract WithdrawalQueue is ERC721Upgradeable, WithdrawalQueueBase {
    using SafeERC20 for IERC4626;

    event WithdrawalRequested(uint256 indexed requestId, address indexed receiver, uint256 shares);
    event WithdrawalClaimed(uint256 indexed requestId, address indexed receiver, uint256 claimedAssets);
    event RequestsFinalized(uint256 lastFinalizedRequest);

    error NotRequestOwner();
    error NotFinalized();

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address levvaVault) external initializer {
        __WithdrawalQueueBase_init(owner, levvaVault);
    }

    function requestWithdrawal(uint256 shares, address receiver) external onlyLevvaVault returns (uint256 requestId) {
        requestId = _enqueueRequest(shares);
        _safeMint(receiver, requestId);

        emit WithdrawalRequested(requestId, receiver, shares);
    }

    function claimWithdrawal(uint256 requestId) external returns (uint256 claimedAssets) {
        if (msg.sender != ownerOf(requestId)) revert NotRequestOwner();
        if (!_isFinalized(requestId)) revert NotFinalized();

        uint256 requestedShares = _removeRequest(requestId);
        claimedAssets = _getLevvaVault().redeem(requestedShares, msg.sender, address(this));

        _burn(requestId);

        emit WithdrawalClaimed(requestId, msg.sender, claimedAssets);
    }

    function finalizeRequests(uint256 requestId) external onlyFinalizer {
        _finalizeRequests(requestId);
        emit RequestsFinalized(requestId);
    }
}
