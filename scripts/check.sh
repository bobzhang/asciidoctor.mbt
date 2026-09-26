#!/bin/sh
# Full validation: type-check (all targets), unit tests, golden parity, and
# (with --corpus) byte-for-byte comparison with Ruby on the docs corpus.
set -e
cd "$(dirname "$0")/.."
moon check --target all
moon test
moon test --target native
moon build --target native cmd/golden
./_build/native/debug/build/cmd/golden/golden.exe | tail -2
if [ "$1" = "--corpus" ]; then
  scripts/corpus_compare.sh | tail -1
fi
