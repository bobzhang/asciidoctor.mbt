#!/bin/sh
# Converts every .adoc under a directory with Ruby Asciidoctor and the MoonBit
# port (embedded HTML, safe mode) and reports files whose output differs.
# Usage: scripts/corpus_compare.sh [DIR]
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=${1:-$ROOT/.repos/asciidoctor/docs}
OUT=${OUT:-/tmp/asciidoctor-corpus}
rm -rf "$OUT"; mkdir -p "$OUT/rb" "$OUT/mbt"
export SOURCE_DATE_EPOCH=1700000000 TZ=UTC
(cd "$ROOT" && moon build --target native cmd/asciidoctor >/dev/null 2>&1)
BIN=$ROOT/_build/native/debug/build/cmd/asciidoctor/asciidoctor.exe
total=0; same=0
for f in $(find "$DIR" -name '*.adoc' | sort); do
  total=$((total+1))
  key=$(echo "$f" | sed "s|$DIR/||; s|/|__|g")
  (cd "$(dirname "$f")" && ruby -I"$ROOT/.repos/asciidoctor/lib" "$ROOT/.repos/asciidoctor/bin/asciidoctor" -S safe -b ${BACKEND:-html5} ${EMBEDDED--s} -o - "$f" > "$OUT/rb/$key.html" 2>"$OUT/rb/$key.err") || true
  (cd "$(dirname "$f")" && "$BIN" -S safe -b ${BACKEND:-html5} ${EMBEDDED--s} -o - "$f" > "$OUT/mbt/$key.html" 2>"$OUT/mbt/$key.err") || true
  if cmp -s "$OUT/rb/$key.html" "$OUT/mbt/$key.html"; then same=$((same+1)); else echo "DIFF $key"; fi
done
echo "identical: $same / $total"
