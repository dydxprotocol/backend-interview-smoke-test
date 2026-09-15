// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Exists only to prove solc 0.8.35 compiles on this machine via the
/// Foundry image the interview project uses.
contract Smoke {
    uint256 public counter;

    event Ticked(uint256 indexed value);

    function tick() external returns (uint256) {
        counter += 1;
        emit Ticked(counter);
        return counter;
    }
}
