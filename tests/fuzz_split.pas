{ Randomized consistency: the same bytes hashed in one Update, in random pieces, with the C chunk routine off,
  through the threads (random counts and pieces), in the three modes, with every output length a prefix of the
  longer ones. The one-Update hash is what the official vectors check (test_official); this finds what the vectors
  do not reach: odd splits, pieces around chunk and group boundaries, thread shares. Usage: fuzz_split [iterations [seed]] }
program fuzz_split;
{$I ../src/pja.inc}
uses {$ifdef unix}cthreads,{$endif} SysUtils, pjablake3, pblake3c, pjablake3mt;
var seed: QWord;
function Rnd(n: SizeInt): SizeInt;     { 0 .. n-1 }
begin
  seed := seed xor (seed shl 13); seed := seed xor (seed shr 7); seed := seed xor (seed shl 17);
  Result := SizeInt((seed shr 8) mod QWord(n));
end;
function Hex(const x: array of Byte): string; var i: Integer;
begin Result := ''; for i := 0 to High(x) do Result := Result + IntToHex(x[i], 2); end;
var it, iters, n, mode, p, k, th, fails: Integer; d: array of Byte; key: array[0..31] of Byte;
    a, b: array[0..99] of Byte; h, h2: TBlake3; hook: TBlake3Chunks; hookKF: TBlake3ChunksKF; ctx: AnsiString; what: string;
    sizes: array[0..11] of SizeInt = (0, 1, 1023, 1024, 1025, 65535, 65536, 65537, 262144, 262145, 3000000, 8400000);
procedure Start(var x: TBlake3); begin
  case mode of 0: x.Init; 1: x.InitKeyed(key, 32); else x.InitDeriveKey(PAnsiChar(ctx)^, Length(ctx)); end;
end;
begin
  iters := 200; seed := QWord($9E3779B97F4A7C15);
  if ParamCount >= 1 then iters := StrToInt(ParamStr(1));
  if ParamCount >= 2 then seed := QWord(StrToInt64(ParamStr(2))) or 1;
  fails := 0; hook := Blake3Chunks; hookKF := Blake3ChunksKF; ctx := 'fuzz context';
  for it := 1 to iters do begin
    if Rnd(3) = 0 then n := sizes[Rnd(12)] + Rnd(3) - 1 else n := Rnd(300000);
    if n < 0 then n := 0;
    d := nil; SetLength(d, n + 1); for k := 0 to n - 1 do d[k] := Byte(Rnd(256));
    for k := 0 to 31 do key[k] := Byte(Rnd(256));
    mode := Rnd(3);
    Blake3Chunks := hook; Blake3ChunksKF := hookKF;
    Start(h); if n > 0 then h.Update(d[0], n); h.FinalXof(a, 100);
    what := Format('iter %d: %d B mode %d', [it, n, mode]);
    { 1. random pieces }
    Start(h2); p := 0;
    while p < n do begin k := 1 + Rnd(1 + Rnd(5000)); if p + k > n then k := n - p; h2.Update(d[p], k); Inc(p, k); end;
    h2.FinalXof(b, 100); if Hex(a) <> Hex(b) then begin Inc(fails); Writeln('FAIL pieces ', what); end;
    { 2. final twice, short outputs are prefixes }
    h2.FinalXof(b, 32); if Hex(Slice(a, 32)) <> Hex(Slice(b, 32)) then begin Inc(fails); Writeln('FAIL prefix ', what); end;
    { 3. without the C chunks }
    Blake3Chunks := nil; Blake3ChunksKF := nil;
    Start(h2); if n > 0 then h2.Update(d[0], n); h2.FinalXof(b, 100);
    if Hex(a) <> Hex(b) then begin Inc(fails); Writeln('FAIL no C ', what); end;
    Blake3Chunks := hook; Blake3ChunksKF := hookKF;
    { 4. threads, in random pieces }
    th := 2 + Rnd(6);
    Start(h2); p := 0;
    while p < n do begin k := 1 + Rnd(1 + Rnd(3000000)); if Rnd(4) = 0 then k := 1024 * (1 + Rnd(400)); if p + k > n then k := n - p;
      Blake3UpdateMT(h2, d[p], k, th); Inc(p, k); end;
    h2.FinalXof(b, 100); if Hex(a) <> Hex(b) then begin Inc(fails); Writeln('FAIL threads(', th, ') ', what); end;
  end;
  Writeln(iters, ' iterations, ', fails, ' failures');
  if fails > 0 then Halt(1);
end.
