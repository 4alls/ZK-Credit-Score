// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Interface for the snarkjs-generated Groth16 verifier.
/// @dev Matches the signature snarkjs emits for a 3-public-signal circuit:
///      [isEligible, minimumScore, userAddress].
interface IGroth16Verifier {
    function verifyProof(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[3] calldata pubSignals
    ) external view returns (bool);
}
