// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {ILiquidityPool} from "./interfaces/ILiquidityPool.sol";
import {IWithdrawRequestNFT} from "./interfaces/IWithdrawRequestNFT.sol";
import {IeETH} from "./interfaces/IeETH.sol";

abstract contract AbstractEtherfiEthAdapter is AdapterBase, ERC721Holder, IExternalPositionAdapter {
    using SafeERC20 for IeETH;
    using SafeERC20 for IWETH9;
    using Asserts for address;

    struct WithdrawalQueue {
        uint256 start;
        uint256 end;
        mapping(uint256 index => uint256) requests;
    }

    error NoWithdrawRequestInQueue();

    IWETH9 public immutable weth;
    ILiquidityPool public immutable liquidityPool;

    IeETH public immutable eETH;
    IWithdrawRequestNFT public immutable withdrawRequestNFT;

    mapping(address vault => WithdrawalQueue) queues;

    constructor(address _weth, address _liquidityPool) {
        _weth.assertNotZeroAddress();
        _liquidityPool.assertNotZeroAddress();

        weth = IWETH9(_weth);
        liquidityPool = ILiquidityPool(_liquidityPool);
        eETH = IeETH(ILiquidityPool(_liquidityPool).eETH());
        withdrawRequestNFT = IWithdrawRequestNFT(ILiquidityPool(_liquidityPool).withdrawRequestNFT());
    }

    receive() external payable {}

    function deposit(uint256 amount) external returns (uint256 output) {
        ILiquidityPool _liquidityPool = liquidityPool;
        IeETH _eETH = eETH;
        _ensureIsValidAsset(address(_eETH));

        IWETH9 _weth = weth;
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_weth), amount);
        _weth.withdraw(amount);

        output = _liquidityPool.deposit{value: amount}();
        _eETH.safeTransfer(msg.sender, amount);
    }

    function requestWithdraw(uint256 amount) external returns (uint256 requestId) {
        ILiquidityPool _liquidityPool = liquidityPool;
        IeETH _eETH = eETH;

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_eETH), amount);

        _eETH.forceApprove(address(_liquidityPool), amount);
        requestId = _liquidityPool.requestWithdraw(address(this), amount);
        _enqueueWithdrawalRequest(requestId);
    }

    function claimWithdraw() external returns (uint256 withdrawn) {
        IWETH9 _weth = weth;
        _ensureIsValidAsset(address(_weth));

        uint256 requestId = _dequeueWithdrawalRequest();
        withdrawRequestNFT.claimWithdraw(requestId);
        withdrawn = address(this).balance;

        _weth.deposit{value: withdrawn}();
        _weth.safeTransfer(msg.sender, withdrawn);
    }

    function _enqueueWithdrawalRequest(uint256 requestId) private {
        WithdrawalQueue storage queue = queues[msg.sender];
        unchecked {
            queue.requests[queue.end++] = requestId;
        }
    }

    function _dequeueWithdrawalRequest() private returns (uint256 requestId) {
        WithdrawalQueue storage queue = queues[msg.sender];
        uint256 queueStart = queue.start++;
        if (queueStart == queue.end) revert NoWithdrawRequestInQueue();

        requestId = queue.requests[queueStart];
        unchecked {
            delete queue.requests[queueStart];
        }
    }

    function _getPendingEthAmount(address vault) internal view returns (uint256 pendingEth) {
        IWithdrawRequestNFT _withdrawRequestNFT = withdrawRequestNFT;
        uint256 totalPooledEthers = liquidityPool.getTotalPooledEther();
        uint256 totalShares = eETH.totalShares();
        WithdrawalQueue storage queue = queues[vault];
        unchecked {
            for (uint256 i = queue.start; i < queue.end; ++i) {
                IWithdrawRequestNFT.WithdrawRequest memory request = _withdrawRequestNFT.getRequest(queue.requests[i]);
                uint256 amountForShares = request.shareOfEEth * totalPooledEthers / totalShares;
                pendingEth += (request.amountOfEEth < amountForShares) ? request.amountOfEEth : amountForShares;
            }
        }
    }
}
