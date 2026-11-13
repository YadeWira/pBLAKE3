#!/bin/sh
# The C code (the plain implementation and the chunk routines, every SIMD level this CPU has) under AddressSanitizer
# and UndefinedBehaviorSanitizer: the official vectors, and the vector levels against the plain one.   CC=gcc|clang
set -eu
cd "$(dirname "$0")/.."
CC=${CC:-gcc}; OUT=${B3_OUT:-build}/san; mkdir -p "$OUT"
SAN="-fsanitize=address,undefined -fno-sanitize-recover=undefined -g -O1 -fno-omit-frame-pointer"
# shellcheck disable=SC2086
$CC $SAN tests/static_test.c -o "$OUT/static_test"
"$OUT/static_test" tests/official_hash.txt | tail -2
# shellcheck disable=SC2086
$CC $SAN -c src/b3chunks.c -o "$OUT/bc.o"
# shellcheck disable=SC2086
$CC $SAN -DB3_PLAIN -Dpblake3_chunks=pblake3_chunks_plain -Dpblake3_chunks_level=pblake3_chunks_level_plain -Dpblake3_chunks_kf=pblake3_chunks_kf_plain -c src/b3chunks.c -o "$OUT/bp.o"
# shellcheck disable=SC2086
$CC $SAN tests/chunks_diff.c "$OUT/bc.o" "$OUT/bp.o" -o "$OUT/chunks_diff"
"$OUT/chunks_diff" | tee "$OUT/cd.txt" | grep -E "differences|level"
grep -q ' 0 differences' "$OUT/cd.txt"
# threads: each with its own state, the first call (SIMD detection) made by all of them at once
# shellcheck disable=SC2086
$CC -fsanitize=thread -g -O1 tests/tsan_threads.c -o "$OUT/tsan_threads" -lpthread
"$OUT/tsan_threads" 2>&1 | tee "$OUT/tsan.txt"
grep -q 'threads done' "$OUT/tsan.txt" && ! grep -q 'WARNING: ThreadSanitizer' "$OUT/tsan.txt"
