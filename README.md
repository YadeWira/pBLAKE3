# pBLAKE3

BLAKE3 in Pascal (FreePascal 3.2) with an optional C core for several chunks at once (SSE2).
Hash only for now (BLAKE3-128 = first 16 bytes). Output must equal the official BLAKE3 always.

- `src/pjablake3.pas`: `TBlake3` (Init / Update / Final) and `Blake3_128` (one pass). Needs `$R+ $Q+`.
- `src/b3chunks.c` + `src/pblake3c.pas`: the C chunk routine and the unit that installs it as `Blake3Chunks`.
- `tests/`: official vectors (`kat.txt`) checked on both paths. Run `./build.sh` (extra flags go to the C compiler, e.g. `-m32`).

Unit/API names are kept as PJA uses them; changes are announced to PJA first.

Big-endian: `scripts/fpc-ppc64be.sh` builds a PowerPC64 cross FreePascal (15 s) and CI runs the tests under qemu-ppc64; the shared library and C API are not tested on big-endian (no cross libc there).
