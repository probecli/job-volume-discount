// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {BaseTestHooks} from "v4-core/src/test/BaseTestHooks.sol";

/// @notice Test target for a PROBE job. NOT FOR PRODUCTION.
///
/// A dynamic-fee hook that rewards volume: every trader starts at the base
/// fee and moves to cheaper tiers as their cumulative swap volume grows.
/// Routers identify the trader by passing their address as hookData; swaps
/// without it are credited to the router itself.
///
/// It contains a deliberate bug for the job: the trader address in hookData
/// is trusted without any check, so any swapper can claim another trader's
/// volume tier and credit volume to an address that never swapped.
contract VolumeDiscountHook is BaseTestHooks {
    struct Tier {
        uint128 minVolume;
        uint24 fee;
    }

    IPoolManager public immutable manager;
    address public immutable owner;

    uint24 public constant BASE_FEE = 3_000; // 0.30%, in hundredths of a bip

    Tier[] internal tiers; // ascending minVolume, falling fee
    mapping(address => uint256) public volume; // cumulative input amount, raw token units

    event TiersSet(uint256 count);
    event VolumeCredited(address indexed trader, uint256 amount, uint256 total);

    error NotOwner();
    error NotManager();
    error BadTiers();

    constructor(IPoolManager _manager, address _owner) {
        manager = _manager;
        owner = _owner;
        tiers.push(Tier({minVolume: 100e18, fee: 2_500}));
        tiers.push(Tier({minVolume: 1_000e18, fee: 1_000}));
    }

    /// @notice Replace the volume tiers. Volumes must rise and fees must fall, never above the base fee.
    function setTiers(Tier[] calldata next) external {
        if (msg.sender != owner) revert NotOwner();
        uint24 lastFee = BASE_FEE;
        uint128 lastVolume = 0;
        for (uint256 i = 0; i < next.length; i++) {
            if (next[i].minVolume <= lastVolume || next[i].fee >= lastFee) revert BadTiers();
            lastVolume = next[i].minVolume;
            lastFee = next[i].fee;
        }
        delete tiers;
        for (uint256 i = 0; i < next.length; i++) tiers.push(next[i]);
        emit TiersSet(next.length);
    }

    function tierCount() external view returns (uint256) {
        return tiers.length;
    }

    /// @notice The fee a trader pays on their next swap.
    function feeFor(address trader) public view returns (uint24) {
        uint256 v = volume[trader];
        for (uint256 i = tiers.length; i > 0; i--) {
            if (v >= tiers[i - 1].minVolume) return tiers[i - 1].fee;
        }
        return BASE_FEE;
    }

    function beforeSwap(address sender, PoolKey calldata, SwapParams calldata, bytes calldata hookData)
        external
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (msg.sender != address(manager)) revert NotManager();
        uint24 fee = feeFor(_trader(sender, hookData));
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    function afterSwap(address sender, PoolKey calldata, SwapParams calldata params, BalanceDelta delta, bytes calldata hookData)
        external
        override
        returns (bytes4, int128)
    {
        if (msg.sender != address(manager)) revert NotManager();
        int128 paid = params.zeroForOne ? delta.amount0() : delta.amount1();
        if (paid < 0) {
            address trader = _trader(sender, hookData);
            uint256 amount = uint256(uint128(-paid));
            volume[trader] += amount;
            emit VolumeCredited(trader, amount, volume[trader]);
        }
        return (this.afterSwap.selector, 0);
    }

    function _trader(address sender, bytes calldata hookData) internal pure returns (address) {
        // BUG (deliberate): trusts whatever address the caller supplies.
        if (hookData.length == 32) return abi.decode(hookData, (address));
        return sender;
    }
}
