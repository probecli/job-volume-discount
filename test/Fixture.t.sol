// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ProbeCase} from "./ProbeCase.sol";

/// Sanity checks that the snapshot is what the job spec says.
contract FixtureTest is ProbeCase {
    function test_snapshotIsPinned() public view {
        assertEq(block.number, 5200000);
        assertEq(hook.tierCount(), 2);
        assertEq(hook.feeFor(alice), hook.BASE_FEE());
    }

    function test_swapCreditsNamedTrader() public {
        (int128 paid,) = swapAs(alice, true, -10e18);
        assertEq(hook.volume(alice), uint256(uint128(-paid)));
    }
}
