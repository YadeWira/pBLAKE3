# pBLAKE3 API

## Pascal (`src/pjablake3.pas`, needs `src/pja.inc`)

```pascal
uses pjablake3, pblake3c;      // pblake3c links b3chunks.o and installs the SIMD hooks; leave it out for pure Pascal
var h: TBlake3; d: THash16; big: array[0..31] of Byte;

h.Init;                        // or h.InitKeyed(key, 32)  or  h.InitDeriveKey(context, Length(context))
h.Update(data, len);           // as many times as you like, any sizes
d := h.Final;                  // BLAKE3-128: the first 16 bytes
h.FinalXof(big, 32);           // any output length; Final / FinalXof can be called again and Update can go on
d := Blake3_128(bytes);        // one pass over a TBytes; a second form takes two ranges (a, b) in a row
```

- `Blake3Chunks` / `Blake3ChunksKF`: variables holding the C chunk routines (`pblake3c` sets them). `nil` = this unit's own
  compression, the same output.
- Bad arguments (negative length, a key that is not 32 bytes) raise `ERangeError`.
- `pjablake3mt`: `Blake3UpdateMT(h, data, len, threads)` hashes a big buffer on several threads (any mode); put `cthreads`
  first in the program's uses on Unix.

## C (`include/pblake3.h`, shared library)

`pblake3_init`, `pblake3_init_keyed`, `pblake3_init_derive_key`, `pblake3_update`, `pblake3_final` (16 bytes),
`pblake3_final_xof`, and one-pass `pblake3_128`, `pblake3_hash`, `pblake3_keyed_hash`, `pblake3_derive_key`.
You allocate the state (`pblake3_state_size()` bytes); every function returns 0, or -1 for a bad argument. See the header
for the details, and `tests/api_test.c` for a complete caller.

## The chunk routine (`src/b3chunks.c`)

`pblake3_chunks(in, n, counter, cv)` and `pblake3_chunks_kf(in, n, counter, key, flags, cv)` compute the chaining values of
`n` whole chunks (8 words each). No memory, no library. `pblake3_chunks_level(max)` caps the SIMD level (0 one chunk at a
time, 1 four, 2 AVX2, 3 AVX-512) and returns what the CPU supports; the level is chosen on the first call.

## `b3sum`

`b3sum [-l N] [--keyed | --derive-key CONTEXT] [--raw] [--no-names] [--num-threads N] [-c] [FILE...]`, output as the official tool's.
