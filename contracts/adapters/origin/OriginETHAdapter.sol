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

contract OriginETHAdapter is AdapterBase, IExternalPositionAdapter {
    using Asserts for address;
    using SafeERC20 for IWETH9;
    using SafeERC20 for IERC4626;
    using SafeERC20 for IERC20;

    struct WithdrawalQueue {
        uint256 start;
        uint256 end;
        mapping(uint256 index => uint256) requests;
    }

    error LessThanMinAmount();
    error NoWithdrawRequestInQueue();

    bytes4 public constant getAdapterId = bytes4(keccak256("OriginETHAdapter"));

    IWETH9 public immutable weth;
    IOETHVault public immutable oETHVault;
    IERC20 public immutable oETH;
    IERC4626 public immutable wrappedOETH;

    mapping(address vault => WithdrawalQueue) queues;

    constructor(address _weth, address _oETHVault, address _oETH, address _wrappedOETH) {
        _weth.assertNotZeroAddress();
        _oETHVault.assertNotZeroAddress();
        _oETH.assertNotZeroAddress();
        _wrappedOETH.assertNotZeroAddress();

        weth = IWETH9(_weth);
        oETHVault = IOETHVault(_oETHVault);
        oETH = IERC20(_oETH);
        wrappedOETH = IERC4626(_wrappedOETH);
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

    function _deposit(IWETH9 _weth, uint256 wethAmount, uint256 minWrappedOETHAmount) private returns (uint256 wrappedOETHAmount) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_weth), wethAmount);

        IOETHVault _oETHVault = oETHVault;
        weth.forceApprove(address(_oETHVault), wethAmount);
        _oETHVault.mint(address(_weth), wethAmount, 0);

        IERC4626 _wrappedOETH = wrappedOETH;
        oETH.forceApprove(address(_wrappedOETH), wethAmount);
        wrappedOETHAmount = _wrappedOETH.deposit(wethAmount, msg.sender);
        if (wrappedOETHAmount < minWrappedOETHAmount) revert LessThanMinAmount();
    }

    function _requestWithdrawal(IERC4626 _wrappedOETH, uint256 wrappedOETHAmount) private returns (uint256 requestId, uint256 oETHAmount) {
        IAdapterCallback(msg.sender).adapterCallback(address(this), address(_wrappedOETH), wrappedOETHAmount);
        oETHAmount = _wrappedOETH.redeem(wrappedOETHAmount, address(this), address(this));

        IOETHVault _oETHVault = oETHVault;
        oETH.forceApprove(address(_oETHVault), oETHAmount);
        (requestId,) = _oETHVault.requestWithdrawal(oETHAmount);
        _enqueueWithdrawalRequest(requestId);  
    }

    function _enqueueWithdrawalRequest(uint256 requestId) private {
        WithdrawalQueue storage queue = queues[msg.sender];
        unchecked {
            queue.requests[queue.end++] = requestId;
        }
    }

    function _dequeueWithdrawalRequest() private returns (uint256 requestId) {
        WithdrawalQueue storage queue = queues[msg.sender];
        uint256 queueStart;
        unchecked {
            queueStart = queue.start++;
        }
        if (queueStart == queue.end) revert NoWithdrawRequestInQueue();

        requestId = queue.requests[queueStart];
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
        amounts[0] = 0; // TODO: get actual amount
    }

    /// @inheritdoc IExternalPositionAdapter
    /// @dev there is no debt assets
    function getDebtAssets() external view returns (address[] memory assets, uint256[] memory amounts) {}
}
