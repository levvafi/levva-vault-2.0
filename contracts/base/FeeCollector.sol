// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {Asserts} from "../libraries/Asserts.sol";

abstract contract FeeCollector is Initializable {
    using Asserts for address;
    using Asserts for uint256;
    using Math for uint256;

    uint48 private constant ONE = 1_000_000;

    /// @custom:storage-location erc7201:levva.storage.FeeCollector
    struct FeeCollectorStorage {
        uint256 lastFeeTimestamp;
        uint256 highWaterMarkPerShare;
        address feeCollector;
        uint48 managementFeeIR;
        uint48 performanceFeeRatio;
    }

    // keccak256(abi.encode(uint256(keccak256("levva.storage.FeeCollector")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FeeCollectorStorageLocation =
        0xed076c0c5f8dad10a45b5b79a69577043806b13b8bb0f0312131865a10c07700;

    function _getFeeCollectorStorage() private pure returns (FeeCollectorStorage storage $) {
        assembly {
            $.slot := FeeCollectorStorageLocation
        }
    }

    function __FeeCollector_init(address feeCollector) internal onlyInitializing {
        FeeCollectorStorage storage $ = _getFeeCollectorStorage();
        $.lastFeeTimestamp = block.timestamp;
        $.highWaterMarkPerShare = 1e18;
        $.feeCollector = feeCollector;
    }

    function _collectFees(uint256 totalAssets, uint256 totalSupply) internal {
        FeeCollectorStorage storage $ = _getFeeCollectorStorage();

        uint256 timeElapsed = block.timestamp - $.lastFeeTimestamp;
        uint256 managementFee = totalAssets.mulDiv(timeElapsed * $.managementFeeIR, 365 days * ONE, Math.Rounding.Floor);

        // TODO: reorg code to take this values from ERC4626
        uint256 decimals = 18;
        uint256 oneToken = 10 ** decimals;
        uint256 decimalsOffset = 0;
        // TODO: floor or ceil? Seems like shouldn't matter
        uint256 currentNavPerShare = oneToken.mulDiv(totalAssets + 1, totalSupply + 10 ** decimalsOffset);

        uint256 highWaterMarkPerShare = $.highWaterMarkPerShare;
        uint256 performanceFee;
        if (currentNavPerShare > highWaterMarkPerShare) {
            uint256 gain = currentNavPerShare - highWaterMarkPerShare;
            performanceFee = totalSupply.mulDiv(gain * $.performanceFeeRatio, oneToken * ONE, Math.Rounding.Floor);
            $.highWaterMarkPerShare = currentNavPerShare;
        }

        if (managementFee + performanceFee != 0) {
            _transferUnderlyingAsset($.feeCollector, managementFee + performanceFee);
        }

        $.lastFeeTimestamp = block.timestamp;
    }

    function _transferUnderlyingAsset(address feeCollector, uint256 fees) private {
        // TODO: not an actual transfer (fails in case of fully zero asset balance)
        // seems like it's required to mint tokens to feeCollector
    }
}
