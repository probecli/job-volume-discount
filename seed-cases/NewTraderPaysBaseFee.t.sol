// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ProbeCase} from "../ProbeCase.sol";

/// A trader with no volume pays the 0.30% base fee, and the swap is credited to them.
contract NewTraderPaysBaseFee is ProbeCase {
    function test_newTraderPaysBaseFee() public {
        assertEq(hook.feeFor(alice), 3_000, "base fee before any volume");
        (int128 paid0,) = swapAs(alice, true, -10e18);
        assertEq(hook.volume(alice), uint256(uint128(-paid0)), "volume credited to alice");
        assertEq(hook.feeFor(alice), 3_000, "still below the first tier");
    }
}
