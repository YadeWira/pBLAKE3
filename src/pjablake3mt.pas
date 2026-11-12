{ pjablake3 on several threads, for big inputs. The workers compute the chunks' chaining values (each through
  Blake3Chunks, so with the SIMD paths) and merge them into subtrees of 64 chunks; the calling thread puts
  the subtrees into the tree (one parent compression per 64 chunks). The hash is the same, thread count or not.
  Not for PJA's core: it needs threads (on Unix, put cthreads first in the program's uses). }
unit pjablake3mt;
{$I pja.inc}
interface
uses pjablake3;

{ nChunks whole chunks at data, with more input to follow them. Plain mode is where threads help; any other
  state just hashes serially. }
procedure Blake3UpdateChunksMT(var h: TBlake3; const data; nChunks: SizeInt; threads: Integer);
{ any length (it keeps the last chunk for Update, so the tail is exact) }
procedure Blake3UpdateMT(var h: TBlake3; const data; len: SizeInt; threads: Integer);
function Blake3Cpus: Integer;

implementation
uses Classes;

const
  CHUNK_BYTES = 1024;
  GROUP_LOG = 6; GROUP = 1 shl GROUP_LOG;   { subtrees of 64 chunks: the workers merge their parents too }
  BLOCK_CHUNKS = 16384;                     { 16 MiB of input per round }
  MIN_CHUNKS_MT = 256;                      { under 256 KiB the threads cost more than they save }

{ chunks [0, cnt) at pp, numbered from fst, cnt a multiple of 64: their 64-chunk subtrees' values into sb
  (cv is scratch, 8 words per chunk) }
procedure ShareWork(pp: PByte; fst: QWord; cnt: SizeInt; cv, sb: PLongWord);
var gi, j, i: SizeInt; c: TCvWords;
begin
  if Assigned(Blake3Chunks) then Blake3Chunks(pp, cnt, fst, cv)
  else
    for i := 0 to cnt - 1 do begin
      Blake3ChunkCv(pp + i * CHUNK_BYTES, fst + QWord(i), c);
      for j := 0 to 7 do cv[8 * i + j] := c[j];
    end;
  for gi := 0 to cnt div GROUP - 1 do begin
    Blake3MergeCvs(cv + 8 * GROUP * gi, GROUP_LOG);
    for j := 0 to 7 do sb[8 * gi + j] := cv[8 * GROUP * gi + j];
  end;
end;

{ any number of chunks, their own values (no merging) }
procedure ChunkWork(pp: PByte; fst: QWord; cnt: SizeInt; cv: PLongWord);
var j, i: SizeInt; c: TCvWords;
begin
  if cnt <= 0 then Exit;
  if Assigned(Blake3Chunks) then Blake3Chunks(pp, cnt, fst, cv)
  else
    for i := 0 to cnt - 1 do begin
      Blake3ChunkCv(pp + i * CHUNK_BYTES, fst + QWord(i), c);
      for j := 0 to 7 do cv[8 * i + j] := c[j];
    end;
end;

type
  TWorker = class(TThread)
  private
    p: PByte; first: QWord; count: SizeInt; cv, sb: PLongWord; done: PRTLEvent;
  protected
    procedure Execute; override;
  public
    constructor Make(ap: PByte; afirst: QWord; acount: SizeInt; acv, asb: PLongWord; adone: PRTLEvent);
  end;

