{ The official test_vectors.json, hash mode (tests/official_hash.txt): every
  case's full 131-byte extended output, whole and in pieces, on the C path and the Pascal path. }
program test_official;
{$I ../src/pja.inc}
uses SysUtils, Classes, pjablake3, pblake3c;
var cells, failures: Integer;
procedure Check(ok: Boolean; const what: string);
begin Inc(cells); if not ok then begin Inc(failures); Writeln('  FAIL ', what); end; end;
function Hex(const x: array of Byte): string; var i: Integer;
begin Result := ''; for i := 0 to High(x) do Result := Result + LowerCase(IntToHex(x[i], 2)); end;
const STEPS: array[0..5] of Integer = (0, 1, 64, 1000, 1024, 3000);
var si: Integer; kat: TStringList; l: string; f: TStringArray; n, i, pass, step, p, k: Integer;
    d: array of Byte; o: array[0..130] of Byte; h: TBlake3; chunks: TBlake3Chunks; a: array[0..15] of Byte;
begin
  cells := 0; failures := 0; chunks := Blake3Chunks;
  kat := TStringList.Create; kat.LoadFromFile(ParamStr(1));
  for pass := 0 to 1 do begin
    if pass = 0 then Blake3Chunks := chunks else Blake3Chunks := nil;
    for l in kat do begin
      if (l = '') or (l[1] = '#') then Continue;
      f := l.Split(' '); n := StrToInt(f[1]);
      d := nil; SetLength(d, n); for i := 0 to n - 1 do d[i] := i mod 251;
      for si := 0 to 5 do begin
        if si = 0 then step := n else step := STEPS[si];
        if step < 1 then Continue;
        h.Init; p := 0;
        while p < n do begin k := step; if p + k > n then k := n - p; h.Update(d[p], k); Inc(p, k); end;
        h.FinalXof(o, 131);
        Check(Hex(o) = f[2], Format('%d B in steps of %d (pass %d)', [n, step, pass]));
      end;
      { Final = the first 16 bytes; a short XOF is a prefix }
      h.Init; if n > 0 then h.Update(d[0], n);
      a := h.Final; Check(Hex(a) = Copy(f[2], 1, 32), Format('Final of %d B', [n]));
      h.FinalXof(o, 100); Check(Hex(Slice(o, 100)) = Copy(f[2], 1, 200), Format('XOF 100 of %d B', [n]));
    end;
  end;
  Blake3Chunks := chunks;
  Writeln(cells, ' cells, ', failures, ' failures');
  if (failures > 0) or (cells < 500) then Halt(1);
end.
