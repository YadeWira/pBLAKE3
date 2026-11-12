#!/bin/sh
# b3sum (ours) against the official one on random files around every boundary (block, chunk, a thread's
# share, the 8 MiB buffer), every mode, 1..7 threads, XOF, --raw, -c.   B3OFF=<official b3sum> sh tests/diff_b3sum.sh
set -eu
OURS=$(realpath "${B3OURS:-build/b3sum}"); OFF=$(command -v "${B3OFF:-b3sum}")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fails=0; cells=0
same() { cells=$((cells+1)); if [ "$1" != "$2" ]; then fails=$((fails+1)); echo "DIFF: $3"; fi; }
head -c 32 /dev/urandom > "$T/key"
for n in 0 1 63 64 65 1023 1024 1025 2047 2048 2049 65536 262143 262144 262145 1048575 1048576 4194305 8388607 8388608 8388609 \
         8389631 8389632 8389633 12582912 16777216 16778240 16778241 25165824 33554432 33555457 40000001; do
  f=$T/f$n; head -c $n /dev/urandom > "$f"
  want=$($OFF "$f" | cut -d' ' -f1)
  for th in 1 2 3 7; do
    got=$($OURS --num-threads $th "$f" | cut -d' ' -f1); same "$want" "$got" "plain $n B, $th threads"
  done
  want=$($OFF -l 200 --no-names "$f"); got=$($OURS -l 200 --no-names "$f"); same "$want" "$got" "xof 200, $n B"
  if true; then
    want=$($OFF --keyed --no-names "$f" < "$T/key"); got=$($OURS --keyed --no-names "$f" < "$T/key"); same "$want" "$got" "keyed $n B"
    want=$($OFF --derive-key "pBLAKE3 test context" --no-names "$f"); got=$($OURS --derive-key "pBLAKE3 test context" --no-names "$f")
    same "$want" "$got" "derive_key $n B"
  fi
done
# stdin, and a name that needs escaping, and --raw, and -c
f=$T/f40000001
same "$($OFF < "$f")" "$($OURS < "$f")" "stdin"
same "$($OFF --raw -l 77 "$f" | od -An -tx1)" "$($OURS --raw -l 77 "$f" | od -An -tx1)" "raw"
printf 'x' > "$T/we\\ird"; same "$($OFF "$T/we\\ird" | sed "s#$T/##")" "$($OURS "$T/we\\ird" | sed "s#$T/##")" "escaped name"
( cd "$T" && $OFF f1025 f65536 > sums.txt && $OURS -c sums.txt > chk.txt && grep -c ': OK' chk.txt | grep -q '^2$' ) && cells=$((cells+1)) || { fails=$((fails+1)); echo "DIFF: -c"; }
echo "$cells comparisons, $fails differences"
[ "$fails" -eq 0 ]
