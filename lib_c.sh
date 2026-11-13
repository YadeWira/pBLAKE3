#!/bin/sh
# The plain C implementation (src/pblake3.c) as a shared library, tested through the same C API test as the
# Pascal one, and against it on random inputs.   CC=<C compiler> sh lib_c.sh   (run lib.sh first: it builds the Pascal library)
set -eu
cd "$(dirname "$0")"; OUT=${B3_OUT:-build}
CC=${CC:-cc}
case $CC in /*) PATH=$(dirname "${CC%% *}"):$PATH; export PATH ;; esac
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) PL=pblake3.dll; CL=pblake3c.dll; EXE=.exe; PIC=; LIBS=; SH="-shared -DPBLAKE3_BUILD_DLL" ;;
  Darwin) PL=libpblake3.dylib; CL=libpblake3c.dylib; EXE=; PIC=-fPIC; LIBS=; SH=-dynamiclib ;;
  *) PL=libpblake3.so; CL=libpblake3c.so; EXE=; PIC=-fPIC; LIBS=-ldl; SH=-shared ;;
esac
mkdir -p "$OUT"
FLAGS="-O3 -fwrapv -ffp-contract=off -fno-stack-protector"
if $CC --version 2>/dev/null | grep -qi clang; then FLAGS="$FLAGS -fno-builtin"; else FLAGS="$FLAGS -fno-tree-loop-distribute-patterns"; fi
case "$CC $* $($CC -dumpmachine 2>/dev/null || true)" in
  *-m32*|*i686*|*i386*|*i586*) FLAGS="$FLAGS -march=i686" ;;
esac
# the object needs no runtime (no libc, no libgcc)
# shellcheck disable=SC2086
$CC $FLAGS $PIC "$@" -c src/pblake3.c -o "$OUT/pblake3_c.o"
if command -v "${NM:-nm}" >/dev/null; then
  bad=$(${NM:-nm} -u "$OUT/pblake3_c.o" | grep -E '__(u?div|u?mod|ctz|clz|popcount)[a-z]*[0-9]|___?chkstk|mem(cpy|set|move)' || true)
  if [ -n "$bad" ]; then echo "pblake3_c.o needs the runtime:"; echo "$bad"; exit 1; fi
  echo "nm -u: pblake3_c.o needs nothing"
fi
# shellcheck disable=SC2086
$CC $FLAGS $PIC "$@" $SH src/pblake3.c -o "$OUT/$CL"
# shellcheck disable=SC2086
$CC -O2 $PIC "$@" tests/api_test.c -o "$OUT/api_test_c$EXE" $LIBS
abs() { case "$1" in /*|[A-Za-z]:*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }
LP=$(abs "$OUT/$PL"); LC=$(abs "$OUT/$CL")
[ "$CL" != pblake3c.dll ] || { LP="$OUT/$PL"; LC="$OUT/$CL"; }
"$OUT/api_test_c$EXE" "$LC" tests/official_hash.txt | tr -d '\r' | tee "$OUT/apic.txt"
grep -q ' 0 failures' "$OUT/apic.txt"
# shellcheck disable=SC2086
$CC -O2 $PIC "$@" tests/cross_impl.c -o "$OUT/cross_impl$EXE" $LIBS
"$OUT/cross_impl$EXE" "$LP" "$LC" "${B3_CROSS:-150}" | tr -d '\r' | tee "$OUT/cross.txt"
grep -q ' 0 failures' "$OUT/cross.txt"