{ The workers are not joined with TThread.WaitFor (FPC's takes ~100 ms per thread on Unix): each one signals
  an event when it is done, and frees itself. }
constructor TWorker.Make(ap: PByte; afirst: QWord; acount: SizeInt; acv, asb: PLongWord; adone: PRTLEvent);
begin
  inherited Create(True); p := ap; first := afirst; count := acount; cv := acv; sb := asb; done := adone;
  FreeOnTerminate := True;
end;

procedure TWorker.Execute;
begin ShareWork(p, first, count, cv, sb); RTLEventSetEvent(done); end;

function Blake3Cpus: Integer;
begin Result := TThread.ProcessorCount; if Result < 1 then Result := 1; end;

procedure Blake3UpdateChunksMT(var h: TBlake3; const data; nChunks: SizeInt; threads: Integer);
var p: PByte; n, per, k, i, t, groups, lone, mis: SizeInt; cvs, sub: array of LongWord; ev: array of PRTLEvent;
    first: QWord; wk: TWorker;
begin
  if nChunks <= 0 then Exit;
  p := @data;
  h.FlushPending;     { more input follows these chunks (the contract), so a pending chunk end can be closed }
  if (threads < 2) or (nChunks < MIN_CHUNKS_MT) or not h.CanTakeChunkCvs then begin
    h.Update(p^, nChunks * CHUNK_BYTES); Exit;
  end;
  if threads > 64 then threads := 64;
  { to a multiple of 64 chunks first, so that the groups are subtrees of the whole tree }
  mis := SizeInt(h.ChunkIndex and (GROUP - 1));
  if mis <> 0 then begin
    k := GROUP - mis; if k > nChunks then k := nChunks;
    h.Update(p^, k * CHUNK_BYTES); h.FlushPending; Inc(p, k * CHUNK_BYTES); Dec(nChunks, k);
  end;
  cvs := nil; SetLength(cvs, 8 * BLOCK_CHUNKS);
  sub := nil; SetLength(sub, 8 * (BLOCK_CHUNKS div GROUP));
  ev := nil; SetLength(ev, threads);
  while nChunks > 0 do begin
    n := nChunks; if n > BLOCK_CHUNKS then n := BLOCK_CHUNKS;
    groups := n div GROUP; lone := n - groups * GROUP;      { lone: fewer than 64 chunks, at the very end }
    first := h.ChunkIndex;
    if groups > 0 then begin
      per := (groups + threads - 1) div threads;            { groups per thread }
      for i := 0 to threads - 1 do ev[i] := nil;
      k := per;                                             { in groups: thread i takes [i*per, (i+1)*per) }
      for i := 1 to threads - 1 do begin
        if k >= groups then Break;
        t := per; if k + t > groups then t := groups - k;
        ev[i] := RTLEventCreate;
        wk := TWorker.Make(p + k * GROUP * CHUNK_BYTES, first + QWord(k * GROUP), t * GROUP,
                           @cvs[8 * k * GROUP], @sub[8 * k], ev[i]);
        wk.Start;
        k := k + t;
      end;
      t := per; if t > groups then t := groups;
      ShareWork(p, first, t * GROUP, @cvs[0], @sub[0]);
      for i := 1 to threads - 1 do if ev[i] <> nil then begin RTLEventWaitFor(ev[i]); RTLEventDestroy(ev[i]); ev[i] := nil; end;
      h.AddSubtreeCvs(sub[0], groups, GROUP_LOG);
    end;
    if lone > 0 then begin
      ChunkWork(p + groups * GROUP * CHUNK_BYTES, first + QWord(groups * GROUP), lone, @cvs[0]);
      h.AddChunkCvs(cvs[0], lone);
    end;
    Inc(p, n * CHUNK_BYTES); Dec(nChunks, n);
  end;
end;

procedure Blake3UpdateMT(var h: TBlake3; const data; len: SizeInt; threads: Integer);
var p: PByte; k: SizeInt;
begin
  if len <= 0 then Exit;
  p := @data;
  h.FlushPending;       { len > 0: there is more input }
  k := (len - 1) div CHUNK_BYTES;
  if (k > 0) and h.CanTakeChunkCvs then begin
    Blake3UpdateChunksMT(h, p^, k, threads);
    Inc(p, k * CHUNK_BYTES); Dec(len, k * CHUNK_BYTES);
  end;
  h.Update(p^, len);
end;

end.
