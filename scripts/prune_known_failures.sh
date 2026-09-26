#!/bin/sh
# Removes entries from tests/golden/known_failures.txt that now pass.
set -e
cd "$(dirname "$0")/.."
moon build --target native cmd/golden >/dev/null 2>&1
./_build/native/debug/build/cmd/golden/golden.exe -v -n 100000 | grep '^---- ' | sed 's/^---- //' > /tmp/golden_failing.$$
python3 - /tmp/golden_failing.$$ <<'PY'
import sys
failing=set(l.rstrip('\n') for l in open(sys.argv[1]))
out=[]
for line in open('tests/golden/known_failures.txt'):
    line=line.rstrip('\n')
    if line.startswith('#') or not line or line.split('\t',1)[1] in failing:
        out.append(line)
open('tests/golden/known_failures.txt','w').write('\n'.join(out)+'\n')
PY
rm -f /tmp/golden_failing.$$
./_build/native/debug/build/cmd/golden/golden.exe | tail -1
