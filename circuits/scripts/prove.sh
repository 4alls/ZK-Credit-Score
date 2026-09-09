#!/usr/bin/env bash
# Generate a Groth16 proof for a given input.
# Usage: ./scripts/prove.sh [path/to/input.json]
set -euo pipefail
cd "$(dirname "$0")/.."

SNARKJS=./node_modules/.bin/snarkjs
CIRCUIT=creditScoreThreshold
BUILD=build
INPUT="${1:-inputs/example.json}"

if [ ! -f "$BUILD/${CIRCUIT}_final.zkey" ]; then
  echo "Proving key not found. Run 'npm run circuit:setup' first." >&2
  exit 1
fi

echo "== Generating witness from $INPUT =="
node "$BUILD/${CIRCUIT}_js/generate_witness.js" \
  "$BUILD/${CIRCUIT}_js/${CIRCUIT}.wasm" "$INPUT" "$BUILD/witness.wtns"

echo "== Generating Groth16 proof =="
$SNARKJS groth16 prove "$BUILD/${CIRCUIT}_final.zkey" "$BUILD/witness.wtns" \
  "$BUILD/proof.json" "$BUILD/public.json"

echo "Proof:  $BUILD/proof.json"
echo "Public signals (isEligible, minimumScore): $BUILD/public.json"
cat "$BUILD/public.json"
