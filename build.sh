#!/bin/sh
# build + test: ./build.sh [CC flags, e.g. -m32]
set -e
HERE=$(cd "$(dirname "$0")" && pwd); OUT="$HERE/build"; CC=${CC:-cc}
mkdir -p "$OUT"
$CC -O3 -fwrapv -ffp-contract=off -fno-stack-protector "$@" -c "$HERE/src/b3chunks.c" -o "$OUT/b3chunks.o"
fpc -Mobjfpc -O2 -Fu"$HERE/src" -Fo"$OUT" -FE"$OUT" -Fl"$OUT" "$HERE/tests/test_blake3.pas" >"$OUT/fpc.log" 2>&1 || { tail -30 "$OUT/fpc.log"; exit 1; }
"$OUT/test_blake3" "$HERE/tests/kat.txt" | tail -3
