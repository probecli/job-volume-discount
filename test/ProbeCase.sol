// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";
import {VolumeDiscountHook} from "../src/VolumeDiscountHook.sol";

/// @notice The job snapshot. Every case inherits this fixture, so all cases
/// start from the same state: a v4 PoolManager, two tokens, the hook at a
/// flag-valid address, and one dynamic-fee pool with deep liquidity.
abstract contract ProbeCase is Test, Deployers {
    VolumeDiscountHook internal hook;
    address internal hookOwner = address(0xB0B);
    address internal alice = address(0xA11CE);
    address internal whale = address(0x3A1E);

    function setUp() public virtual {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        address flagged = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) | (uint160(0x5555) << 144));
        deployCodeTo("VolumeDiscountHook.sol:VolumeDiscountHook", abi.encode(manager, hookOwner), flagged);
        hook = VolumeDiscountHook(flagged);

        (key,) = initPool(currency0, currency1, IHooks(flagged), LPFeeLibrary.DYNAMIC_FEE_FLAG, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -6000, tickUpper: 6000, liquidityDelta: 100_000e18, salt: 0}), ZERO_BYTES
        );
    }

    // ------------------------------------------------------------ helpers for cases

    /// @notice Swap through the test router, naming `trader` in hookData the way a router would.
    /// @return amount0 amount1 The swapper's balance change in each token (negative = paid).
    function swapAs(address trader, bool zeroForOne, int256 amountSpecified) internal returns (int128 amount0, int128 amount1) {
        BalanceDelta d = swap(key, zeroForOne, amountSpecified, abi.encode(trader));
        return (d.amount0(), d.amount1());
    }

    /// @notice Swap with no hookData; the hook credits the router as the trader.
    function swapAnonymously(bool zeroForOne, int256 amountSpecified) internal returns (int128 amount0, int128 amount1) {
        BalanceDelta d = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        return (d.amount0(), d.amount1());
    }

    /// @notice Replace the hook's tiers as its owner.
    function setTiers(uint128[] memory minVolumes, uint24[] memory fees) internal {
        VolumeDiscountHook.Tier[] memory t = new VolumeDiscountHook.Tier[](minVolumes.length);
        for (uint256 i = 0; i < minVolumes.length; i++) t[i] = VolumeDiscountHook.Tier({minVolume: minVolumes[i], fee: fees[i]});
        vm.prank(hookOwner);
        hook.setTiers(t);
    }

    /// @return The router address the hook sees as the trader for anonymous swaps.
    function router() internal view returns (address) {
        return address(swapRouter);
    }
}
