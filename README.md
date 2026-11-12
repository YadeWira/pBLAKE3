# pBLAKE3

BLAKE3 in Pascal (FreePascal 3.2) with a C core that hashes many chunks at once (SSE2, AVX2, AVX-512, NEON,
chosen at run time). Output is the official BLAKE3's, always: see [STABILITY.md](STABILITY.md).

| | |
|---|---|
| `src/pjablake3.pas` | the library: `TBlake3` (`Init`, `Update`, `Final`; `FinalXof` any length; `InitKeyed`; `InitDeriveKey`) and `Blake3_128`. Needs `$R+ $Q+`. |
| `src/b3chunks.c`, `src/pblake3c.pas` | the C chunk routine (1, 4, 8, 16 chunks at a time, no libc) and the unit that installs it as `Blake3Chunks` |
| `src/pjablake3mt.pas` | big inputs on several threads (same hash) |
| `src/pblake3dll.pas`, `include/pblake3.h` | the C API as a shared library (`pblake3.dll`, `libpblake3.so`, `libpblake3.dylib`) |
| `src/b3sum.pas` | `b3sum`, the official tool's format: hash, `--keyed`, `--derive-key`, `-l`, `--raw`, `-c`, `--num-threads` |
| `tests/` | official vectors, SIMD-level diff, differential test against the official `b3sum`, fuzz |

Build and test: `./build.sh` (`FPC=`, `CC=`; extra flags go to the C compiler, e.g. `-m32`); the shared library and
its C API: `./lib.sh`. Targets in CI: Linux x64/x86/arm64, macOS arm64, Windows x64/x86 (also XP and 7), and
big-endian PowerPC64 under qemu (`scripts/fpc-ppc64be.sh` builds the cross compiler; the shared library is not
tested on big-endian).

Speed, chunk computation on GitHub runners (MB/s, one thread): plain C 0.5-1.0k; SSE2/NEON 1.4-1.7k; AVX2 3.0-3.4k;
AVX-512 5.9k. `b3sum` on 16 threads: about 3 GB/s here (the official one, with mmap, is faster).

Keyed hash and derive_key use the same SIMD paths and threads as the plain hash.

MIT, see LICENSE and NOTICE (BLAKE3 is by Jack O'Connor, Jean-Philippe Aumasson, Samuel Neves and Zooko Wilcox-O'Hearn).
