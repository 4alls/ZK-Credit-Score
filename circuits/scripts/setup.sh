#!/usr/bin/env bash
# Groth16 trusted setup for the CreditScoreThreshold circuit.
#
# WARNING: this generates a toy, single-contributor setup. It is fine for a
# local demo / portfolio project, but it is NOT a secure trusted setup.
# A production system must use a public multi-party ceremony (e.g. the
# Hermez/Polygon Powers of Tau ceremony) so that the "1-of-N honesty"
# assumption actually holds. See README.md > Security notes.
set -euo pipefail
cd "$(dirname "$0")/.."

SNARKJS=./node_modules/.bin/snarkjs
CIRCUIT=creditScoreThreshold
BUILD=build

mkdir -p "$BUILD"

if [ ! -f "$BUILD/$CIRCUIT.r1cs" ]; then
  echo "R1CS not found, compiling circuit first..."
  npm run circuit:compile
fi

echo "== Phase 1: Powers of Tau (generic, circuit-independent) =="
$SNARKJS powersoftau new bn128 12 "$BUILD/pot12_0000.ptau" -v
$SNARKJS powersoftau contribute "$BUILD/pot12_0000.ptau" "$BUILD/pot12_0001.ptau" \
  --name="Dev contribution (toy setup)" -v -e="$(openssl rand -hex 32)"
$SNARKJS powersoftau prepare phase2 "$BUILD/pot12_0001.ptau" "$BUILD/pot12_final.ptau" -v

echo "== Phase 2: circuit-specific setup =="
$SNARKJS groth16 setup "$BUILD/$CIRCUIT.r1cs" "$BUILD/pot12_final.ptau" "$BUILD/${CIRCUIT}_0000.zkey"
$SNARKJS zkey contribute "$BUILD/${CIRCUIT}_0000.zkey" "$BUILD/${CIRCUIT}_final.zkey" \
  --name="Dev contribution (toy setup)" -v -e="$(openssl rand -hex 32)"

echo "== Exporting verification key =="
$SNARKJS zkey export verificationkey "$BUILD/${CIRCUIT}_final.zkey" verification_key.json

# Intermediate ceremony files are not needed once the final zkey exists.
rm -f "$BUILD/pot12_0000.ptau" "$BUILD/pot12_0001.ptau" "$BUILD/${CIRCUIT}_0000.zkey"

echo "Setup complete: $BUILD/${CIRCUIT}_final.zkey"
