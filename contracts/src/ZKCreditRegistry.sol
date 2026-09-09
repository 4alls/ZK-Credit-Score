// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGroth16Verifier} from "./interfaces/IGroth16Verifier.sol";

/// @title ZKCreditRegistry
/// @notice Lets a user prove, with a Groth16 proof, that their private
///         credit score meets a public threshold -- without revealing the
///         score. Records the highest threshold each address has proven.
///
/// @dev Public signals produced by CreditScoreThreshold.circom, in order:
///        pubSignals[0] = isEligible   (always 1 for a valid proof)
///        pubSignals[1] = minimumScore (the threshold that was proven)
///        pubSignals[2] = userAddress  (the address the proof is bound to)
///
///      Security properties enforced here (see README > Security notes for
///      the full write-up):
///        - proof-to-address binding: pubSignals[2] must equal msg.sender,
///          so a proof intercepted in the mempool cannot be resubmitted by
///          a different address ("front-running" / proof theft).
///        - replay protection: each distinct proof can be consumed once.
///        - threshold integrity: the stored threshold is read directly from
///          the verified public signal, never from a separate, untrusted
///          function argument.
///        - no admin backdoor: the verifier address is immutable.
contract ZKCreditRegistry {
    /// @notice The Groth16 verifier for the CreditScoreThreshold circuit.
    /// @dev Immutable: nobody, including this contract's deployer, can swap
    ///      it out after deployment for a verifier that accepts forged proofs.
    IGroth16Verifier public immutable verifier;

    /// @notice Highest credit-score threshold each address has proven, 0 if none.
    mapping(address => uint256) public provenThreshold;

    /// @notice Tracks proofs that have already been consumed, keyed by a
    ///         hash of their (pA, pB, pC) components, to prevent replay.
    mapping(bytes32 => bool) public usedProofs;

    event EligibilityProven(address indexed user, uint256 minimumScore);

    error InvalidProof();
    error ProofAlreadyUsed();
    error ProofNotBoundToSender();

    constructor(IGroth16Verifier _verifier) {
        verifier = _verifier;
    }

    /// @notice Submit a Groth16 proof that msg.sender's private credit score
    ///         is >= the public minimumScore encoded in the proof.
    /// @param pA First component of the Groth16 proof.
    /// @param pB Second component of the Groth16 proof.
    /// @param pC Third component of the Groth16 proof.
    /// @param pubSignals [isEligible, minimumScore, userAddress] -- the exact
    ///        public signals the proof was generated against. minimumScore
    ///        is taken from here, never from a separate argument, so it
    ///        cannot be forged independently of what was actually proven.
    function proveEligibility(
        uint256[2] calldata pA,
        uint256[2][2] calldata pB,
        uint256[2] calldata pC,
        uint256[3] calldata pubSignals
    ) external {
        if (pubSignals[2] != uint256(uint160(msg.sender))) {
            revert ProofNotBoundToSender();
        }

        bytes32 proofHash = keccak256(abi.encode(pA, pB, pC));
        if (usedProofs[proofHash]) {
            revert ProofAlreadyUsed();
        }

        if (!verifier.verifyProof(pA, pB, pC, pubSignals)) {
            revert InvalidProof();
        }

        usedProofs[proofHash] = true;

        uint256 minimumScore = pubSignals[1];
        if (minimumScore > provenThreshold[msg.sender]) {
            provenThreshold[msg.sender] = minimumScore;
        }

        emit EligibilityProven(msg.sender, minimumScore);
    }

    /// @notice Whether `user` has proven a credit score >= `threshold`.
    function isEligible(address user, uint256 threshold) external view returns (bool) {
        return provenThreshold[user] >= threshold;
    }
}
