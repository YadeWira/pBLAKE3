/* Loads pblake3.dll with LoadLibrary and checks the official vectors through it,
   whole and in pieces. Pattern is the same xorshift32 as tests/test_blake3.pas. */
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
typedef long (*f_i)(void);
typedef intptr_t (*f_sz)(void);
typedef long (*f_init)(void *);
typedef long (*f_upd)(void *, const void *, intptr_t);
typedef long (*f_fin)(void *, uint8_t *);
typedef long (*f_one)(const void *, intptr_t, uint8_t *);
static void pattern(uint8_t *p, long n, uint32_t seed) {
  uint32_t x = seed; long i;
  for (i = 0; i < n; i++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; p[i] = (uint8_t)(x >> 3); }
}
static void hex(const uint8_t *h, char *o) { int i; for (i = 0; i < 16; i++) sprintf(o + 2 * i, "%02x", h[i]); }
int main(int argc, char **argv) {
  HMODULE m; FILE *f; char line[512]; int cells = 0, fails = 0;
  f_i uses; f_sz ssize; f_init init; f_upd upd; f_fin fin; f_one one;
  if (argc < 3) { fprintf(stderr, "usage: dll_test <dll> <kat.txt>\n"); return 2; }
  m = LoadLibraryA(argv[1]);
  if (!m) { fprintf(stderr, "LoadLibrary failed: %lu\n", GetLastError()); return 1; }
  uses = (f_i)GetProcAddress(m, "pblake3_uses_c"); ssize = (f_sz)GetProcAddress(m, "pblake3_state_size");
  init = (f_init)GetProcAddress(m, "pblake3_init"); upd = (f_upd)GetProcAddress(m, "pblake3_update");
  fin = (f_fin)GetProcAddress(m, "pblake3_final"); one = (f_one)GetProcAddress(m, "pblake3_128");
  if (!uses || !ssize || !init || !upd || !fin || !one) { fprintf(stderr, "missing export\n"); return 1; }
  printf("C chunks inside the DLL: %ld, state %ld B\n", uses(), (long)ssize());
  if (uses() != 1) { printf("FAIL: the C routine is not installed in the DLL\n"); fails++; }
  f = fopen(argv[2], "r");
  if (!f) { fprintf(stderr, "no kat\n"); return 1; }
  while (fgets(line, sizeof line, f)) {
    long n; char want[64]; uint8_t *d, h[16]; char got[40]; void *st; static const int steps[] = {1, 7, 63, 64, 65, 1024}; int s, ok;
    if (sscanf(line, "b3 %ld %32s", &n, want) != 2) continue;
    d = (uint8_t *)malloc(n ? n : 1); pattern(d, n, 0x1234567u ^ (uint32_t)n);
    one(d, n, h); hex(h, got); cells++;
    if (strcmp(got, want)) { fails++; printf("FAIL one-shot %ld\n", n); }
    st = malloc((size_t)ssize());
    for (s = 0, ok = 1; s < 6; s++) {
      long p = 0, k;
      if (n > 70000 && steps[s] < 63) continue;
      init(st);
      while (p < n) { k = steps[s]; if (p + k > n) k = n - p; upd(st, d + p, k); p += k; }
      fin(st, h); hex(h, got); if (strcmp(got, want)) ok = 0;
    }
    cells++; if (!ok) { fails++; printf("FAIL pieces %ld\n", n); }
    if (one(NULL, 5, h) != -1 || one(d, -1, h) != -1) { fails++; printf("FAIL bad args %ld\n", n); }
    free(st); free(d);
  }
  fclose(f); FreeLibrary(m);
  printf("%d cells, %d failures\n", cells, fails);
  return (fails || cells < 40) ? 1 : 0;
}
