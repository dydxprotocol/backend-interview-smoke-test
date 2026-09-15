// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";

import {Smoke} from "../src/Smoke.sol";

contract SmokeTest is Test {
    function test_tick() public {
        Smoke s = new Smoke();
        assertEq(s.tick(), 1);
        assertEq(s.tick(), 2);
        assertEq(s.counter(), 2);
    }
}
