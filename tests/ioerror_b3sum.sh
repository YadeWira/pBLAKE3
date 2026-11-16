#!/bin/sh
# A read that fails in the middle of a file must be an error: no hash printed, exit status 1. strace injects EIO into the
# file's reads (Linux; needs strace).   B3OURS=build/b3sum sh tests/ioerror_b3sum.sh
set -u
OURS=$(realpath "${B3OURS:-build/b3sum}")
command -v strace >/dev/null || { echo "no strace: skipped"; exit 0; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
head -c 100000000 /dev/urandom > "$T/f"
want=$("$OURS" --no-names "$T/f"); fails=0; cells=0
for w in 1 2 3 6 9 12; do
  for mode in "+" ""; do
    cells=$((cells+1))
    out=$(strace -f -P "$T/f" -e trace=read -e "inject=read:error=EIO:when=$w$mode" -o /dev/null "$OURS" --no-names --num-threads 4 "$T/f" 2> "$T/err"); rc=$?
    # an EIO only on a read that never happens (when=12 with nothing after it) may leave the hash right: then it must be the right one
    if [ "$rc" -eq 0 ]; then
      [ "$out" = "$want" ] || { fails=$((fails+1)); echo "WRONG HASH PRINTED with EIO at read $w$mode"; }
    else
      [ -z "$out" ] && [ -s "$T/err" ] || { fails=$((fails+1)); echo "error exit but output/stderr wrong at read $w$mode"; }
    fi
  done
done
# through a pipe too
cells=$((cells+1))
out=$(cat "$T/f" | strace -f -e trace=read -P /proc/self/fd/0 -e inject=read:error=EIO:when=3+ -o /dev/null "$OURS" --no-names 2>/dev/null); rc=$?
[ "$rc" -ne 0 ] || [ "$out" = "$want" ] || { fails=$((fails+1)); echo "WRONG HASH PRINTED (pipe)"; }
echo "$cells cases, $fails problems"
[ "$fails" -eq 0 ]
