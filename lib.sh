#!/bin/sh
# Build the shared library (pblake3.dll / libpblake3.so / libpblake3.dylib) and test the C API through it.
#   FPC=<compiler> CC=<C compiler> sh lib.sh
set -eu
cd "$(dirname "$0")"; OUT=${B3_OUT:-build}
FPC=${FPC:-fpc}; CC=${CC:-cc}
case $CC in /*) PATH=$(dirname "${CC%% *}"):$PATH; export PATH ;; esac
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) LIB=pblake3.dll; EXE=.exe; PIC=; LIBS= ;;
  Darwin) LIB=libpblake3.dylib; EXE=; PIC=-fPIC; LIBS= ;;
  *) LIB=libpblake3.so; EXE=; PIC=-fPIC; LIBS=-ldl ;;
esac
mkdir -p "$OUT/u"
# the C object again, position independent where the library is
FLAGS="-O3 -fwrapv -ffp-contract=off -fno-stack-protector"
if $CC --version 2>/dev/null | grep -qi clang; then FLAGS="$FLAGS -fno-builtin"; else FLAGS="$FLAGS -fno-tree-loop-distribute-patterns"; fi
case "$CC $* $($CC -dumpmachine 2>/dev/null || true)" in
  *-m32*|*i686*|*i386*|*i586*) FLAGS="$FLAGS -march=i686" ;;
esac
# shellcheck disable=SC2086
$CC $FLAGS $PIC "$@" -c src/b3chunks.c -o "$OUT/b3chunks.o"
case "$PIC" in -fPIC) FPCPIC=-Cg ;; *) FPCPIC= ;; esac
$FPC -O3 $FPCPIC -Fusrc -Fisrc -Fo"$OUT" -FU"$OUT/u" -o"$OUT/$LIB" src/pblake3dll.pas > "$OUT/fpc_lib.log" 2>&1 || { cat "$OUT/fpc_lib.log"; exit 1; }
# shellcheck disable=SC2086
$CC -O2 $PIC "$@" tests/api_test.c -o "$OUT/api_test$EXE" $LIBS
"$OUT/api_test$EXE" "$( [ "$LIB" = pblake3.dll ] && echo "$OUT/$LIB" || echo "$PWD/$OUT/$LIB")" tests/official_hash.txt | tr -d '\r' | tee "$OUT/api.txt"
grep -q ' 0 failures' "$OUT/api.txt"
