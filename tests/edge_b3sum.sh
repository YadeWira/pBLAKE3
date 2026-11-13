#!/bin/sh
# Awkward cases for b3sum, ours against the official one: stdout and the exit status must be the same (stderr only has to
# be empty or not).  Missing and unreadable files, directories, -c with every kind of bad line, odd options, stdin.
#   B3OFF=<official b3sum> B3OURS=<ours> sh tests/edge_b3sum.sh
set -u
OURS=$(realpath "${B3OURS:-build/b3sum}"); OFF=$(command -v "${B3OFF:-b3sum}")
T=$(mktemp -d); trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
cd "$T" || exit 2
fails=0; cells=0
printf 'hello\n' > a.txt; : > empty; head -c 5000 /dev/urandom > big; mkdir dir; printf 'x' > noperm; chmod 000 noperm
head -c 32 /dev/urandom > key32; head -c 31 /dev/urandom > key31
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) NOPERM=0 ;; *) NOPERM=1; [ "$(id -u)" = 0 ] && NOPERM=0 ;; esac
# run NAME INPUT-FILE args...: both tools with the same stdin
run() {
  name=$1; inp=$2; shift 2; cells=$((cells+1))
  "$OFF" "$@" < "$inp" > off.out 2> off.err; oc=$?
  "$OURS" "$@" < "$inp" > our.out 2> our.err; uc=$?
  if [ "$oc" != "$uc" ]; then fails=$((fails+1)); echo "DIFF exit [$name]: official $oc, ours $uc"; return; fi
  if ! cmp -s off.out our.out; then fails=$((fails+1)); echo "DIFF stdout [$name]"; diff off.out our.out | head -4; return; fi
  if [ -s off.err ] && [ ! -s our.err ]; then fails=$((fails+1)); echo "DIFF stderr [$name]: official complains, ours silent"; return; fi
  if [ ! -s off.err ] && [ -s our.err ]; then fails=$((fails+1)); echo "DIFF stderr [$name]: ours complains ($(head -c 80 our.err))"; return; fi
}
none=/dev/null
run "one file" $none a.txt
run "several files" $none a.txt empty big a.txt
run "no names" $none --no-names a.txt empty big
run "missing file" $none nonexistent
run "missing among good" $none a.txt nonexistent empty
run "directory" $none dir
run "directory among good" $none a.txt dir empty
[ "$NOPERM" = 1 ] && run "unreadable" $none noperm
[ "$NOPERM" = 1 ] && run "unreadable among good" $none a.txt noperm empty
run "stdin default" a.txt
run "stdin dash" a.txt -
run "dash and files" a.txt a.txt - empty
run "stdin twice" a.txt - -
run "empty stdin" $none
run "length 0" $none -l 0 a.txt
run "length 1" $none -l 1 a.txt
run "length 64" $none -l 64 a.txt
run "length 65" $none -l 65 big
run "length 1000" $none --length 1000 big
run "no names + length" $none --no-names -l 100 a.txt big
run "keyed" key32 --keyed a.txt
run "keyed short key" key31 --keyed a.txt
run "keyed no key" $none --keyed a.txt
run "keyed length" key32 --keyed -l 90 big
run "derive-key" $none --derive-key "some context" a.txt big
run "derive-key empty context" $none --derive-key "" a.txt
run "derive-key + length" $none --derive-key ctx -l 77 --no-names big
run "unknown option" $none --frobnicate a.txt
run "raw one file" $none --raw a.txt
run "raw length" $none --raw -l 100 big
run "raw two files" $none --raw a.txt empty
# -c
"$OFF" a.txt empty big > good.sums
run "check good" $none -c good.sums
run "check good via stdin" good.sums -c
printf 'bad\n' > a2.txt; "$OFF" a.txt > bad1.sums; sed 's/^./0/' bad1.sums > bad1x.sums
run "check wrong hash" $none -c bad1x.sums
"$OFF" a.txt empty > two.sums; printf 'x' > empty
run "check one fails, one ok" $none -c two.sums
: > empty
run "check missing file" $none -c nonexistent.sums
printf 'not a checksum line\n' > malformed.sums
run "check malformed" $none -c malformed.sums
printf '\n\n' > blanks.sums
run "check blank lines" $none -c blanks.sums
{ cat good.sums; printf '\n'; } > blank_in.sums
run "check with a blank line" $none -c blank_in.sums
"$OFF" a.txt | awk '{print toupper($1) "  " $2}' > upper.sums
run "check upper-case hex" $none -c upper.sums
"$OFF" --no-names -l 16 a.txt | awk '{print $0"  a.txt"}' > short.sums
run "check short hash" $none -c short.sums
printf '%s  missing_file\n' "$("$OFF" --no-names a.txt)" > nofile.sums
run "check file not there" $none -c nofile.sums
printf 'x\\ny' > 'we\ird'; "$OFF" 'we\ird' > esc.sums
run "check escaped name" $none -c esc.sums
run "plain escaped name" $none 'we\ird'
echo "$cells cases, $fails differences"
[ "$fails" -eq 0 ]
