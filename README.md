# ZK Credit Score

A minimal protocol proving credit-score eligibility with a Zero-Knowledge Proof,
without ever revealing the exact score.

> Status: work in progress / portfolio project. Not audited, not production-ready.

## The problem

A lender wants to know: *"is this user's credit score at least 700?"*

The naive way requires revealing the exact score (742, say) to the lender.
That leaks more information than necessary — the lender only needs a yes/no
answer to the threshold question, not the precise number.

## The idea

The user proves, with a cryptographic Zero-Knowledge Proof:

> "I know a credit score that is within a realistic range, and that score is
> greater than or equal to the public threshold you asked about."

The proof reveals nothing else. The private score (`742`) never appears
anywhere — not in the proof, not on-chain, not in any log.

```
private input:  creditScore = 742      (never revealed)
public input:   minimumScore = 700     (the question being asked)
public output:  isEligible = 1         (the answer, and nothing more)
```

## How it works

```
User (knows creditScore privately)
        │
        ▼
  Circom circuit ──── enforces creditScore in [300, 850]
        │             and creditScore >= minimumScore
        ▼
  Groth16 proof  ──── a few hundred bytes, cheap to verify on-chain
        │
        ▼
  Solidity verifier ── pure cryptographic proof check
        │
        ▼
  ZKCreditRegistry ─── proof-specific safety: no replay, proof bound
                        to msg.sender, threshold cannot be forged
```

## Scope of this project

This is intentionally a **small, focused** project — it demonstrates the
core ZK proof pipeline end to end, not a full lending protocol. Specifically
in scope:

- a Circom circuit proving `creditScore >= minimumScore` (see
  [`circuits/`](circuits/))
- the full Groth16 workflow: compile, trusted setup, prove, verify
- a Solidity verifier + registry with real security analysis (replay
  protection, proof-to-address binding, access control)
- Foundry tests for the contracts

Out of scope, on purpose (documented here rather than half-built):

- a real credit score issuer with signed credentials — this version lets a
  user self-declare their score, so it demonstrates the ZK mechanics, not a
  production trust model
- a lending protocol built on top of eligibility
- a backend/API server

## Repository structure

```
zk-credit-score/
├── circuits/           Circom circuit + tests
│   ├── src/
│   ├── test/
│   └── inputs/
├── contracts/           Solidity verifier + registry + Foundry tests (WIP)
├── package.json
└── README.md
```

## Getting started

```bash
# circuit tests
npm --prefix circuits install
npm run circuit:test
```

Requires [`circom`](https://docs.circom.io/getting-started/installation/)
(the compiler) installed and available on your `PATH`.

## Security notes

- **Range constraint**: the circuit forces `creditScore` into a realistic
  `[300, 850]` range using bit-decomposition (`Num2Bits`) before any
  comparison, to prevent field-overflow tricks against circomlib's
  comparators.
- **Trusted setup**: Groth16 requires a circuit-specific trusted setup. This
  is a real trust assumption of the system — documented, not hidden.
- **Self-declared score**: in this reduced scope, the user supplies their own
  `creditScore` with no issuer signature. The system proves the *threshold
  logic* correctly, but does **not** prove the score is truthful. A
  production system would require a signed credential from a trusted score
  provider (see "Out of scope" above).

## License

MIT
