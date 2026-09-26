#!/bin/sh
# Regenerate golden fixtures under tests/golden/ by running the upstream test suite
# with scripts/harvest/harvest.rb loaded. Requires ruby + nokogiri; installs rouge/coderay
# into .repos/gems on first use.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
UP=$ROOT/.repos/asciidoctor
export GEM_HOME=$ROOT/.repos/gems
export GEM_PATH=$GEM_HOME:$(gem env gempath)
[ -d "$GEM_HOME/gems" ] && ls "$GEM_HOME/gems" | grep -q rouge || gem install --no-document 'rouge:~>3.0' 'coderay:~>1.1.0' 'asciimath:~>2.0'
export SOURCE_DATE_EPOCH=1700000000 TZ=UTC
mkdir -p "$ROOT/tests/golden"
cd "$UP"
for f in ${@:-test/*_test.rb}; do
  name=$(basename "$f" _test.rb)
  HARVEST_OUT="$ROOT/tests/golden/$name.jsonl" ruby -Ilib -Itest -r"$ROOT/scripts/harvest/harvest.rb" "$f" 2>&1 | grep -E "runs,|Error" | sed "s|^|$name: |"
done
