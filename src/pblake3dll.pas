{ pBLAKE3 as a shared library (Windows DLL; also .so/.dylib). C interface, cdecl.
  The caller owns every buffer: the state is pblake3_state_size() bytes, no
  allocation here. A Pascal exception never crosses the boundary: calls
  return 0 on success, -1 on a bad argument. }
library pblake3;
{$I pja.inc}
uses pjablake3, pblake3c;

function pblake3_version: LongInt; cdecl;
begin Result := 1; end;

{ 1 if the C chunk routine is installed inside this library }
function pblake3_uses_c: LongInt; cdecl;
begin if Assigned(Blake3Chunks) then Result := 1 else Result := 0; end;

function pblake3_state_size: SizeInt; cdecl;
begin Result := SizeOf(TBlake3); end;

function pblake3_init(st: Pointer): LongInt; cdecl;
begin
  if st = nil then Exit(-1);
  PBlake3(st)^.Init; Result := 0;
end;

function pblake3_update(st: Pointer; data: Pointer; len: SizeInt): LongInt; cdecl;
begin
  if (st = nil) or (len < 0) or ((data = nil) and (len > 0)) then Exit(-1);
  if len > 0 then PBlake3(st)^.Update(data^, len);
  Result := 0;
end;

{ out: 16 bytes (BLAKE3-128) }
function pblake3_final(st: Pointer; outp: PByte): LongInt; cdecl;
var h: THash16;
begin
  if (st = nil) or (outp = nil) then Exit(-1);
  h := PBlake3(st)^.Final; Move(h, outp^, 16); Result := 0;
end;

function pblake3_128(data: Pointer; len: SizeInt; outp: PByte): LongInt; cdecl;
var s: TBlake3;
begin
  if (len < 0) or ((data = nil) and (len > 0)) or (outp = nil) then Exit(-1);
  s.Init;
  if len > 0 then s.Update(data^, len);
  Result := pblake3_final(@s, outp);
end;

exports pblake3_version, pblake3_uses_c, pblake3_state_size, pblake3_init,
        pblake3_update, pblake3_final, pblake3_128;
end.
