// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockLendingProtocol} from "../src/MockLendingProtocol.sol";
import {ZKCreditRegistry} from "../src/ZKCreditRegistry.sol";
import {IGroth16Verifier} from "../src/interfaces/IGroth16Verifier.sol";
import {IZKCreditRegistry} from "../src/interfaces/IZKCreditRegistry.sol";
import {Groth16Verifier} from "../src/verifiers/CreditScoreVerifier.sol";

/// @notice Same real Groth16 proof fixture as ZKCreditRegistry.t.sol (see
///         that file for how it was generated) -- bound to ALICE, proving a
///         threshold of 700.
contract MockLendingProtocolTest is Test {
    ZKCreditRegistry internal registry;
    MockLendingProtocol internal lending;

    address internal constant ALICE = address(1);
    address internal constant BOB = address(2);

    uint256 internal constant MIN_SCORE = 700;
    uint256 internal constant BORROW_LIMIT = 1 ether;

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
    uint256[3] internal pubSignals = [uint256(1), uint256(700), uint256(1)];

    function setUp() public {
        IGroth16Verifier verifier = IGroth16Verifier(address(new Groth16Verifier()));
        registry = new ZKCreditRegistry(verifier);
        lending =
            new MockLendingProtocol(IZKCreditRegistry(address(registry)), MIN_SCORE, BORROW_LIMIT);

        // Fund the pool.
        vm.deal(address(this), 10 ether);
        (bool ok,) = address(lending).call{value: 5 ether}("");
        require(ok, "funding failed");

        // Make ALICE eligible via a real proof.
        vm.prank(ALICE);
        registry.proveEligibility(pA, pB, pC, pubSignals);

        // ALICE needs her own ETH to test repay() overpayment/refund --
        // borrow() alone only ever gives her up to BORROW_LIMIT.
        vm.deal(ALICE, 10 ether);
    }

    function test_EligibleUser_CanBorrowUncollateralized() public {
        uint256 aliceBalanceBefore = ALICE.balance;

        vm.prank(ALICE);
        lending.borrow(0.5 ether);

        assertEq(lending.borrowed(ALICE), 0.5 ether);
        assertEq(ALICE.balance, aliceBalanceBefore + 0.5 ether);
    }

    function test_IneligibleUser_CannotBorrow() public {
        vm.prank(BOB);
        vm.expectRevert(MockLendingProtocol.NotEligible.selector);
        lending.borrow(0.1 ether);
    }

    function test_Borrow_RevertsBeyondBorrowLimit() public {
        vm.startPrank(ALICE);
        lending.borrow(BORROW_LIMIT);

        vm.expectRevert(MockLendingProtocol.BorrowLimitExceeded.selector);
        lending.borrow(1);
        vm.stopPrank();
    }

    function test_Borrow_RevertsWhenPoolLacksLiquidity() public {
        // A separate, unfunded pool: BORROW_LIMIT alone would allow this
        // request, but there is no liquidity to actually lend out.
        MockLendingProtocol emptyPool =
            new MockLendingProtocol(IZKCreditRegistry(address(registry)), MIN_SCORE, BORROW_LIMIT);

        vm.prank(ALICE);
        vm.expectRevert(MockLendingProtocol.InsufficientLiquidity.selector);
        emptyPool.borrow(0.1 ether);
    }

    function test_Repay_ReducesOutstandingDebt() public {
        vm.startPrank(ALICE);
        lending.borrow(0.5 ether);

        lending.repay{value: 0.2 ether}();
        assertEq(lending.borrowed(ALICE), 0.3 ether);
        vm.stopPrank();
    }

    function test_Repay_RefundsAmountBeyondDebt() public {
        vm.startPrank(ALICE);
        lending.borrow(0.5 ether);

        uint256 balanceBeforeRepay = ALICE.balance;
        lending.repay{value: 2 ether}();

        assertEq(lending.borrowed(ALICE), 0);
        // Paid 0.5 to clear debt, got 1.5 refunded back.
        assertEq(ALICE.balance, balanceBeforeRepay - 0.5 ether);
        vm.stopPrank();
    }

    function test_Repay_RevertsWithNoOutstandingLoan() public {
        vm.prank(ALICE);
        vm.expectRevert(MockLendingProtocol.NoOutstandingLoan.selector);
        lending.repay{value: 0.1 ether}();
    }

    function test_EligibleUser_CanBorrowAgainAfterRepaying() public {
        vm.startPrank(ALICE);
        lending.borrow(BORROW_LIMIT);
        lending.repay{value: BORROW_LIMIT}();
        lending.borrow(BORROW_LIMIT);
        vm.stopPrank();

        assertEq(lending.borrowed(ALICE), BORROW_LIMIT);
    }
}
