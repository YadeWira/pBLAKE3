#!/usr/bin/env python3
"""The shared libraries (Pascal and plain C) against the official BLAKE3 Python binding (pip install blake3), in
process, exhaustively where it is cheap: every input size 0..N in the three modes, every size around chunk and
subtree boundaries, XOF lengths 0..400, random sizes up to some MiB, random pieces.
Usage: py_diff.py <library> [<library>...] [--max N] [--random N] [--seed S]"""
import ctypes, os, random, sys
import blake3

def load(path):
    L = ctypes.CDLL(os.path.abspath(path))
    vp, ip, u8p = ctypes.c_void_p, ctypes.c_ssize_t, ctypes.POINTER(ctypes.c_uint8)
    L.pblake3_state_size.restype = ip
    for n, a in (("pblake3_init", [vp]), ("pblake3_init_keyed", [vp, vp, ip]), ("pblake3_init_derive_key", [vp, vp, ip]),
                 ("pblake3_update", [vp, vp, ip]), ("pblake3_final_xof", [vp, vp, ip]),
                 ("pblake3_hash", [vp, ip, vp, ip]), ("pblake3_keyed_hash", [vp, vp, ip, vp, ip]),
                 ("pblake3_derive_key", [vp, ip, vp, ip, vp, ip])):
        getattr(L, n).argtypes = a; getattr(L, n).restype = ctypes.c_int
    return L

def run(L, mode, data, key, ctx, olen):
    out = ctypes.create_string_buffer(max(olen, 1)); d = ctypes.c_char_p(bytes(data)) if data else None
    if mode == 0: r = L.pblake3_hash(d, len(data), out, olen)
    elif mode == 1: r = L.pblake3_keyed_hash(key, d, len(data), out, olen)
    else: r = L.pblake3_derive_key(ctx, len(ctx), d, len(data), out, olen)
    assert r == 0
    return out.raw[:olen]

def pieces(L, mode, data, key, ctx, olen, rnd):
    st = ctypes.create_string_buffer(L.pblake3_state_size() + 64)
    if mode == 0: L.pblake3_init(st)
    elif mode == 1: L.pblake3_init_keyed(st, key, 32)
    else: L.pblake3_init_derive_key(st, ctx, len(ctx))
    p = 0
    while p < len(data):
        k = 1 + rnd.randrange(1 + rnd.randrange(5000)); k = min(k, len(data) - p)
        L.pblake3_update(st, bytes(data[p:p + k]), k); p += k
    out = ctypes.create_string_buffer(max(olen, 1)); L.pblake3_final_xof(st, out, olen)
    return out.raw[:olen]

def ref(mode, data, key, ctx, olen):
    if mode == 0: h = blake3.blake3(data)
    elif mode == 1: h = blake3.blake3(data, key=key)
    else: h = blake3.blake3(data, derive_key_context=ctx.decode())
    return h.digest(length=olen)

def main():
    args = sys.argv[1:]; libs = []; mx, nrand, seed = 9000, 300, 1
    i = 0
    while i < len(args):
        if args[i] == "--max": mx = int(args[i + 1]); i += 2
        elif args[i] == "--random": nrand = int(args[i + 1]); i += 2
        elif args[i] == "--seed": seed = int(args[i + 1]); i += 2
        else: libs.append(args[i]); i += 1
    rnd = random.Random(seed); key = bytes(rnd.randrange(256) for _ in range(32)); ctx = b"pBLAKE3 py_diff context"
    base = bytes(rnd.randrange(256) for _ in range(4 * 1024 * 1024 + 7)); fails = cells = 0
    sizes = list(range(0, mx + 1))
    for k in range(1, 400):
        for d in (-1, 0, 1): sizes.append(1024 * k + d)
    for e in range(10, 22):
        for d in (-2, -1, 0, 1, 2): sizes.append((1 << e) + d)
    for L in map(load, libs):
        name = os.path.basename(libs[0]) if False else None
        for n in sizes:
            if n < 0 or n > len(base): continue
            data = base[:n]; off = rnd.randrange(0, 1 + len(base) - n) if n < 100000 and rnd.random() < 0.3 else 0
            data = base[off:off + n]
            for mode in (0, 1, 2):
                for olen in ((32, 131) if n % 7 == 0 else (32,)):
                    cells += 1
                    if run(L, mode, data, key, ctx, olen) != ref(mode, data, key, ctx, olen): fails += 1; print("DIFF one-pass", n, mode, olen)
        for olen in range(0, 401):
            cells += 1
            if run(L, 0, base[:3000], key, ctx, olen) != ref(0, base[:3000], key, ctx, olen): fails += 1; print("DIFF xof", olen)
        for it in range(nrand):
            n = rnd.randrange(0, len(base)); mode = rnd.randrange(3); olen = rnd.randrange(0, 200); data = base[n // 3:n // 3 + n]
            cells += 1
            if pieces(L, mode, data, key, ctx, olen, rnd) != ref(mode, data, key, ctx, olen): fails += 1; print("DIFF pieces", n, mode, olen)
    print(f"{cells} comparisons, {fails} differences")
    sys.exit(1 if fails else 0)
main()
