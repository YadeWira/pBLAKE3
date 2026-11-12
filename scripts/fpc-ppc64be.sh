#!/bin/bash
# A FreePascal cross compiler for big-endian PowerPC64 Linux (powerpc64-linux), built from the
# distribution's fpc-source with the host fpc, plus its RTL; writes "$1/fpc", a wrapper.
# Needs: fpc, fpc-source, binutils-powerpc64-linux-gnu (on PATH). Run the result under qemu-ppc64.
# Why: the distributions ship no big-endian FPC, and big-endian is where LEtoN/NtoLE earn their keep.
set -e
PREFIX=$(mkdir -p "${1:-/tmp/fpc-ppc64}" && cd "${1:-/tmp/fpc-ppc64}" && pwd)
SRC=${FPCSRC:-/usr/share/fpcsrc/3.2.2}
MSG=$(find /usr/lib -name errore.msg -path '*fpc/3.2.2*' | head -1)
[ -n "$MSG" ] && [ -d "$SRC/compiler" ] || { echo "need fpc and fpc-source installed"; exit 1; }
command -v powerpc64-linux-gnu-as >/dev/null || { echo "need binutils-powerpc64-linux-gnu"; exit 1; }
mkdir -p "$PREFIX/src" "$PREFIX/o"
cp -r "$SRC/compiler" "$SRC/rtl" "$PREFIX/src/"
cd "$PREFIX/src/compiler"
# the compiler's message tables (msgtxt.inc)
fpc -O1 -FU"$PREFIX/o" -o"$PREFIX/msg2inc" utils/msg2inc.pp >/dev/null
cp "$MSG" errore.msg && "$PREFIX/msg2inc" errore.msg msg msg >/dev/null
# the cross compiler: ppc64 big-endian code generator, running on the host
fpc -Mobjfpc -Sgic -O2 -dPOWERPC64 -Fupowerpc64 -Fuppcgen -Fusystems -Fu. -Fipowerpc64 -Fippcgen -Fisystems -Fi. \
    -FU"$PREFIX/o" -o"$PREFIX/ppcppc64" pp.pas >"$PREFIX/compiler.log" 2>&1 || { tail -20 "$PREFIX/compiler.log"; exit 1; }
# its RTL (the startup .as files are not in the distribution's source; powerpc64 starts up in Pascal)
cd "$PREFIX/src/rtl"
for d in $(find . -name Makefile.fpc -not -path ./Makefile.fpc | xargs -n1 dirname) .; do (cd "$d" && fpcmake -Tall Makefile.fpc >/dev/null 2>&1); done
: > powerpc/makefile.cpu; : > powerpc64/makefile.cpu
for f in prt0 dllprt0 cprt0 gprt0; do [ -e linux/powerpc64/$f.as ] || : > linux/powerpc64/$f.as; done
make all CPU_TARGET=powerpc64 OS_TARGET=linux PP="$PREFIX/ppcppc64" BINUTILSPREFIX=powerpc64-linux-gnu- FPCFPMAKE=fpc \
     >"$PREFIX/rtl.log" 2>&1 || { tail -20 "$PREFIX/rtl.log"; exit 1; }
cat > "$PREFIX/fpc" <<WRAP
#!/bin/sh
exec "$PREFIX/ppcppc64" -n -Tlinux -XPpowerpc64-linux-gnu- -Fu"$PREFIX/src/rtl/units/powerpc64-linux" "\$@"
WRAP
chmod +x "$PREFIX/fpc"
echo "$PREFIX/fpc"
