{ pBLAKE3 as a shared library (Windows DLL; also .so/.dylib). C interface, cdecl.
  The caller owns every buffer: the state is pblake3_state_size() bytes, no
  allocation here. A Pascal exception never crosses the boundary: calls
  return 0 on success, -1 on a bad argument. }
library pblake3dll;
{$I pja.inc}
uses pjablake3, pblake3c;

function pblake3_version: LongInt; cdecl;
begin Result := 2; end;

{ 1 if the C chunk routine is installed inside this library }
function pblake3_uses_c: LongInt; cdecl;
begin if Assigned(Blake3Chunks) then Result := 1 else Result := 0; end;

function pblake3_state_size: SizeInt; cdecl;
begin Result := SizeOf(TBlake3); end;

function pblake3_init(st: Pointer): LongInt; cdecl;
var b: PBlake3;
begin
  if st = nil then Exit(-1);
  b := PBlake3(st); b^.Init; Result := 0;
end;

function pblake3_update(st: Pointer; data: Pointer; len: SizeInt): LongInt; cdecl;
var b: PBlake3;
begin
  if (st = nil) or (len < 0) or ((data = nil) and (len > 0)) then Exit(-1);
  b := PBlake3(st);
  if len > 0 then b^.Update(data^, len);
  Result := 0;
end;

{ out: 16 bytes (BLAKE3-128) }
function pblake3_final(st: Pointer; outp: PByte): LongInt; cdecl;
var h: THash16; b: PBlake3;
begin
  if (st = nil) or (outp = nil) then Exit(-1);
  b := PBlake3(st); h := b^.Final; Move(h, outp^, 16); Result := 0;
end;

function pblake3_128(data: Pointer; len: SizeInt; outp: PByte): LongInt; cdecl;
var s: TBlake3;
begin
  if (len < 0) or ((data = nil) and (len > 0)) or (outp = nil) then Exit(-1);
  s.Init;
  if len > 0 then s.Update(data^, len);
  Result := pblake3_final(@s, outp);
end;

{ keyed hash (MAC): key is exactly 32 bytes }
function pblake3_init_keyed(st: Pointer; key: Pointer; keyLen: SizeInt): LongInt; cdecl;
var b: PBlake3;
begin
  if (st = nil) or (key = nil) or (keyLen <> 32) then Exit(-1);
  b := PBlake3(st); b^.InitKeyed(key^, keyLen); Result := 0;
end;

{ derive_key: the context string (UTF-8), then pblake3_update with the key material }
function pblake3_init_derive_key(st: Pointer; ctx: Pointer; ctxLen: SizeInt): LongInt; cdecl;
var b: PBlake3;
begin
  if (st = nil) or (ctxLen < 0) or ((ctx = nil) and (ctxLen > 0)) then Exit(-1);
  b := PBlake3(st); b^.InitDeriveKey(ctx^, ctxLen); Result := 0;
end;

{ any output length (XOF); the state is not consumed: it can be called again, or updated further }
function pblake3_final_xof(st: Pointer; outp: PByte; outLen: SizeInt): LongInt; cdecl;
var b: PBlake3;
begin
  if (st = nil) or (outLen < 0) or ((outp = nil) and (outLen > 0)) then Exit(-1);
  b := PBlake3(st);
  if outLen > 0 then b^.FinalXof(outp^, outLen);
  Result := 0;
end;

{ one pass, any output length }
function pblake3_hash(data: Pointer; len: SizeInt; outp: PByte; outLen: SizeInt): LongInt; cdecl;
var s: TBlake3;
begin
  if (len < 0) or ((data = nil) and (len > 0)) then Exit(-1);
  s.Init;
  if len > 0 then s.Update(data^, len);
  Result := pblake3_final_xof(@s, outp, outLen);
end;

function pblake3_keyed_hash(key: Pointer; data: Pointer; len: SizeInt; outp: PByte; outLen: SizeInt): LongInt; cdecl;
var s: TBlake3;
begin
  if (len < 0) or ((data = nil) and (len > 0)) or (key = nil) then Exit(-1);
  s.InitKeyed(key^, 32);
  if len > 0 then s.Update(data^, len);
  Result := pblake3_final_xof(@s, outp, outLen);
end;

function pblake3_derive_key(ctx: Pointer; ctxLen: SizeInt; material: Pointer; matLen: SizeInt;
                            outp: PByte; outLen: SizeInt): LongInt; cdecl;
var s: TBlake3;
begin
  if (ctxLen < 0) or ((ctx = nil) and (ctxLen > 0)) or (matLen < 0) or ((material = nil) and (matLen > 0)) then Exit(-1);
  s.InitDeriveKey(ctx^, ctxLen);
  if matLen > 0 then s.Update(material^, matLen);
  Result := pblake3_final_xof(@s, outp, outLen);
end;

exports pblake3_version, pblake3_uses_c, pblake3_state_size, pblake3_init,
        pblake3_update, pblake3_final, pblake3_128,
        pblake3_init_keyed, pblake3_init_derive_key, pblake3_final_xof,
        pblake3_hash, pblake3_keyed_hash, pblake3_derive_key;
end.
