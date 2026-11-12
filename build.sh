#!/bin/sh
# Build and test.  FPC=<compiler> CC=<C compiler> sh build.sh [extra C flags]
# The C object must not need libgcc (no 64-bit division, etc.): checked with nm -u.
set -eu
cd "$(dirname "$0")"; HERE=.; OUT=${B3_OUT:-build}   # relative paths: a native Windows fpc cannot read MSYS paths
FPC=${FPC:-fpc}; CC=${CC:-cc}; NM=${NM:-nm}; RUN=${RUN:-}   # RUN: a prefix for the test programs (qemu-ppc64 ...)
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
if command -v "$NM" >/dev/null; then
  bad=$($NM -u "$OUT/b3chunks.o" | grep -E '__(u?div|u?mod|ctz|clz|popcount)[a-z]*[0-9]|___?chkstk|memcpy|memset' || true)
  if [ -n "$bad" ]; then echo "b3chunks.o needs the runtime:"; echo "$bad"; exit 1; fi
  echo "$NM -u: b3chunks.o needs nothing"
fi
# the chunk routine (SSE2 / NEON where there is one) against the plain one, and how fast each is; not for cross builds
if [ -z "$RUN" ]; then
  # shellcheck disable=SC2086
  $CC $FLAGS "$@" -DB3_PLAIN -Dpblake3_chunks=pblake3_chunks_plain -Dpblake3_chunks_level=pblake3_chunks_level_plain -c "$HERE/src/b3chunks.c" -o "$OUT/b3plain.o"
  # shellcheck disable=SC2086
  $CC -O2 "$@" "$HERE/tests/chunks_diff.c" "$OUT/b3chunks.o" "$OUT/b3plain.o" -o "$OUT/chunks_diff$EXE"
  "$OUT/chunks_diff$EXE" | tr -d '\r' | tee "$OUT/diff.txt"
  grep -q ' 0 differences' "$OUT/diff.txt"
fi
$FPC -O3 -Fu"$HERE/src" -Fi"$HERE/src" -Fo"$OUT" -FU"$OUT" -o"$OUT/test_blake3$EXE" "$HERE/tests/test_blake3.pas" >"$OUT/fpc.log" 2>&1 \
  || { cat "$OUT/fpc.log"; exit 1; }
$RUN "$OUT/test_blake3$EXE" "$HERE/tests/kat.txt" | tr -d '\r' | tail -3
$RUN "$OUT/test_blake3$EXE" "$HERE/tests/kat.txt" | tr -d '\r' | grep -q ' 0 failures'
$FPC -O3 -Fu"$HERE/src" -Fi"$HERE/src" -Fo"$OUT" -FU"$OUT" -o"$OUT/test_official$EXE" "$HERE/tests/test_official.pas" >"$OUT/fpc2.log" 2>&1 \
  || { cat "$OUT/fpc2.log"; exit 1; }
$RUN "$OUT/test_official$EXE" "$HERE/tests/official_hash.txt" | tr -d '\r' | tee "$OUT/off.txt" | tail -3
grep -q ' 0 failures' "$OUT/off.txt"
# the command line tool, on a few threads (not for the cross builds: no libc there for the threads)
if [ -z "$RUN" ]; then
  $FPC -O3 -Fu"$HERE/src" -Fi"$HERE/src" -Fo"$OUT" -FU"$OUT" -o"$OUT/b3sum$EXE" "$HERE/src/b3sum.pas" >"$OUT/fpc3.log" 2>&1 \
    || { cat "$OUT/fpc3.log"; exit 1; }
  got=$(printf abc | "$OUT/b3sum$EXE" --no-names | tr -d '\r')
  [ "$got" = 6437b3ac38465133ffb63b75273a8db548c558465d79db03fd359c6cd5bd9d85 ] || { echo "b3sum of abc: $got"; exit 1; }
  # threads or not, the same hash (the tool's own file is big enough for the threads to engage after 256 KiB)
  cat "$OUT/b3sum$EXE" "$OUT/b3sum$EXE" "$OUT/b3sum$EXE" "$OUT/b3sum$EXE" "$OUT/b3sum$EXE" > "$OUT/big.bin"
  one=$("$OUT/b3sum$EXE" --num-threads 1 "$OUT/big.bin" | tr -d '\r'); four=$("$OUT/b3sum$EXE" --num-threads 4 "$OUT/big.bin" | tr -d '\r')
  [ "$one" = "$four" ] || { echo "b3sum: 1 thread and 4 threads differ"; exit 1; }
  $FPC -O3 -Fu"$HERE/src" -Fi"$HERE/src" -Fo"$OUT" -FU"$OUT" -o"$OUT/fuzz_split$EXE" "$HERE/tests/fuzz_split.pas" >"$OUT/fpc4.log" 2>&1 \
    || { cat "$OUT/fpc4.log"; exit 1; }
  "$OUT/fuzz_split$EXE" "${B3_FUZZ:-60}" | tr -d '\r' | tail -3 | tee "$OUT/fuzz.txt"; grep -q ' 0 failures' "$OUT/fuzz.txt"
  echo "b3sum: abc ok, 1 thread = 4 threads ($(wc -c < "$OUT/big.bin" | tr -d ' ') bytes)"
fi
