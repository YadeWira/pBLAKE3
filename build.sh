#!/bin/sh
# Build and test.  FPC=<compiler> CC=<C compiler> sh build.sh [extra C flags]
# The C object must not need libgcc (no 64-bit division, etc.): checked with nm -u.
set -eu
cd "$(dirname "$0")"; HERE=.; OUT=${B3_OUT:-build}   # relative paths: a native Windows fpc cannot read MSYS paths
FPC=${FPC:-fpc}; CC=${CC:-cc}
case $CC in /*) PATH=$(dirname "${CC%% *}"):$PATH; export PATH ;; esac
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) EXE=.exe ;; *) EXE= ;; esac
rm -rf "$OUT"; mkdir -p "$OUT"
FLAGS="-O3 -fwrapv -ffp-contract=off -fno-stack-protector"
if $CC --version 2>/dev/null | grep -qi clang; then FLAGS="$FLAGS -fno-builtin"
else FLAGS="$FLAGS -fno-tree-loop-distribute-patterns"; fi
case "$CC $* $($CC -dumpmachine 2>/dev/null || true)" in
  *-m32*|*i686*|*i386*|*i586*) FLAGS="$FLAGS -fno-pic -march=i686" ;;
esac
# shellcheck disable=SC2086
$CC $FLAGS "$@" -c "$HERE/src/b3chunks.c" -o "$OUT/b3chunks.o"
if command -v nm >/dev/null; then
  bad=$(nm -u "$OUT/b3chunks.o" | grep -E '__(u?div|u?mod|ctz|clz|popcount)[a-z]*[0-9]|___?chkstk|memcpy|memset' || true)
  if [ -n "$bad" ]; then echo "b3chunks.o needs the runtime:"; echo "$bad"; exit 1; fi
  echo "nm -u: b3chunks.o needs nothing"
fi
$FPC -O3 -Fu"$HERE/src" -Fi"$HERE/src" -Fo"$OUT" -FU"$OUT" -o"$OUT/test_blake3$EXE" "$HERE/tests/test_blake3.pas" >"$OUT/fpc.log" 2>&1 \
  || { cat "$OUT/fpc.log"; exit 1; }
"$OUT/test_blake3$EXE" "$HERE/tests/kat.txt" | tr -d '\r' | tail -3
"$OUT/test_blake3$EXE" "$HERE/tests/kat.txt" | tr -d '\r' | grep -q ' 0 failures'
