/* The C API (include/pblake3.h) through the shared library, loaded at run time
   (LoadLibrary / dlopen), against the official test vectors (tests/official_hash.txt):
   hash, keyed_hash and derive_key, 131-byte outputs, one pass and in pieces,
   plus the argument checks. Usage: api_test <library> <official_hash.txt> */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#ifdef _WIN32
#include <windows.h>
#define LOAD(p) LoadLibraryA(p)
#define SYM(h, n) ((void *)GetProcAddress((HMODULE)(h), n))
#else
#include <dlfcn.h>
#define LOAD(p) dlopen(p, RTLD_NOW)
#define SYM(h, n) dlsym(h, n)
#endif
#include "../include/pblake3.h"
#define CALL
#ifdef _WIN32
#define CC_ __cdecl
#else
#define CC_
#endif
#define FN(ret, name, args) static ret (CC_ *name) args
FN(int, f_version, (void)); FN(int, f_uses_c, (void)); FN(intptr_t, f_ssize, (void));
FN(int, f_init, (void *)); FN(int, f_initk, (void *, const void *, intptr_t));
FN(int, f_initd, (void *, const void *, intptr_t)); FN(int, f_upd, (void *, const void *, intptr_t));
FN(int, f_fin, (void *, uint8_t *)); FN(int, f_xof, (void *, uint8_t *, intptr_t));
FN(int, f_128, (const void *, intptr_t, uint8_t *)); FN(int, f_hash, (const void *, intptr_t, uint8_t *, intptr_t));
FN(int, f_keyed, (const void *, const void *, intptr_t, uint8_t *, intptr_t));
FN(int, f_derive, (const void *, intptr_t, const void *, intptr_t, uint8_t *, intptr_t));
static int cells, fails;
static void check(int ok, const char *what, long n) { cells++; if (!ok) { fails++; printf("FAIL %s (%ld)\n", what, n); } }
static void hex(const uint8_t *h, int n, char *o) { int i; for (i = 0; i < n; i++) sprintf(o + 2 * i, "%02x", h[i]); }
#define KEY "whats the Elvish word for friend"
#define CTX "BLAKE3 2019-12-27 16:29:52 test vectors context"
int main(int argc, char **argv) {
  void *m; FILE *f; char line[600]; uint8_t out[131], o2[200]; char got[300];
  static const int steps[] = {0, 1, 64, 1000, 1024, 3000}; void *st;
  if (argc < 3) { fprintf(stderr, "usage: api_test <library> <official_hash.txt>\n"); return 2; }
  m = LOAD(argv[1]);
  if (!m) { fprintf(stderr, "cannot load %s\n", argv[1]); return 1; }
#define GET(v, n) do { *(void **)&v = SYM(m, n); if (!v) { fprintf(stderr, "missing export %s\n", n); return 1; } } while (0)
  GET(f_version, "pblake3_version"); GET(f_uses_c, "pblake3_uses_c"); GET(f_ssize, "pblake3_state_size");
  GET(f_init, "pblake3_init"); GET(f_initk, "pblake3_init_keyed"); GET(f_initd, "pblake3_init_derive_key");
  GET(f_upd, "pblake3_update"); GET(f_fin, "pblake3_final"); GET(f_xof, "pblake3_final_xof");
  GET(f_128, "pblake3_128"); GET(f_hash, "pblake3_hash"); GET(f_keyed, "pblake3_keyed_hash"); GET(f_derive, "pblake3_derive_key");
  printf("API %ld, C chunks: %ld, state %ld B\n", (long)f_version(), (long)f_uses_c(), (long)f_ssize());
  check(f_version() == PBLAKE3_API_VERSION, "version", 0);
  check(f_uses_c() == 1, "the C chunk routine is installed", 0);
  st = malloc((size_t)f_ssize());
  f = fopen(argv[2], "r"); if (!f) { fprintf(stderr, "no vectors\n"); return 1; }
  while (fgets(line, sizeof line, f)) {
    char mode[32], want[300]; long n, i; uint8_t *d; int s;
    if (line[0] == '#' || sscanf(line, "%31s %ld %290s", mode, &n, want) != 3) continue;
    d = (uint8_t *)malloc(n ? n : 1); for (i = 0; i < n; i++) d[i] = (uint8_t)(i % 251);
    /* one pass */
    memset(out, 0, sizeof out);
    if (!strcmp(mode, "hash")) f_hash(d, n, out, 131);
    else if (!strcmp(mode, "keyed_hash")) f_keyed(KEY, d, n, out, 131);
    else f_derive(CTX, (intptr_t)strlen(CTX), d, n, out, 131);
    hex(out, 131, got); check(!strcmp(got, want), mode, n);
    /* in pieces; the state keeps going after a Final */
    for (s = 0; s < 6; s++) {
      long step = s ? steps[s] : (n ? n : 1), p = 0, k;
      if (!strcmp(mode, "hash")) f_init(st);
      else if (!strcmp(mode, "keyed_hash")) f_initk(st, KEY, 32);
      else f_initd(st, CTX, (intptr_t)strlen(CTX));
      while (p < n) { k = step; if (p + k > n) k = n - p; f_upd(st, d + p, k); p += k; }
      memset(out, 0, sizeof out); f_xof(st, out, 131); hex(out, 131, got);
      check(!strcmp(got, want), "pieces", n);
      f_xof(st, o2, 100); hex(o2, 100, got); check(!strncmp(got, want, 200), "xof prefix, again", n);
      if (!strcmp(mode, "hash")) { f_fin(st, o2); hex(o2, 16, got); check(!strncmp(got, want, 32), "final 128", n); }
    }
    if (!strcmp(mode, "hash")) { f_128(d, n, o2); hex(o2, 16, got); check(!strncmp(got, want, 32), "128 one pass", n); }
    free(d);
  }
  fclose(f);
  /* bad arguments are refused, not crashed on */
  check(f_hash(NULL, 5, out, 32) == -1, "NULL data", 0);
  check(f_hash(out, -1, out, 32) == -1, "negative length", 0);
  check(f_hash(out, 3, NULL, 32) == -1, "NULL output", 0);
  check(f_hash(out, 3, out, -1) == -1, "negative output length", 0);
  check(f_hash(NULL, 0, out, 32) == 0, "empty input is fine", 0);
  check(f_hash(out, 0, NULL, 0) == 0, "empty output is fine", 0);
  check(f_initk(st, KEY, 31) == -1, "key of 31 bytes", 0);
  check(f_initk(st, NULL, 32) == -1, "NULL key", 0);
  check(f_keyed(NULL, out, 1, out, 32) == -1, "keyed with NULL key", 0);
  check(f_init(NULL) == -1 && f_upd(NULL, out, 1) == -1 && f_fin(NULL, out) == -1, "NULL state", 0);
  check(f_initd(st, NULL, 3) == -1, "NULL context", 0);
  free(st);
  printf("%d cells, %d failures\n", cells, fails);
  return (fails || cells < 1000) ? 1 : 0;
}
