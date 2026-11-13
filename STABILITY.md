# What pBLAKE3 promises

**The output never changes.** For every input, key, context string and output length, the bytes pBLAKE3
produces are the official BLAKE3's (BLAKE3-team/BLAKE3, `test_vectors.json` and the official `b3sum`). Formats
that store a BLAKE3-128 in files (PJA's `.pja`) can rely on it forever. A change that altered a single output
byte would be a bug, and is never a release.

How that is kept honest, on every push (CI, 7 targets):
- the official `test_vectors.json`: hash, keyed_hash and derive_key, full 131-byte outputs, whole and in pieces,
  on the C path and the pure Pascal path (`tests/test_official.pas`);
- the older frozen BLAKE3-128 vectors of PJA (`tests/kat.txt`);
- every SIMD level (4, 8, 16 chunks at a time) against the plain C one (`tests/chunks_diff.c`);
- the official `b3sum` against ours on random files around every boundary, all modes, 1 to 7 threads
  (`tests/diff_b3sum.sh`), and randomized splits/threads consistency (`tests/fuzz_split.pas`);
- Linux x64/x86/arm64, macOS arm64, Windows x64/x86, and big-endian PowerPC64 under qemu.

## Interfaces

Stable (a change needs a new major version and a notice to PJA first; additions are allowed in any release):
- the unit name `pjablake3` and its types `THash16` and `TCvWords`.
- `pjablake3`: `TBlake3` with `Init`, `Update`, `Final`, `FinalXof`, `InitKeyed`, `InitDeriveKey`; `Blake3_128`
  (both forms); `Blake3Chunks` and the `TBlake3Chunks` signature (and `Blake3ChunksKF`, its keyed twin).
- `pblake3_chunks_level(max)` in `src/b3chunks.c` (caps the SIMD level 0..3 and returns what the CPU can do; PJA's tests walk every path with it).
- `src/b3chunks.c`: `pblake3_chunks(in, n, counter, cv)` and `pblake3_chunks_kf(in, n, counter, key, flags, cv)` (the hooks' C side; it takes no memory and calls no library).
- the C API of `include/pblake3.h` (`PBLAKE3_API_VERSION`; a function is never changed or removed inside a version).

**Take `src/pja.inc` with the unit.** `pjablake3` starts with `{$I pja.inc}` (`$mode objfpc`, `$H+`, `$R+`, `$Q+`, `advancedrecords`) and
refuses to compile without range and overflow checks. The file is in this repository; a project that copies the
unit without PJA has to copy it too (PJA's own `pja.inc` is the same).

Not promised: the speed of any path, which SIMD level is used, the internals of `TBlake3`, the thread unit
`pjablake3mt` (it may change), and `b3sum`'s options beyond the official ones.

## Versions

Tags are `vMAJOR.MINOR.PATCH`. Take a tag, not `main`. Before 1.0.0 the interfaces above are kept as if it were
1.0.0, but the 1.0.0 tag waits until the projects that use pBLAKE3 have confirmed them.
