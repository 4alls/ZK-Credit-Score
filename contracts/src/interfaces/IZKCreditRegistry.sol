// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal read interface a downstream protocol needs from
///         ZKCreditRegistry to gate access on proven eligibility.
interface IZKCreditRegistry {
    function isEligible(address user, uint256 threshold) external view returns (bool);
}
