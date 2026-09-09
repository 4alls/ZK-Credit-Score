#!/usr/bin/env bash
# Verify a Groth16 proof locally (off-chain) against verification_key.json.
set -euo pipefail
cd "$(dirname "$0")/.."

SNARKJS=./node_modules/.bin/snarkjs
BUILD=build

if [ ! -f verification_key.json ]; then
  echo "verification_key.json not found. Run 'npm run circuit:setup' first." >&2
  exit 1
fi

$SNARKJS groth16 verify verification_key.json "$BUILD/public.json" "$BUILD/proof.json"
