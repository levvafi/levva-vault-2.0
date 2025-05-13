// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";

abstract contract FeeCollector is Initializable, ERC4626Upgradeable, Ownable2StepUpgradeable {
    using Asserts for address;
    using Asserts for uint256;
    using Asserts for uint48;
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

    event FeeCollectorSet(address indexed newFeeCollector);
    event ManagementFeeIRSet(uint48 newManagementFeeIR);
    event PerformanceFeeRatioSet(uint48 newPerformanceFeeRatio);

    function __FeeCollector_init(address feeCollector) internal onlyInitializing {
        feeCollector.assertNotZeroAddress();

        FeeCollectorStorage storage $ = _getFeeCollectorStorage();
        $.lastFeeTimestamp = block.timestamp;
        $.feeCollector = feeCollector;

        uint256 oneToken = 10 ** decimals();
        uint256 oneTokenOffset = 10 ** _decimalsOffset();
        $.highWaterMarkPerShare = oneToken.mulDiv(1, oneTokenOffset, Math.Rounding.Floor);
    }

    function setFeeCollector(address newFeeCollector) external onlyOwner {
        newFeeCollector.assertNotZeroAddress();

        FeeCollectorStorage storage $ = _getFeeCollectorStorage();
        newFeeCollector.assertNotSameValue($.feeCollector);

        $.feeCollector = newFeeCollector;
        emit FeeCollectorSet(newFeeCollector);
    }

    function setManagementFeeIR(uint48 newManagementFeeIR) external onlyOwner {
        FeeCollectorStorage storage $ = _getFeeCollectorStorage();
        newManagementFeeIR.assertNotSameValue($.managementFeeIR);

        $.managementFeeIR = newManagementFeeIR;
        emit ManagementFeeIRSet(newManagementFeeIR);
    }

    function setPerformanceFeeRatio(uint48 newPerformanceFeeRatio) external onlyOwner {
        FeeCollectorStorage storage $ = _getFeeCollectorStorage();
        newPerformanceFeeRatio.assertNotSameValue($.performanceFeeRatio);

        $.performanceFeeRatio = newPerformanceFeeRatio;
        emit PerformanceFeeRatioSet(newPerformanceFeeRatio);
    }

    function getFeeCollectorStorage() external pure returns (FeeCollectorStorage memory) {
        return _getFeeCollectorStorage();
    }

    function _collectFees(uint256 totalAssets) internal {
        uint256 totalSupply = totalSupply();

        FeeCollectorStorage storage $ = _getFeeCollectorStorage();

        uint256 timeElapsed = block.timestamp - $.lastFeeTimestamp;
        uint256 managementFee = totalAssets.mulDiv(timeElapsed * $.managementFeeIR, 365 days * ONE, Math.Rounding.Floor);

        uint256 oneToken = 10 ** decimals();
        uint256 oneTokenOffset = 10 ** _decimalsOffset();
        uint256 currentNavPerShare = oneToken.mulDiv(totalAssets + 1, totalSupply + oneTokenOffset, Math.Rounding.Floor);

        uint256 highWaterMarkPerShare = $.highWaterMarkPerShare;
        uint256 performanceFee;
        if (currentNavPerShare > highWaterMarkPerShare) {
            uint256 gainPerShare = currentNavPerShare - highWaterMarkPerShare;
            uint256 gain = totalSupply.mulDiv(gainPerShare, oneToken, Math.Rounding.Floor);
            performanceFee = gain.mulDiv($.performanceFeeRatio, ONE, Math.Rounding.Floor);
            $.highWaterMarkPerShare = currentNavPerShare;
        }

        uint256 totalFees = managementFee + performanceFee;
        if (totalFees != 0) {
            /* Underlying asset transfer fails in case of liquidity distribution to other tracked tokens or protocols
             * Because of that we're minting an equivalent amount of lp tokens to feeCollector
             *
             * sharesToMint / (totalSupply + sharesToMint) = totalFees / totalAssets
             * sharesToMint = totalFees * totalSupply / (totalAssets - totalFees)
             */
            uint256 sharesToMint =
                totalFees.mulDiv(totalSupply + oneTokenOffset, totalAssets - totalFees + 1, Math.Rounding.Floor);
            _mint($.feeCollector, sharesToMint);
        }

        $.lastFeeTimestamp = block.timestamp;
    }
}
