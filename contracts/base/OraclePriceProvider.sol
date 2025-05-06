// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {Asserts} from "../libraries/Asserts.sol";
import {IEulerPriceOracle} from "../interfaces/IEulerPriceOracle.sol";

abstract contract OraclePriceProvider is Initializable, Ownable2StepUpgradeable {
    using Asserts for address;

    /// @custom:storage-location erc7201:levva.storage.OraclePriceProvider
    struct OraclePriceProviderStorage {
        IEulerPriceOracle eulerOracle;
    }

    // keccak256(abi.encode(uint256(keccak256("levva.storage.OraclePriceProvider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OraclePriceProviderStorageLocation =
        0x915411155a1c14a9e152cb55b4d59555a72a2626bf44e042bd6db07323e1cc00;

    function _getOraclePriceProviderStorage() private pure returns (OraclePriceProviderStorage storage $) {
        assembly {
            $.slot := OraclePriceProviderStorageLocation
        }
    }

    event OracleSet(address indexed oracle);

    function __OraclePriceProvider_init(address eulerOracle) internal onlyInitializing {
        _setOracle(eulerOracle);
    }

    function setOracle(address eulerOracle) external onlyOwner {
        _setOracle(eulerOracle);
    }

    function oracle() external view returns (address) {
        return address(_getOraclePriceProviderStorage().eulerOracle);
    }

    function _setOracle(address eulerOracle) private {
        eulerOracle.assertNotZeroAddress();
        OraclePriceProviderStorage storage $ = _getOraclePriceProviderStorage();
        eulerOracle.assertNotSameValue(address($.eulerOracle));
        $.eulerOracle = IEulerPriceOracle(eulerOracle);

        emit OracleSet(eulerOracle);
    }

    function _getQuote(uint256 inAmount, address base, address quote) internal view virtual returns (uint256) {
        return _getOraclePriceProviderStorage().eulerOracle.getQuote(inAmount, base, quote);
    }
}
