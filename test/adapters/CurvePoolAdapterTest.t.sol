// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {CurvePoolAdapter} from "contracts/adapters/curve/CurvePoolAdapter.sol";
import {EulerRouterMock} from "../mocks/EulerRouterMock.t.sol";
import {LevvaVaultFactory} from "../../contracts/LevvaVaultFactory.sol";
import {LevvaVault} from "../../contracts/LevvaVault.sol";
import {WithdrawalQueue} from "../../contracts/WithdrawalQueue.sol";

contract CurvePoolAdapterTest is Test {
    address private weethWethNgPool = 0xDB74dfDD3BB46bE8Ce6C33dC9D82777BCFc3dEd5;
    address private usdcWbtcWethTriCryptoPool = 0x7F86Bf177Dd4F3494b841a37e810A34dD56c829B;
    address private usrRlpTwoCryptoPool = 0xC907ba505C2E1cbc4658c395d4a2c7E6d2c32656;

    IERC20 private USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private WEETH = IERC20(0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee);
    IERC20 private WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IERC20 private USR = IERC20(0x66a1E37c9b0eAddca17d3662D6c05F4DECf3e110);
    IERC20 private RLP = IERC20(0x4956b52aE2fF65D74CA2d61207523288e4528f96);

    CurvePoolAdapter internal curvePoolAdapter;

    address internal OWNER = makeAddr("owner");
    LevvaVault internal vault;

    string private mainnetRpcUrl = vm.envString("ETH_RPC_URL");

    function setUp() public virtual {
        vm.createSelectFork(vm.rpcUrl(mainnetRpcUrl), 22497400);
        vm.skip(block.chainid != 1, "Only mainnet fork test");

        curvePoolAdapter = new CurvePoolAdapter();
        vm.deal(OWNER, 1 ether);

        EulerRouterMock oracle = new EulerRouterMock();
        oracle.setPrice(oracle.ONE(), address(WBTC), address(USDC));
        oracle.setPrice(oracle.ONE(), address(WETH), address(USDC));
        oracle.setPrice(oracle.ONE(), address(WEETH), address(USDC));
        oracle.setPrice(oracle.ONE(), address(USR), address(USDC));
        oracle.setPrice(oracle.ONE(), address(RLP), address(USDC));

        address levvaVaultImplementation = address(new LevvaVault());
        address withdrawalQueueImplementation = address(new WithdrawalQueue());
        address levvaVaultFactoryImplementation = address(new LevvaVaultFactory());

        bytes memory data = abi.encodeWithSelector(
            LevvaVaultFactory.initialize.selector, levvaVaultImplementation, withdrawalQueueImplementation
        );
        ERC1967Proxy levvaVaultFactoryProxy = new ERC1967Proxy(levvaVaultFactoryImplementation, data);
        LevvaVaultFactory levvaVaultFactory = LevvaVaultFactory(address(levvaVaultFactoryProxy));

        (address deployedVault,) = levvaVaultFactory.deployVault(
            address(USDC),
            "lpName",
            "lpSymbol",
            "withdrawalQueueName",
            "withdrawalQueueSymbol",
            address(0xFEE),
            address(oracle)
        );

        vault = LevvaVault(deployedVault);
        vault.setMaxTrackedAssets(type(uint8).max);
        vault.addAdapter(address(curvePoolAdapter));

        deal(address(USDC), address(vault), 100_000 * 10 ** 6);
        deal(address(WBTC), address(vault), 1 * 10 ** 8);
        deal(address(WETH), address(vault), 20 ether);
        deal(address(WEETH), address(vault), 20 ether);
        deal(address(USR), address(vault), 100_000 * 10 ** 18);
        deal(address(RLP), address(vault), 80_000 * 10 ** 18);
    }

    function testAddLiquidityNgPool() public {
        uint256 lpBalanceBefore = IERC20(weethWethNgPool).balanceOf(address(vault));
        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));
        uint256 weethBalanceBefore = WEETH.balanceOf(address(vault));

        address[] memory coins = new address[](2);
        coins[0] = address(WETH);
        coins[1] = address(WEETH);

        uint256 weethAmount = 1 ether;
        uint256 wethAmount = 2 ether;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethAmount;
        amounts[1] = weethAmount;

        vm.prank(address(vault));
        curvePoolAdapter.addLiquidityNg(weethWethNgPool, coins, amounts, 0);

        assertGt(IERC20(weethWethNgPool).balanceOf(address(vault)), lpBalanceBefore);
        assertEq(WETH.balanceOf(address(vault)), wethBalanceBefore - wethAmount);
        assertEq(WEETH.balanceOf(address(vault)), weethBalanceBefore - weethAmount);
    }

    function testRemoveLiquidityNgPool() public {
        address[] memory coins = new address[](2);
        coins[0] = address(WETH);
        coins[1] = address(WEETH);

        uint256 wethAmount = 2 ether;
        uint256 weethAmount = 2 ether;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = wethAmount;
        amounts[1] = weethAmount;

        vm.prank(address(vault));
        curvePoolAdapter.addLiquidityNg(weethWethNgPool, coins, amounts, 0);

        uint256 lpBalanceBefore = IERC20(weethWethNgPool).balanceOf(address(vault));
        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));
        uint256 weethBalanceBefore = WEETH.balanceOf(address(vault));

        uint256 wethMinAmount = 1 ether;
        uint256 weethMinAmount = 1 ether;

        uint256[] memory minAmounts = new uint256[](2);
        amounts[0] = wethMinAmount;
        amounts[1] = weethMinAmount;

        uint256 lpAmountToRemove = lpBalanceBefore * 3 / 4;

        vm.prank(address(vault));
        curvePoolAdapter.removeLiquidityNg(weethWethNgPool, lpAmountToRemove, minAmounts);

        assertEq(IERC20(weethWethNgPool).balanceOf(address(vault)), lpBalanceBefore - lpAmountToRemove);
        assertGt(WETH.balanceOf(address(vault)), wethBalanceBefore + wethMinAmount);
        assertGt(WEETH.balanceOf(address(vault)), weethBalanceBefore + weethMinAmount);
    }

    function testAddLiquidityTwoCrypto() public {
        uint256 lpBalanceBefore = IERC20(usrRlpTwoCryptoPool).balanceOf(address(vault));
        uint256 usrBalanceBefore = USR.balanceOf(address(vault));
        uint256 rlpBalanceBefore = RLP.balanceOf(address(vault));

        address[2] memory coins;
        coins[0] = address(USR);
        coins[1] = address(RLP);

        uint256 usrAmount = 1_000 * 10 ** 18; // 1000 usr
        uint256 rlpAmount = 800 * 10 ** 18; // 800 rlp

        uint256[2] memory amounts;
        amounts[0] = usrAmount;
        amounts[1] = rlpAmount;

        vm.prank(address(vault));
        curvePoolAdapter.addLiquidityTwoCrypto(usrRlpTwoCryptoPool, coins, amounts, 0);

        assertGt(IERC20(usrRlpTwoCryptoPool).balanceOf(address(vault)), lpBalanceBefore);
        assertEq(USR.balanceOf(address(vault)), usrBalanceBefore - usrAmount);
        assertEq(RLP.balanceOf(address(vault)), rlpBalanceBefore - rlpAmount);
    }

    function testRemoveLiquidityTwoCrypto() public {
        address[2] memory coins;
        coins[0] = address(USR);
        coins[1] = address(RLP);

        uint256 usrAmount = 2_000 * 10 ** 18; // 2000 usr
        uint256 rlpAmount = 1_600 * 10 ** 18; // 1600 rlp

        uint256[2] memory amounts;
        amounts[0] = usrAmount;
        amounts[1] = rlpAmount;

        vm.prank(address(vault));
        curvePoolAdapter.addLiquidityTwoCrypto(usrRlpTwoCryptoPool, coins, amounts, 0);

        uint256 lpBalanceBefore = IERC20(usrRlpTwoCryptoPool).balanceOf(address(vault));
        uint256 usrBalanceBefore = USR.balanceOf(address(vault));
        uint256 rlpBalanceBefore = RLP.balanceOf(address(vault));

        uint256 usrMinAmount = 1_000 * 10 ** 18; // 1000 usr
        uint256 rlpMinAmount = 800 * 10 ** 18; // 800 rlp

        uint256[2] memory minAmounts;
        amounts[0] = usrMinAmount;
        amounts[1] = rlpMinAmount;

        uint256 lpAmountToRemove = lpBalanceBefore * 3 / 4;

        vm.prank(address(vault));
        curvePoolAdapter.removeLiquidityTwoCrypto(usrRlpTwoCryptoPool, lpAmountToRemove, minAmounts);

        assertEq(IERC20(usrRlpTwoCryptoPool).balanceOf(address(vault)), lpBalanceBefore - lpAmountToRemove);
        assertGt(USR.balanceOf(address(vault)), usrBalanceBefore + usrMinAmount);
        assertGt(RLP.balanceOf(address(vault)), rlpBalanceBefore + rlpMinAmount);
    }

    function testAddLiquidityTriCrypto() public {
        uint256 lpBalanceBefore = IERC20(usdcWbtcWethTriCryptoPool).balanceOf(address(vault));
        uint256 usdcBalanceBefore = USDC.balanceOf(address(vault));
        uint256 wbtcBalanceBefore = WBTC.balanceOf(address(vault));
        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));
        address[3] memory coins;
        coins[0] = address(USDC);
        coins[1] = address(WBTC);
        coins[2] = address(WETH);

        uint256 usdcAmount = 4_000 * 10 ** 6; // 4000 usdc
        uint256 wbtcAmount = 4 * 10 ** 6; // 0.04 wbtc
        uint256 wethAmount = 1 ether;
        uint256[3] memory amounts;
        amounts[0] = usdcAmount;
        amounts[1] = wbtcAmount;
        amounts[2] = wethAmount;

        vm.prank(address(vault));
        curvePoolAdapter.addLiquidityTriCrypto(usdcWbtcWethTriCryptoPool, coins, amounts, 0);

        assertGt(IERC20(usdcWbtcWethTriCryptoPool).balanceOf(address(vault)), lpBalanceBefore);
        assertEq(USDC.balanceOf(address(vault)), usdcBalanceBefore - usdcAmount);
        assertEq(WBTC.balanceOf(address(vault)), wbtcBalanceBefore - wbtcAmount);
        assertEq(WETH.balanceOf(address(vault)), wethBalanceBefore - wethAmount);
    }

    function testRemoveLiquidityTriCrypto() public {
        address[3] memory coins;
        coins[0] = address(USDC);
        coins[1] = address(WBTC);
        coins[2] = address(WETH);

        uint256 usdcAmount = 8_000 * 10 ** 6; // 8000 usdc
        uint256 wbtcAmount = 8 * 10 ** 6; // 0.02 wbtc
        uint256 wethAmount = 2 ether;
        uint256[3] memory amounts;
        amounts[0] = usdcAmount;
        amounts[1] = wbtcAmount;
        amounts[2] = wethAmount;

        vm.prank(address(vault));
        curvePoolAdapter.addLiquidityTriCrypto(usdcWbtcWethTriCryptoPool, coins, amounts, 0);

        uint256 lpBalanceBefore = IERC20(usdcWbtcWethTriCryptoPool).balanceOf(address(vault));
        uint256 usdcBalanceBefore = USDC.balanceOf(address(vault));
        uint256 wbtcBalanceBefore = WBTC.balanceOf(address(vault));
        uint256 wethBalanceBefore = WETH.balanceOf(address(vault));

        uint256 usdcMinAmount = 4_000 * 10 ** 6; // 4000 usdc
        uint256 wbtcMinAmount = 4 * 10 ** 6; // 0.04 wbtc
        uint256 wethMinAmount = 1 ether;

        uint256[3] memory minAmounts;
        amounts[0] = usdcMinAmount;
        amounts[1] = wbtcMinAmount;
        amounts[2] = wethMinAmount;

        uint256 lpAmountToRemove = lpBalanceBefore * 3 / 4;

        vm.prank(address(vault));
        curvePoolAdapter.removeLiquidityTriCrypto(usdcWbtcWethTriCryptoPool, lpAmountToRemove, minAmounts);

        assertEq(IERC20(usdcWbtcWethTriCryptoPool).balanceOf(address(vault)), lpBalanceBefore - lpAmountToRemove);
        assertGt(USDC.balanceOf(address(vault)), usdcBalanceBefore + usdcMinAmount);
        assertGt(WBTC.balanceOf(address(vault)), wbtcBalanceBefore + wbtcMinAmount);
        assertGt(WETH.balanceOf(address(vault)), wethBalanceBefore + wethMinAmount);
    }
}
