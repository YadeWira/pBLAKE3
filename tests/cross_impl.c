/* The two implementations of the C API against each other: the FreePascal library and the plain C one
   (src/pblake3.c), loaded side by side, on random inputs: sizes around every boundary, the three modes, output
   lengths 0..300, one pass and random pieces. Usage: cross_impl <pascal lib> <c lib> [iterations] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#ifdef _WIN32
#include <windows.h>
#define LOAD(p) LoadLibraryA(p)
#define SYM(h, n) ((void *)GetProcAddress((HMODULE)(h), n))
#define CC_ __cdecl
#else
#include <dlfcn.h>
#define LOAD(p) dlopen(p, RTLD_NOW | RTLD_LOCAL)
#define SYM(h, n) dlsym(h, n)
#define CC_
#endif
typedef struct {
  intptr_t (CC_ *ssize)(void);
  int (CC_ *init)(void *); int (CC_ *initk)(void *, const void *, intptr_t); int (CC_ *initd)(void *, const void *, intptr_t);
  int (CC_ *upd)(void *, const void *, intptr_t); int (CC_ *xof)(void *, uint8_t *, intptr_t);
  int (CC_ *hash)(const void *, intptr_t, uint8_t *, intptr_t); int (CC_ *keyed)(const void *, const void *, intptr_t, uint8_t *, intptr_t);
  int (CC_ *derive)(const void *, intptr_t, const void *, intptr_t, uint8_t *, intptr_t);
} api_t;
static int load(api_t *a, const char *path) {
  void *m = LOAD(path);
  if (!m) { fprintf(stderr, "cannot load %s\n", path); return 0; }
#define G(f, n) *(void **)&a->f = SYM(m, n); if (!a->f) { fprintf(stderr, "%s: missing %s\n", path, n); return 0; }
  G(ssize, "pblake3_state_size") G(init, "pblake3_init") G(initk, "pblake3_init_keyed") G(initd, "pblake3_init_derive_key")
  G(upd, "pblake3_update") G(xof, "pblake3_final_xof") G(hash, "pblake3_hash") G(keyed, "pblake3_keyed_hash") G(derive, "pblake3_derive_key")
  return 1;
}
static uint64_t seed = 88172645463325252ull;
static uint32_t rnd(uint32_t n) { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return (uint32_t)((seed >> 11) % n); }
static void pieces(api_t *a, void *st, const uint8_t *d, intptr_t n, uint32_t maxp) {
  intptr_t p = 0, k;
  while (p < n) { k = 1 + rnd(1 + rnd(maxp)); if (p + k > n) k = n - p; a->upd(st, d + p, k); p += k; }
}
int main(int argc, char **argv) {
  api_t P, C; int iters = argc > 3 ? atoi(argv[3]) : 300, it, fails = 0;
  static const long sizes[] = {0, 1, 63, 64, 65, 1023, 1024, 1025, 2048, 2049, 65535, 65536, 65537, 262144, 262145, 1000000};
  uint8_t key[32], ctx[40]; uint8_t *d, *o1, *o2, *o3, *o4; void *s1, *s2;
  if (argc < 3 || !load(&P, argv[1]) || !load(&C, argv[2])) return 2;
  s1 = malloc((size_t)P.ssize() + 64); s2 = malloc((size_t)C.ssize() + 64);
  o1 = (uint8_t *)malloc(400); o2 = (uint8_t *)malloc(400); o3 = (uint8_t *)malloc(400); o4 = (uint8_t *)malloc(400);
  for (it = 0; it < iters; it++) {
    long n = rnd(3) == 0 ? sizes[rnd(16)] + (long)rnd(3) - 1 : (long)rnd(300000); int mode = (int)rnd(3), i; intptr_t ol = rnd(301), cl = 1 + rnd(39);
    if (n < 0) n = 0;
    d = (uint8_t *)malloc(n + 1); for (i = 0; i < n; i++) d[i] = (uint8_t)rnd(256);
    for (i = 0; i < 32; i++) key[i] = (uint8_t)rnd(256);
    for (i = 0; i < 40; i++) ctx[i] = (uint8_t)rnd(256);
    memset(o1, 0xAA, 400); memset(o2, 0xAA, 400); memset(o3, 0xAA, 400); memset(o4, 0xAA, 400);
    if (mode == 0) { P.hash(d, n, o1, ol); C.hash(d, n, o2, ol); P.init(s1); C.init(s2); }
    else if (mode == 1) { P.keyed(key, d, n, o1, ol); C.keyed(key, d, n, o2, ol); P.initk(s1, key, 32); C.initk(s2, key, 32); }
    else { P.derive(ctx, cl, d, n, o1, ol); C.derive(ctx, cl, d, n, o2, ol); P.initd(s1, ctx, cl); C.initd(s2, ctx, cl); }
    pieces(&P, s1, d, n, 4000); P.xof(s1, o3, ol);        /* Pascal, in pieces */
    pieces(&C, s2, d, n, 9000); C.xof(s2, o4, ol);        /* C, in other pieces */
    if (memcmp(o1, o2, 400) || memcmp(o1, o3, 400) || memcmp(o1, o4, 400)) { fails++; printf("DIFF iter %d: %ld B mode %d out %ld\n", it, n, mode, (long)ol); }
    free(d);
  }
  free(s1); free(s2); free(o1); free(o2); free(o3); free(o4);
  printf("%d iterations, %d failures\n", iters, fails);
  return fails != 0;
}
