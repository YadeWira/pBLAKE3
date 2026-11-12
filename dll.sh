#!/bin/sh
# Windows: build pblake3.dll (library) and test it through LoadLibrary.
#   FPC=<compiler> CC=<C compiler> sh dll.sh
set -eu
cd "$(dirname "$0")"; OUT=${B3_OUT:-build}
FPC=${FPC:-fpc}; CC=${CC:-cc}
case $CC in /*) PATH=$(dirname "${CC%% *}"):$PATH; export PATH ;; esac
# shellcheck disable=SC2086
sh ./build.sh | tail -2
mkdir -p "$OUT/u"
$FPC -O3 -Fusrc -Fisrc -Fo"$OUT" -FU"$OUT/u" -o"$OUT/pblake3.dll" src/pblake3dll.pas > "$OUT/fpc_dll.log" 2>&1 || { cat "$OUT/fpc_dll.log"; exit 1; }
# shellcheck disable=SC2086
$CC -O2 -static tests/dll_test.c -o "$OUT/dll_test.exe"
"$OUT/dll_test.exe" "$OUT/pblake3.dll" tests/kat.txt
