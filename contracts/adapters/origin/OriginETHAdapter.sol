// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IAdapterCallback} from "../../interfaces/IAdapterCallback.sol";
import {IExternalPositionAdapter} from "../../interfaces/IExternalPositionAdapter.sol";
import {IWETH9} from "../../interfaces/IWETH9.sol";
import {Asserts} from "../../libraries/Asserts.sol";
import {AdapterBase} from "../AdapterBase.sol";
import {IOETHVault} from "./interfaces/IOETHVault.sol";
import {IOETH} from "./interfaces/IOETH.sol";

contract OriginETHAdapter is AdapterBase, IExternalPositionAdapter {
    using Asserts for address;
    using SafeERC20 for IWETH9;
    using SafeERC20 for IERC4626;
    using SafeERC20 for IOETH;

    struct WithdrawalRequest {
        uint256 amount;
        uint256 id;
    }

    struct WithdrawalQueue {
        uint256 start;
        uint256 end;
        uint256 totalPending;
        mapping(uint256 index => WithdrawalRequest) requests;
    }

    event OriginETHRequestWithdrawal(
        address indexed vault, uint256 indexed requestId, uint256 wrappedOETHAmount, uint256 expectedOETHAmount
    );
    event OriginETHClaimWithdrawal(address indexed vault, uint256 indexed requestId, uint256 withdrawnETHAmount);

    error LessThanMinAmount();
    error NoWithdrawRequestInQueue();

    bytes4 public constant getAdapterId = bytes4(keccak256("OriginETHAdapter"));

    IWETH9 public immutable weth;
    IOETHVault public immutable oETHVault;
    IOETH public immutable oETH;
    IERC4626 public immutable wrappedOETH;

    mapping(address vault => WithdrawalQueue) queues;

    constructor(address _wrappedOETH) {
        _wrappedOETH.assertNotZeroAddress();
        wrappedOETH = IERC4626(_wrappedOETH);

        IOETH _oETH = IOETH(IERC4626(wrappedOETH).asset());
        oETH = _oETH;

        IOETHVault _oETHVault = IOETHVault(_oETH.vaultAddress());
        oETHVault = _oETHVault;

        weth = IWETH9(_oETHVault.asset());
    }

    function deposit(uint256 wethAmount, uint256 minWrappedOETHAmount) external returns (uint256) {
        return _deposit(weth, wethAmount, minWrappedOETHAmount);
    }

    function depositAllExcept(uint256 except, uint256 minWrappedOETHAmount) external returns (uint256) {
        IWETH9 _weth = weth;
        uint256 amount = _weth.balanceOf(msg.sender) - except;
        return _deposit(_weth, amount, minWrappedOETHAmount);
    }

    function requestWithdrawal(uint256 wrappedOETHAmount) external returns (uint256, uint256) {
        return _requestWithdrawal(wrappedOETH, wrappedOETHAmount);
    }

    function requestWithdrawalAllExcept(uint256 wrappedOETHAmountExcept) external returns (uint256, uint256) {
        IERC4626 _wrappedOETH = wrappedOETH;
        uint256 amount = _wrappedOETH.balanceOf(msg.sender) - wrappedOETHAmountExcept;
        return _requestWithdrawal(_wrappedOETH, amount);
    }

    function claimWithdrawal() external returns (uint256 withdrawn) {
        uint256 requestId = _dequeueWithdrawalRequest();
        withdrawn = oETHVault.claimWithdrawal(requestId);
        weth.safeTransfer(msg.sender, withdrawn);

        emit OriginETHClaimWithdrawal(msg.sender, requestId, withdrawn);
    }

    function unwrap(uint256 wrappedOETHAmount) external returns (uint256) {
        return _unwrap(wrappedOETH, wrappedOETHAmount);
    }

    function unwrapAllExcept(uint256 wrappedOETHExceptAmount) external returns (uint256) {
        IERC4626 _wrappedOETH = wrappedOETH;
        uint256 wrappedOETHAmount = _wrappedOETH.balanceOf(msg.sender) - wrappedOETHExceptAmount;
        return _unwrap(_wrappedOETH, wrappedOETHAmount);
    }

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IExternalPositionAdapter).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IExternalPositionAdapter
    function getManagedAssets() external view returns (address[] memory assets, uint256[] memory amounts) {
        return _getManagedAssets(msg.sender);
    }

    function getManagedAssets(address vault)
        external
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        return _getManagedAssets(vault);
    }

    /// @inheritdoc IExternalPositionAdapter
    /// @dev there is no debt assets
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}

    function claimable(address vault) external view returns (address asset, uint256 claimableAmount) {
        WithdrawalQueue storage queue = queues[vault];
        WithdrawalRequest storage request = queue.requests[queue.start];

        uint256 requestId = request.id;
        if (requestId == 0) return (address(0), 0);

        IOETHVault _oETHVault = oETHVault;
        IOETHVault.WithdrawalRequest memory withdrawalRequest = _oETHVault.withdrawalRequests(requestId);

        if (block.timestamp < withdrawalRequest.timestamp + _oETHVault.withdrawalClaimDelay()) {
            return (address(0), 0);
        }

        if (_claimableAmount(_oETHVault) >= withdrawalRequest.queued) {
            return (address(weth), request.amount);
        }
    }

    function _deposit(IWETH9 _weth, uint256 wethAmount, uint256 minWrappedOETHAmount)
        private
        returns (uint256 wrappedOETHAmount)
    {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_weth), wethAmount);

        IOETHVault _oETHVault = oETHVault;
        weth.forceApprove(address(_oETHVault), wethAmount);
        _oETHVault.mint(address(_weth), wethAmount, 0);

        IERC4626 _wrappedOETH = wrappedOETH;
        oETH.forceApprove(address(_wrappedOETH), wethAmount);
        wrappedOETHAmount = _wrappedOETH.deposit(wethAmount, msg.sender);
        if (wrappedOETHAmount < minWrappedOETHAmount) revert LessThanMinAmount();

        emit Swap(msg.sender, address(_weth), wethAmount, address(_wrappedOETH), wrappedOETHAmount);
    }

    function _requestWithdrawal(IERC4626 _wrappedOETH, uint256 wrappedOETHAmount)
        private
        returns (uint256 requestId, uint256 oETHAmount)
    {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_wrappedOETH), wrappedOETHAmount);
        oETHAmount = _wrappedOETH.redeem(wrappedOETHAmount, address(this), address(this));

        IOETHVault _oETHVault = oETHVault;
        oETH.forceApprove(address(_oETHVault), oETHAmount);
        (requestId,) = _oETHVault.requestWithdrawal(oETHAmount);
        _enqueueWithdrawalRequest(requestId, oETHAmount);

        emit OriginETHRequestWithdrawal(msg.sender, requestId, wrappedOETHAmount, oETHAmount);
    }

    function _unwrap(IERC4626 _wrappedOETH, uint256 wrappedOETHAmount) private returns (uint256 oETHAmount) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_wrappedOETH), wrappedOETHAmount);
        oETHAmount = _wrappedOETH.redeem(wrappedOETHAmount, msg.sender, address(this));

        emit Swap(msg.sender, address(_wrappedOETH), wrappedOETHAmount, address(oETH), oETHAmount);
    }

    function _enqueueWithdrawalRequest(uint256 requestId, uint256 amount) private {
        WithdrawalQueue storage queue = queues[msg.sender];
        queue.totalPending += amount;
        WithdrawalRequest storage request;
        unchecked {
            request = queue.requests[queue.end++];
        }
        request.amount = amount;
        request.id = uint128(requestId);
    }

    function _dequeueWithdrawalRequest() private returns (uint256 requestId) {
        WithdrawalQueue storage queue = queues[msg.sender];
        uint256 queueStart;
        unchecked {
            queueStart = queue.start++;
        }
        if (queueStart == queue.end) revert NoWithdrawRequestInQueue();

        WithdrawalRequest storage request = queue.requests[queueStart];
        requestId = request.id;
        queue.totalPending -= request.amount;

        delete queue.requests[queueStart];
    }

    function _getManagedAssets(address vault)
        private
        view
        returns (address[] memory assets, uint256[] memory amounts)
    {
        assets = new address[](1);
        assets[0] = address(weth);

        amounts = new uint256[](1);
        amounts[0] = queues[vault].totalPending;
    }

    /// @dev based on
    /// https://github.com/OriginProtocol/origin-dollar/blob/a8be73bf0077a9d489a87ec9353280d1bbb59e3b/contracts/contracts/vault/OETHVaultCore.sol#L365
    function _claimableAmount(IOETHVault _oETHVault) private view returns (uint256) {
        (uint256 queued, uint256 _claimable, uint256 claimed,) = _oETHVault.withdrawalQueueMetadata();

        uint256 queueShortfall = queued - _claimable;
        if (queueShortfall == 0) {
            return _claimable;
        }

        uint256 wethBalance = weth.balanceOf(address(_oETHVault));
        uint256 allocatedWeth = _claimable - claimed;

        if (wethBalance <= allocatedWeth) {
            return _claimable;
        }

        uint256 unallocatedWeth = wethBalance - allocatedWeth;
        uint256 addedClaimable = queueShortfall < unallocatedWeth ? queueShortfall : unallocatedWeth;
        return _claimable + addedClaimable;
    }
}
