{ Installs the C chunk routine (b3chunks.c) as pjablake3.Blake3Chunks. }
unit pblake3c;
{$I pja.inc}
interface
implementation
uses pjablake3;
{$L b3chunks.o}
procedure pblake3_chunks(input: PByte; n: SizeInt; counter: QWord; cv: PLongWord); cdecl; external;
initialization
  Blake3Chunks := @pblake3_chunks;
end.
