// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IZKCreditRegistry} from "./interfaces/IZKCreditRegistry.sol";

/// @title MockLendingProtocol
/// @notice Demonstrates one concrete use case for ZKCreditRegistry: an
///         *uncollateralized* loan, gated purely on a proven credit-score
///         threshold instead of posted collateral. This is the opposite of
///         typical over-collateralized DeFi lending, and is the whole point
///         of proving a credit score in the first place.
///
/// @dev Deliberately minimal: this is a demo of the ZK integration, not a
///      production lending protocol. In particular it has no interest, no
///      liquidation, and a single flat borrow limit for every eligible
///      address. See README > Security notes for what a real protocol would
///      still need on top of this (issuer-signed credentials, expiring
///      eligibility, tiered limits, etc).

contract MockLendingProtocol {
    IZKCreditRegistry public immutable registry;

    /// @notice Minimum credit-score threshold a borrower must have proven
    ///         via `registry` (see ZKCreditRegistry.proveEligibility).
    uint256 public immutable minimumScore;

    /// @notice Maximum outstanding principal a single eligible address may
    ///         hold at once.
    uint256 public immutable borrowLimit;

    /// @notice Outstanding principal owed by each borrower.
    mapping(address => uint256) public borrowed;

    event Funded(address indexed funder, uint256 amount);
    event Borrowed(address indexed borrower, uint256 amount);
    event Repaid(address indexed borrower, uint256 amount);

    error NotEligible();
    error BorrowLimitExceeded();
    error InsufficientLiquidity();
    error NoOutstandingLoan();
    error TransferFailed();

    constructor(IZKCreditRegistry _registry, uint256 _minimumScore, uint256 _borrowLimit) {
        registry = _registry;
        minimumScore = _minimumScore;
        borrowLimit = _borrowLimit;
    }

    /// @notice Adds ETH to the lending pool. Anyone can fund it; this mock
    ///         has no concept of lender shares or yield.
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    /// @notice Borrow `amount` of ETH, uncollateralized, if msg.sender has
    ///         proven a credit score >= minimumScore in the registry.
    function borrow(uint256 amount) external {
        if (!registry.isEligible(msg.sender, minimumScore)) revert NotEligible();

        uint256 newDebt = borrowed[msg.sender] + amount;
        if (newDebt > borrowLimit) revert BorrowLimitExceeded();
        if (address(this).balance < amount) revert InsufficientLiquidity();

        // Effects before interaction: state is updated before the ETH
        // transfer, so a malicious borrower's receive/fallback cannot
        // reenter borrow() against a stale, not-yet-updated debt balance.
        borrowed[msg.sender] = newDebt;

        emit Borrowed(msg.sender, amount);

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /// @notice Repay up to the caller's outstanding debt. Any ETH sent
    ///         beyond the outstanding debt is refunded immediately.
    function repay() external payable {
        uint256 debt = borrowed[msg.sender];
        if (debt == 0) revert NoOutstandingLoan();

        uint256 amount = msg.value > debt ? debt : msg.value;
        borrowed[msg.sender] = debt - amount;

        emit Repaid(msg.sender, amount);

        uint256 refund = msg.value - amount;
        if (refund > 0) {
            (bool success,) = msg.sender.call{value: refund}("");
            if (!success) revert TransferFailed();
        }
    }
}
