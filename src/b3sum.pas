{ b3sum: the BLAKE3 checksum tool, in the official one's format ("<hex>  <name>"), on pjablake3 (+ threads).
  Hash, --keyed (the 32-byte key on stdin), --derive-key CONTEXT, -l/--length N (XOF), --raw, --no-names,
  -c/--check, --num-threads N, "-" or no file = stdin. }
program b3sum;
{$I pja.inc}
uses {$ifdef unix}cthreads,{$endif} SysUtils, Classes, pjablake3, pblake3c, pjablake3mt;

type TMode = (mPlain, mKeyed, mDerive);
const BUFSZ = 8 * 1024 * 1024;      { a multiple of 1024 }
var
  mode: TMode = mPlain; key: array[0..31] of Byte; context: AnsiString = '';
  outLen: SizeInt = 32; threads: Integer = 0; raw: Boolean = False; noNames: Boolean = False;
  check: Boolean = False; failed: Boolean = False; stdinUsed: Boolean = False;

procedure Fail(const msg: string); begin Writeln(StdErr, 'b3sum: ', msg); failed := True; end;

function Hex(const x: array of Byte; n: SizeInt): string; var i: SizeInt;
begin Result := ''; for i := 0 to n - 1 do Result := Result + LowerCase(IntToHex(x[i], 2)); end;

{ Reading runs ahead on its own thread through a ring of 3 buffers, so that reading and hashing overlap; a
  buffer is hashed once the next one is known to hold more data (then none of its chunks is the last). }
type
  TReader = class(TThread)
  private
    st: TStream;
  protected
    procedure Execute; override;
  public
    constructor Make(s: TStream);
  end;
const NBUF = 3;
var
  ring: array[0..NBUF - 1] of array of Byte; rlen: array[0..NBUF - 1] of SizeInt;
  fullEv, emptyEv: array[0..NBUF - 1] of PRTLEvent; rerr: string; rdone: PRTLEvent;

constructor TReader.Make(s: TStream);
begin inherited Create(True); st := s; FreeOnTerminate := True; end;

procedure TReader.Execute;
var j, have, got: SizeInt;
begin
  j := 0;
  try
    repeat
      RTLEventWaitFor(emptyEv[j]);
      have := 0;
      repeat
        got := st.Read(ring[j][have], BUFSZ - have);
        if got <= 0 then Break;
        Inc(have, got);
      until have = BUFSZ;
      rlen[j] := have;
      RTLEventSetEvent(fullEv[j]);
      if have < BUFSZ then Break;
      j := (j + 1) mod NBUF;
    until False;
  except on e: Exception do begin rerr := e.Message; rlen[j] := 0; RTLEventSetEvent(fullEv[j]); end; end;
  RTLEventSetEvent(rdone);
end;

function HashStream(s: TStream): string;
var h: TBlake3; o: array of Byte; j, nx: Integer; ready: array[0..NBUF - 1] of Boolean; rd: TReader;
  procedure WaitFull(k: Integer);
  begin if not ready[k] then begin RTLEventWaitFor(fullEv[k]); ready[k] := True; end; end;
begin
  case mode of
    mPlain: h.Init;
    mKeyed: h.InitKeyed(key, 32);
    mDerive: h.InitDeriveKey(PAnsiChar(context)^, Length(context));
  end;
  rerr := '';
  for j := 0 to NBUF - 1 do begin
    ready[j] := False; fullEv[j] := RTLEventCreate; emptyEv[j] := RTLEventCreate; RTLEventSetEvent(emptyEv[j]);
  end;
  rdone := RTLEventCreate;
  rd := TReader.Make(s); rd.Start;
  j := 0;
  repeat
    WaitFull(j);
    if rlen[j] = BUFSZ then begin
      nx := (j + 1) mod NBUF; WaitFull(nx);
      if rlen[nx] > 0 then Blake3UpdateChunksMT(h, ring[j][0], BUFSZ div 1024, threads)
      else Blake3UpdateMT(h, ring[j][0], BUFSZ, threads);
    end else Blake3UpdateMT(h, ring[j][0], rlen[j], threads);
    if rlen[j] < BUFSZ then Break;
    ready[j] := False; RTLEventSetEvent(emptyEv[j]);   { the reader may refill it }
    j := (j + 1) mod NBUF;
  until False;
  RTLEventWaitFor(rdone);
  for j := 0 to NBUF - 1 do begin RTLEventDestroy(fullEv[j]); RTLEventDestroy(emptyEv[j]); end;
  RTLEventDestroy(rdone);
  if rerr <> '' then raise Exception.Create(rerr);
  o := nil; SetLength(o, outLen + 1);
  h.FinalXof(o[0], outLen);
  Result := Hex(o, outLen);
end;

function HashFile(const name: string; out hx: string): Boolean;
var s: TStream;
begin
  Result := False; hx := '';
  try
    if name = '-' then begin
      if stdinUsed then begin Fail('stdin was already used'); Exit; end;
      stdinUsed := True; s := THandleStream.Create(StdInputHandle);
    end else s := TFileStream.Create(name, fmOpenRead or fmShareDenyWrite);
    try hx := HashStream(s); Result := True; finally s.Free; end;
  except on e: Exception do Fail(name + ': ' + e.Message); end;
