// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ZKCreditRegistry} from "../src/ZKCreditRegistry.sol";
import {IGroth16Verifier} from "../src/interfaces/IGroth16Verifier.sol";
import {Groth16Verifier} from "../src/verifiers/CreditScoreVerifier.sol";

/// @notice Tests ZKCreditRegistry against a real Groth16 proof, generated
///         once offline by the circuits/ pipeline (npm run circuit:prove
///         with circuits/inputs/example.json) and pinned here as calldata.
///
///         Fixture statement: "I know a creditScore in [300, 850] that is
///         >= 700, and this proof is bound to address(1)." The private
///         creditScore (742) used to generate it never appears below.
contract ZKCreditRegistryTest is Test {
    ZKCreditRegistry internal registry;

    // The address the fixture proof below is bound to (userAddress=1 in
    // circuits/inputs/example.json).
    address internal constant ALICE = address(1);
    address internal constant MALLORY = address(2);

    uint256[2] internal pA = [
        0x1199c115c05e293563dd2e892f6b2d89922f116f40a9814b6e17a8f7d9416861,
        0x207f68d63f5c055da1ea2bd2784c53a6a8aee11f6c884caadec0d914843037a2
    ];
    uint256[2][2] internal pB = [
        [
            0x2079c87211068918bb7ace48a79d297a7276536f4fa973de5160acf7e5fb070e,
            0x1b7692ae92483078c0f2043c0a9ef52e6a7afddb3784b55b8d13cb4876189fa5
        ],
        [
            0x0b5aee2165ea9f08b7eb1570a5aa0005c4f69e16543bf9f83374bdc96cbd9ce5,
            0x10109bd9b663582c397fd14e0fa0aa9382957e410d4f89f138f17a2a91e57dae
        ]
    ];
    uint256[2] internal pC = [
        0x142ac5b2459473f2af84dc8207c1607cbb07bbc5515b932ebe1f2b9fbdacbd2d,
        0x22fa53f1d1e42a119807007b78d67c5687d397ced83e0e4b7e794d4d51aff8c5
    ];
    // [isEligible, minimumScore, userAddress] = [1, 700, 1]
    uint256[3] internal pubSignals = [uint256(1), uint256(700), uint256(1)];

    function setUp() public {
        IGroth16Verifier verifier = IGroth16Verifier(address(new Groth16Verifier()));
        registry = new ZKCreditRegistry(verifier);
    }

    function test_ValidProof_RecordsProvenThreshold() public {
        vm.prank(ALICE);
        registry.proveEligibility(pA, pB, pC, pubSignals);

        assertEq(registry.provenThreshold(ALICE), 700);
        assertTrue(registry.isEligible(ALICE, 700));
        assertTrue(registry.isEligible(ALICE, 600));
        assertFalse(registry.isEligible(ALICE, 701));
    }

    function test_ValidProof_EmitsEvent() public {
        vm.expectEmit(true, false, false, true, address(registry));
        emit ZKCreditRegistry.EligibilityProven(ALICE, 700);

        vm.prank(ALICE);
        registry.proveEligibility(pA, pB, pC, pubSignals);
    }

    /// A copied proof cannot be claimed by an address other than the one it
    /// was generated for -- this is the front-running / proof-theft defense.
    function test_CopiedProof_RevertsWhenSubmittedByAnotherAddress() public {
        vm.prank(MALLORY);
        vm.expectRevert(ZKCreditRegistry.ProofNotBoundToSender.selector);
        registry.proveEligibility(pA, pB, pC, pubSignals);
    }

    /// Even if an attacker rewrites the userAddress public signal to pass
    /// the binding check, the proof no longer verifies: Groth16 soundness
    /// means the proof is bound to the *exact* public signals it was
    /// generated with, not just the parts a naive contract might check.
    function test_TamperedUserAddressSignal_RevertsAsInvalidProof() public {
        uint256[3] memory tampered = [uint256(1), uint256(700), uint256(uint160(MALLORY))];

        vm.prank(MALLORY);
        vm.expectRevert(ZKCreditRegistry.InvalidProof.selector);
        registry.proveEligibility(pA, pB, pC, tampered);
    }

    /// Same defense applies to the threshold itself: a caller cannot claim
    /// a higher (or different) minimumScore than what was actually proven.
    function test_TamperedMinimumScoreSignal_RevertsAsInvalidProof() public {
        uint256[3] memory tampered = [uint256(1), uint256(900), uint256(1)];

        vm.prank(ALICE);
        vm.expectRevert(ZKCreditRegistry.InvalidProof.selector);
        registry.proveEligibility(pA, pB, pC, tampered);
    }

    /// Same defense applies to isEligible itself: a caller cannot flip a
    /// proof's public "eligible" output without invalidating the proof,
    /// even though the contract never checks pubSignals[0] directly -- it
    /// relies entirely on Groth16 soundness for this signal, exactly as it
    /// does for minimumScore and userAddress above.
    function test_TamperedIsEligibleSignal_RevertsAsInvalidProof() public {
        uint256[3] memory tampered = [uint256(0), uint256(700), uint256(1)];

        vm.prank(ALICE);
        vm.expectRevert(ZKCreditRegistry.InvalidProof.selector);
        registry.proveEligibility(pA, pB, pC, tampered);
    }

    function test_SameProof_CannotBeSubmittedTwice() public {
        vm.prank(ALICE);
        registry.proveEligibility(pA, pB, pC, pubSignals);

        vm.prank(ALICE);
        vm.expectRevert(ZKCreditRegistry.ProofAlreadyUsed.selector);
        registry.proveEligibility(pA, pB, pC, pubSignals);
    }

    function test_CorruptedProofBytes_RevertAsInvalidProof() public {
        uint256[2] memory corruptedA = [pA[0] + 1, pA[1]];

        vm.prank(ALICE);
        vm.expectRevert(ZKCreditRegistry.InvalidProof.selector);
        registry.proveEligibility(corruptedA, pB, pC, pubSignals);
    }

    function test_UnprovenAddress_IsNotEligible() public view {
        assertFalse(registry.isEligible(MALLORY, 300));
        assertEq(registry.provenThreshold(MALLORY), 0);
    }

    /// isEligible must agree with a plain >= comparison against the proven
    /// threshold for every possible query threshold, not just the few
    /// values exercised above.
    function testFuzz_IsEligible_MatchesProvenThreshold(uint256 threshold) public {
        vm.prank(ALICE);
        registry.proveEligibility(pA, pB, pC, pubSignals);

        assertEq(registry.isEligible(ALICE, threshold), threshold <= 700);
    }
}
