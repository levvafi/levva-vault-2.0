// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {ERC4626AdapterBase} from "../ERC4626AdapterBase.sol";
import {IStakedUSDe} from "./interfaces/IStakedUSDe.sol";

contract EthenaAdapter is ERC4626AdapterBase {
    using SafeERC20 for IStakedUSDe;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("EthenaAdapter"));

    address public immutable levvaVault;

    error NoAccess();

    modifier onlyVault() {
        if (msg.sender != levvaVault) revert NoAccess();
        _;
    }

    constructor(address _levvaVault, address _sUSDe) ERC4626AdapterBase(_sUSDe) {
        _levvaVault.assertNotZeroAddress();
        levvaVault = _levvaVault;
    }

    function cooldownShares(uint256 shares) external onlyVault returns (uint256 assets) {
        IStakedUSDe _stakedUSDe = stakedUSDe();

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_stakedUSDe), shares);
        return _stakedUSDe.cooldownShares(shares);
    }

    function unstake() external onlyVault {
        IStakedUSDe _stakedUSDe = stakedUSDe();
        _ensureIsValidAsset(_stakedUSDe.asset());

        _stakedUSDe.unstake(msg.sender);
    }

    function stakedUSDe() public view returns (IStakedUSDe) {
        return IStakedUSDe(_vault);
    }
}