end;

function Escaped(const name: string; out esc: string): Boolean;
var i: Integer;
begin
  esc := ''; Result := False;
  for i := 1 to Length(name) do
    case name[i] of
      '\': begin esc := esc + '\\'; Result := True; end;
      #10: begin esc := esc + '\n'; Result := True; end;
      #13: begin esc := esc + '\r'; Result := True; end;
    else esc := esc + name[i]; end;
end;

function Unescape(const s: string): string;
var i: Integer;
begin
  Result := ''; i := 1;
  while i <= Length(s) do begin
    if (s[i] = '\') and (i < Length(s)) then begin
      Inc(i);
      case s[i] of 'n': Result := Result + #10; 'r': Result := Result + #13; else Result := Result + s[i]; end;
    end else Result := Result + s[i];
    Inc(i);
  end;
end;

procedure DoFile(const name: string);
var hx, esc: string; b: array of Byte; i: Integer;
begin
  if not HashFile(name, hx) then Exit;
  if raw then begin
    b := nil; SetLength(b, outLen);
    for i := 0 to outLen - 1 do b[i] := StrToInt('$' + Copy(hx, 2 * i + 1, 2));
    if outLen > 0 then FileWrite(StdOutputHandle, b[0], outLen);
    Exit;
  end;
  if noNames then Writeln(hx)
  else if Escaped(name, esc) then Writeln('\', hx, '  ', esc)
  else Writeln(hx, '  ', name);
end;

procedure DoCheck(const listFile: string);
var l: TStringList; line, want, name, hx: string; esc: Boolean; ok, bad, miss: Integer; p: Integer;
begin
  l := TStringList.Create; ok := 0; bad := 0; miss := 0;
  try
    try
      if listFile = '-' then l.LoadFromStream(THandleStream.Create(StdInputHandle)) else l.LoadFromFile(listFile);
    except on e: Exception do begin Fail(listFile + ': ' + e.Message); Exit; end; end;
    for line in l do begin
      if line = '' then Continue;
      esc := line[1] = '\';
      if esc then want := Copy(line, 2, MaxInt) else want := line;
      p := Pos('  ', want);
      if p < 2 then begin Fail('improperly formatted line: ' + line); Continue; end;
      name := Copy(want, p + 2, MaxInt); want := LowerCase(Copy(want, 1, p - 1));
      if esc then name := Unescape(name);
      if not HashFile(name, hx) then begin Inc(miss); Writeln(name, ': FAILED (could not read)'); Continue; end;
      if Copy(hx, 1, Length(want)) = want then begin Inc(ok); Writeln(name, ': OK'); end
      else begin Inc(bad); Writeln(name, ': FAILED'); end;
    end;
  finally l.Free; end;
  if (bad > 0) or (miss > 0) then begin
    failed := True;
    if bad > 0 then Writeln(StdErr, 'b3sum: WARNING: ', bad, ' computed checksum(s) did NOT match');
  end;
end;

var i, n: Integer; a: string; files: TStringList; keyIn: THandleStream; kn, kk: SizeInt;
begin
  for i := 0 to NBUF - 1 do begin ring[i] := nil; SetLength(ring[i], BUFSZ); end;
  files := TStringList.Create;
  i := 1;
  while i <= ParamCount do begin
    a := ParamStr(i);
    if (a = '-l') or (a = '--length') then begin Inc(i); outLen := StrToIntDef(ParamStr(i), -1); if outLen < 0 then begin Fail('bad length'); Halt(2); end; end
    else if a = '--keyed' then mode := mKeyed
    else if a = '--derive-key' then begin mode := mDerive; Inc(i); context := ParamStr(i); end
    else if a = '--num-threads' then begin Inc(i); threads := StrToIntDef(ParamStr(i), 0); end
    else if a = '--raw' then raw := True
    else if a = '--no-names' then noNames := True
    else if (a = '-c') or (a = '--check') then check := True
    else if a = '--no-mmap' then begin end
    else if (a = '-h') or (a = '--help') then begin
      Writeln('b3sum [-l N] [--keyed | --derive-key CONTEXT] [--raw] [--no-names] [--num-threads N] [-c] [FILE...]'); Halt(0);
    end
    else if (a = '-') or (Copy(a, 1, 1) <> '-') then files.Add(a)
    else begin Fail('unknown option ' + a); Halt(2); end;
    Inc(i);
  end;
  if threads <= 0 then threads := Blake3Cpus;
  if mode = mKeyed then begin
    keyIn := THandleStream.Create(StdInputHandle); kn := 0;
    while kn < 32 do begin kk := keyIn.Read(key[kn], 32 - kn); if kk <= 0 then Break; Inc(kn, kk); end;
    if kn <> 32 then begin Fail('the key must be 32 bytes on stdin'); Halt(2); end;
    stdinUsed := True;
  end;
  if files.Count = 0 then files.Add('-');
  for n := 0 to files.Count - 1 do
    if check then DoCheck(files[n]) else DoFile(files[n]);
  if failed then Halt(1);
end.
