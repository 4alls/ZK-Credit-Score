pragma circom 2.1.6;

include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/bitify.circom";

// CreditScoreThreshold
//
// Proves that a private credit score satisfies a public minimum threshold,
// without revealing the score itself.
//
//   private input : creditScore    e.g. 742
//   public input  : minimumScore   e.g. 700
//   public output : isEligible     1 iff creditScore >= minimumScore
//
// The circuit also enforces that creditScore lies within a realistic
// FICO-like range [300, 850]. Without this, a prover could pick an
// out-of-range value (e.g. a negative number represented as a huge field
// element) to try to game the comparator below.
template CreditScoreThreshold() {
    var MIN_SCORE = 300;
    var MAX_SCORE = 850;
    // 2^10 = 1024 comfortably covers MAX_SCORE (850) while staying small,
    // which keeps circomlib's comparators inside their safe operating range.
    var BITS = 10;

    signal input creditScore;   // private
    signal input minimumScore;  // public
    signal output isEligible;   // public

    // --- Step 1: bind both operands to BITS bits before comparing them. ---
    //
    // circomlib's LessEqThan/GreaterEqThan compute in[0] + 2^n - in[1] and
    // inspect its (n+1)-th bit. That trick is only sound when in[0] and
    // in[1] are already known to be < 2^n. If a malicious prover supplied
    // an unconstrained field element close to the field modulus, the
    // subtraction could wrap around and forge a false "greater-or-equal"
    // result. Num2Bits(BITS) closes that gap: it forces creditScore and
    // minimumScore to have an exact BITS-bit decomposition, which is only
    // satisfiable for values in [0, 2^BITS).
    component creditScoreBits = Num2Bits(BITS);
    creditScoreBits.in <== creditScore;

    component minimumScoreBits = Num2Bits(BITS);
    minimumScoreBits.in <== minimumScore;

    // --- Step 2: enforce the realistic score range [MIN_SCORE, MAX_SCORE]. ---
    component geMin = GreaterEqThan(BITS);
    geMin.in[0] <== creditScore;
    geMin.in[1] <== MIN_SCORE;
    geMin.out === 1;

    component leMax = LessEqThan(BITS);
    leMax.in[0] <== creditScore;
    leMax.in[1] <== MAX_SCORE;
    leMax.out === 1;

    // --- Step 3: the actual eligibility check. ---
    component ge = GreaterEqThan(BITS);
    ge.in[0] <== creditScore;
    ge.in[1] <== minimumScore;

    isEligible <== ge.out;
    // Forcing the output to 1 means a witness (and therefore a proof) can
    // only be produced when the prover really is eligible. An ineligible
    // prover cannot generate a valid proof at all, rather than generating
    // one that a verifier must additionally check for isEligible == 1.
    isEligible === 1;
}

component main { public [minimumScore] } = CreditScoreThreshold();
