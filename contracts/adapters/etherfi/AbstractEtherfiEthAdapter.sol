// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {ILiquidityPool} from "./interfaces/ILiquidityPool.sol";
import {IWithdrawRequestNFT} from "./interfaces/IWithdrawRequestNFT.sol";

abstract contract AbstractEtherfiEthAdapter is AdapterBase, ERC721Holder {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH9;
    using Asserts for address;

    struct WithdrawalRequest {
        uint256 requestId;
        uint256 amount;
    }

    struct WithdrawalQueue {
        uint256 start;
        uint256 end;
        mapping(uint256 index => WithdrawalRequest) queue;
    }

    IWETH9 public immutable weth;
    ILiquidityPool public immutable liquidityPool;

    mapping(address vault => WithdrawalQueue) queues;

    constructor(address _weth, address _liquidityPool) {
        _weth.assertNotZeroAddress();
        _liquidityPool.assertNotZeroAddress();

        weth = IWETH9(_weth);
        liquidityPool = ILiquidityPool(_liquidityPool);
    }

    receive() external payable {}

    function deposit(uint256 amount) external returns (uint256 output) {
        ILiquidityPool _liquidityPool = liquidityPool;
        address eETH = _liquidityPool.eETH();
        _ensureIsValidAsset(eETH);

        IWETH9 _weth = weth;
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_weth), amount);
        _weth.withdraw(amount);

        output = _liquidityPool.deposit{value: amount}();
        IERC20(eETH).safeTransfer(msg.sender, amount);
    }

    function requestWithdraw(uint256 amount) external returns (uint256 requestId) {
        ILiquidityPool _liquidityPool = liquidityPool;
        IERC20 eETH = IERC20(_liquidityPool.eETH());

        IAdapterCallback(msg.sender).adapterCallback(address(this), address(eETH), amount);

        eETH.forceApprove(address(_liquidityPool), amount);
        requestId = _liquidityPool.requestWithdraw(address(this), amount);
        _enqueueWithdrawalRequest(requestId, amount);
    }

    function claimWithdraw() external returns (uint256 withdrawn) {
        IWETH9 _weth = weth;
        _ensureIsValidAsset(address(_weth));

        WithdrawalRequest memory request = _dequeueWithdrawalRequest();

        IWithdrawRequestNFT withdrawRequestNFT = IWithdrawRequestNFT(liquidityPool.withdrawRequestNFT());
        if (!withdrawRequestNFT.isFinalized(request.requestId) || !withdrawRequestNFT.isValid(request.requestId)) {
            revert();
        }

        withdrawRequestNFT.claimWithdraw(request.requestId);
        withdrawn = address(this).balance;

        _weth.deposit{value: withdrawn}();
        _weth.safeTransfer(msg.sender, withdrawn);
    }

    function _enqueueWithdrawalRequest(uint256 requestId, uint256 amount) private {
        WithdrawalQueue storage queue = queues[msg.sender];
        unchecked {
            queue.queue[queue.end++] = WithdrawalRequest({requestId: requestId, amount: amount});
        }
    }

    function _dequeueWithdrawalRequest() private returns (WithdrawalRequest memory request) {
        WithdrawalQueue storage queue = queues[msg.sender];
        uint256 queueStart = queue.start++;
        if (queueStart == queue.end) revert();

        request = queue.queue[queueStart];
        unchecked {
            delete queue.queue[queueStart];
        }
    }
}
