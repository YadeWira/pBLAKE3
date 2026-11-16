#!/bin/sh
# Big-endian with a C library, under qemu-user: what tests/qemu_c_core.sh cannot do without one.
#  - powerpc64: the Pascal unit with threads (cthreads, linked against the cross glibc): the official vectors, the
#    split/thread fuzz, b3sum on a 21 MB file in all modes and thread counts against the host's b3sum; the plain C library
#    as a shared library through dlopen (api_test).
#  - s390x: the plain C library through dlopen.
# Needs: gcc-powerpc64-linux-gnu, gcc-s390x-linux-gnu, libc6-dev-ppc64-cross, libc6-dev-s390x-cross, qemu-user, fpc and
# fpc-source (for scripts/fpc-ppc64be.sh), and the host's build/b3sum (sh build.sh).
# XPFX: where the cross toolchains live (default /usr; a root extracted from the .deb files works too).
# Not covered: the Pascal *shared library* on powerpc64 (FPC 3.2.2 makes no position-independent code there: the .so
# links but cannot be loaded, R_PPC64_ADDR16_HA out of range).
set -u
cd "$(dirname "$0")/.."
XPFX=${XPFX:-/usr}; OUT=${B3_OUT:-build}/qbe; mkdir -p "$OUT"; fails=0
if [ "$XPFX" = /usr ]; then SR=""; GSR=""; else SR="-k--sysroot=$XPFX"; GSR="-Wl,--sysroot=$XPFX"; fi
ok() { if [ "$1" -ne 0 ]; then fails=$((fails+1)); echo "FAILED: $2"; else echo "ok: $2"; fi; }
HOST=$(realpath "${B3OURS:-build/b3sum}")
# --- powerpc64
P=$XPFX/powerpc64-linux-gnu; [ -d "$P" ] || P=$XPFX/usr/powerpc64-linux-gnu
QP="qemu-ppc64 -L $P"
FPC=${FPC_PPC64:-}
[ -n "$FPC" ] || FPC=$(scripts/fpc-ppc64be.sh "$OUT/fpc" | tail -1)
powerpc64-linux-gnu-gcc -O3 -fwrapv -ffp-contract=off -fno-stack-protector -fno-tree-loop-distribute-patterns -c src/b3chunks.c -o "$OUT/b3chunks.o"
for p in test_official fuzz_split; do
  # shellcheck disable=SC2086
  $FPC -O3 -Fusrc -Fisrc -Fo"$OUT" -FU"$OUT" -Fl"$P/lib" -FL/lib64/ld64.so.1 $SR -o"$OUT/$p" tests/$p.pas > "$OUT/fpc_$p.log" 2>&1 || { cat "$OUT/fpc_$p.log"; exit 1; }
done
# shellcheck disable=SC2086
$FPC -O3 -Fusrc -Fisrc -Fo"$OUT" -FU"$OUT" -Fl"$P/lib" -FL/lib64/ld64.so.1 $SR -o"$OUT/b3sum" src/b3sum.pas > "$OUT/fpc_b3sum.log" 2>&1 || { cat "$OUT/fpc_b3sum.log"; exit 1; }
$QP "$OUT/test_official" tests/official_hash.txt | tail -1 | tee "$OUT/o.txt"; grep -q ' 0 failures' "$OUT/o.txt"; ok $? "powerpc64: official vectors (Pascal, C hooks on and off)"
$QP "$OUT/fuzz_split" 120 7 | tail -1 | tee "$OUT/f.txt"; grep -q ' 0 failures' "$OUT/f.txt"; ok $? "powerpc64: split and thread fuzz"
head -c 21000000 /dev/urandom > "$OUT/r"; head -c 32 /dev/urandom > "$OUT/k"
for args in "" "--derive-key ctx"; do
  # shellcheck disable=SC2086
  want=$("$HOST" --no-names $args "$OUT/r")
  for th in 1 4; do
    # shellcheck disable=SC2086
    got=$($QP "$OUT/b3sum" --no-names --num-threads $th $args "$OUT/r"); [ "$got" = "$want" ]; ok $? "powerpc64: b3sum $args, $th thread(s)"
  done
done
want=$("$HOST" --keyed --no-names "$OUT/r" < "$OUT/k"); got=$($QP "$OUT/b3sum" --keyed --no-names --num-threads 4 "$OUT/r" < "$OUT/k")
[ "$got" = "$want" ]; ok $? "powerpc64: b3sum --keyed, 4 threads"
# --- the plain C library through dlopen, on both big-endian CPUs
for t in powerpc64:ppc64 s390x:s390x; do
  tc=${t%%:*}-linux-gnu; q=qemu-${t##*:}; R=$XPFX/$tc; [ -d "$R" ] || R=$XPFX/usr/$tc
  # shellcheck disable=SC2086
  $tc-gcc $GSR -O2 -fPIC -shared src/pblake3.c -o "$OUT/libpblake3c_$tc.so" && $tc-gcc $GSR -O2 tests/api_test.c -o "$OUT/api_test_$tc" -ldl &&
    $q -L "$R" "$OUT/api_test_$tc" "$OUT/libpblake3c_$tc.so" tests/official_hash.txt | tail -1 | tee "$OUT/a.txt"
  grep -q ' 0 failures' "$OUT/a.txt"; ok $? "${t%%:*}: the C library through dlopen"
done
echo "$fails problem(s)"
[ "$fails" -eq 0 ]
