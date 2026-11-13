#!/bin/sh
# The plain C implementation on other CPUs under qemu-user: aarch64 (NEON) and ARM 32-bit with a cross libc
# (tests/static_test.c), and big-endian powerpc64 and s390x with no libc at all (tests/be_selftest.c).
# REQUIRE_ALL=1 (CI): a missing tool is an error, not a skip.
set -u
cd "$(dirname "$0")/.."
OUT=${B3_OUT:-build}/qemu; mkdir -p "$OUT"; fails=0; ran=0
python3 tests/be_vectors.py tests/official_hash.txt "$OUT/be_vectors.h"
have() { command -v "$1" >/dev/null 2>&1; }
skip() { if [ "${REQUIRE_ALL:-0}" = 1 ]; then echo "MISSING: $1"; fails=$((fails+1)); else echo "skip: $1"; fi; }
ok() { ran=$((ran+1)); if [ "$1" -ne 0 ]; then fails=$((fails+1)); echo "FAILED: $2"; else echo "ok: $2"; fi; }
for t in aarch64-linux-gnu:qemu-aarch64 arm-linux-gnueabihf:qemu-arm; do
  tc=${t%%:*}; q=${t##*:}
  if have $tc-gcc && have $q; then
    $tc-gcc -O2 -static tests/static_test.c -o "$OUT/st_$q" && $q "$OUT/st_$q" tests/official_hash.txt | tee "$OUT/st_$q.txt"
    grep -q ' 0 failures' "$OUT/st_$q.txt"; ok $? "$tc static (libc)"
  else skip "$tc / $q"; fi
done
for t in powerpc64-linux-gnu:qemu-ppc64:powerpc64 s390x-linux-gnu:qemu-s390x:s390x; do
  tc=${t%%:*}; rest=${t#*:}; q=${rest%%:*}; tg=${rest##*:}
  if have clang && have $tc-ld && have $q; then
    # the include of be_vectors.h comes from the build dir (a copy of tests/be_vectors.h would go stale)
    clang --target=$tc -ffreestanding -fno-builtin -fno-stack-protector -O2 -I"$OUT" -c tests/be_selftest.c -o "$OUT/be_$tg.o" &&
      $tc-ld -static -nostdlib -e _start "$OUT/be_$tg.o" -o "$OUT/be_$tg" && $q "$OUT/be_$tg" | tee "$OUT/be_$tg.txt"
    grep -q ' 0 failures' "$OUT/be_$tg.txt"; ok $? "$tg big-endian (no libc)"
  else skip "$tc / $q / clang"; fi
done
echo "$ran target(s) run, $fails problem(s)"
[ "$fails" -eq 0 ] && [ "$ran" -gt 0 ]
