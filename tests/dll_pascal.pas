{ The shared library as a Pascal program uses it (DynLibs: LoadLibrary / dlopen), the way another FreePascal project
  would load pblake3.dll: the C API's functions by name, a few official vectors in all three modes plus the
  incremental calls. Usage: dll_pascal <library> <official_hash.txt> }
program dll_pascal;
{$mode objfpc}{$H+}
uses SysUtils, Classes, DynLibs;
type
  TUpd = function(st: Pointer; data: Pointer; len: PtrInt): LongInt; cdecl;
  THash = function(data: Pointer; len: PtrInt; outp: PByte; outLen: PtrInt): LongInt; cdecl;
  TKeyed = function(key: Pointer; data: Pointer; len: PtrInt; outp: PByte; outLen: PtrInt): LongInt; cdecl;
  TDerive = function(ctx: Pointer; ctxLen: PtrInt; mat: Pointer; matLen: PtrInt; outp: PByte; outLen: PtrInt): LongInt; cdecl;
  TInit = function(st: Pointer): LongInt; cdecl;
  TInitK = function(st: Pointer; key: Pointer; n: PtrInt): LongInt; cdecl;
  TXof = function(st: Pointer; outp: PByte; n: PtrInt): LongInt; cdecl;
  TSize = function: PtrInt; cdecl;
var
  lib: TLibHandle; cells, fails: Integer;
  fHash: THash; fKeyed: TKeyed; fDerive: TDerive; fInit: TInit; fInitK: TInitK; fUpd: TUpd; fXof: TXof; fSize: TSize;
procedure Check(ok: Boolean; const what: string);
begin Inc(cells); if not ok then begin Inc(fails); Writeln('FAIL ', what); end; end;
function Hex(const x: array of Byte; n: Integer): string; var i: Integer;
begin Result := ''; for i := 0 to n - 1 do Result := Result + LowerCase(IntToHex(x[i], 2)); end;
function Sym(const n: string): Pointer;
begin Result := GetProcAddress(lib, n); if Result = nil then begin Writeln('missing export ', n); Halt(1); end; end;
const KEY = 'whats the Elvish word for friend'; CTX = 'BLAKE3 2019-12-27 16:29:52 test vectors context';
var f: TStringList; l: string; p: TStringArray; n, i, tested: Integer; d: array of Byte; o: array[0..130] of Byte;
    st: array of Byte; k, c: AnsiString;
begin
  cells := 0; fails := 0; tested := 0; k := KEY; c := CTX;
  lib := LoadLibrary(ParamStr(1));
  if lib = NilHandle then begin Writeln('cannot load ', ParamStr(1)); Halt(1); end;
  fHash := THash(Sym('pblake3_hash')); fKeyed := TKeyed(Sym('pblake3_keyed_hash')); fDerive := TDerive(Sym('pblake3_derive_key'));
  fInit := TInit(Sym('pblake3_init')); fInitK := TInitK(Sym('pblake3_init_keyed')); fUpd := TUpd(Sym('pblake3_update'));
  fXof := TXof(Sym('pblake3_final_xof')); fSize := TSize(Sym('pblake3_state_size'));
  st := nil; SetLength(st, fSize() + 16);
  f := TStringList.Create; f.LoadFromFile(ParamStr(2));
  for l in f do begin
    if (l = '') or (l[1] = '#') then Continue;
    p := l.Split(' '); n := StrToInt(p[1]);
    if not ((n = 0) or (n = 1) or (n = 64) or (n = 1023) or (n = 1024) or (n = 1025) or (n = 2049) or (n = 8192) or (n = 31744) or (n = 102400)) then Continue;
    Inc(tested);
    d := nil; SetLength(d, n + 1); for i := 0 to n - 1 do d[i] := Byte(i mod 251);
    FillChar(o, SizeOf(o), 0);
    if p[0] = 'hash' then fHash(@d[0], n, @o[0], 131)
    else if p[0] = 'keyed_hash' then fKeyed(PAnsiChar(k), @d[0], n, @o[0], 131)
    else fDerive(PAnsiChar(c), Length(c), @d[0], n, @o[0], 131);
    Check(Hex(o, 131) = p[2], Format('%s %d B one pass', [p[0], n]));
    { incremental, in pieces of 1000 }
    if p[0] = 'hash' then fInit(@st[0]) else if p[0] = 'keyed_hash' then fInitK(@st[0], PAnsiChar(k), 32) else Continue;
    i := 0; while i < n do begin if i + 1000 > n then fUpd(@st[0], @d[i], n - i) else fUpd(@st[0], @d[i], 1000); Inc(i, 1000); end;
    FillChar(o, SizeOf(o), 0); fXof(@st[0], @o[0], 131);
    Check(Hex(o, 131) = p[2], Format('%s %d B in pieces', [p[0], n]));
  end;
  Check(tested >= 20, 'vectors tested');
  Check(fHash(nil, 5, @o[0], 32) = -1, 'NULL data is refused');
  f.Free; UnloadLibrary(lib);
  Writeln(cells, ' cells, ', fails, ' failures');
  if fails > 0 then Halt(1);
end.
