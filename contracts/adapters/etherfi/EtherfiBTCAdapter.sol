// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {ILayerZeroTellerWithRateLimiting} from "./interfaces/ILayerZeroTellerWithRateLimiting.sol";
import {IAtomicQueue} from "./interfaces/IAtomicQueue.sol";

contract EtherfiBTCAdapter is AdapterBase {
    using SafeERC20 for IERC20;
    using Asserts for address;

    bytes4 public constant getAdapterId = bytes4(keccak256("EtherfiBTCAdapter"));

    event EtherfiBTCRequestWithdraw(
        address indexed from, address indexed to, uint96 amount, uint88 atomicPrice, uint64 deadline
    );
    event EtherfiBTCRequestCancel();

    IERC20 public immutable wBTC;
    IERC20 public immutable eBTC;
    ILayerZeroTellerWithRateLimiting public immutable teller;
    IAtomicQueue public immutable atomicQueue;

    constructor(address _wBTC, address _eBTC, address _teller, address _atomicQueue) {
        _wBTC.assertNotZeroAddress();
        _eBTC.assertNotZeroAddress();
        _teller.assertNotZeroAddress();
        _atomicQueue.assertNotZeroAddress();

        wBTC = IERC20(_wBTC);
        eBTC = IERC20(_eBTC);
        teller = ILayerZeroTellerWithRateLimiting(_teller);
        atomicQueue = IAtomicQueue(_atomicQueue);
    }

    function deposit(uint256 amount, uint256 minShare) external returns (uint256 shares) {
        IERC20 _wBTC = wBTC;
        IERC20 _eBTC = eBTC;

        _ensureIsValidAsset(address(_eBTC));

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_wBTC), amount);
        _wBTC.forceApprove(address(_eBTC), amount);

        shares = teller.deposit(_wBTC, amount, minShare);
        _eBTC.safeTransfer(msg.sender, amount);
    }

    // TODO: there is no mechanism for transferring tokens back to vault after request is resolved or cancelled
    //       I didn't bother to implement it cause then there must be some requests origins tracking
    //       otherwise anyone can appropriate tokens
    //       all of that won't be required in delegateCall approach anyway
    function requestWithdraw(uint96 amount, uint88 atomicPrice, uint64 deadline) external {
        IERC20 _wBTC = wBTC;
        IERC20 _eBTC = eBTC;
        IAtomicQueue _atomicQueue = atomicQueue;

        _ensureIsValidAsset(address(_wBTC));

        IAtomicQueue.AtomicRequest memory currentRequest =
            _atomicQueue.getUserAtomicRequest(address(this), _eBTC, _wBTC);
        currentRequest.offerAmount = amount;
        currentRequest.deadline = deadline;
        currentRequest.atomicPrice = atomicPrice;

        _atomicQueue.updateAtomicRequest(_eBTC, _wBTC, currentRequest);

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_eBTC), amount);
        _eBTC.forceApprove(address(_atomicQueue), amount);

        emit EtherfiBTCRequestWithdraw(address(_eBTC), address(_wBTC), amount, atomicPrice, deadline);
    }

    function cancelWithdrawRequest() external {
        IERC20 _eBTC = eBTC;
        IAtomicQueue _atomicQueue = atomicQueue;

        IAtomicQueue.AtomicRequest memory defaultRequest;

        _atomicQueue.updateAtomicRequest(_eBTC, wBTC, defaultRequest);
        _eBTC.forceApprove(address(_atomicQueue), 0);

        emit EtherfiBTCRequestCancel();
    }
}
