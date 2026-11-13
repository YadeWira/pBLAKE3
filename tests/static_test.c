/* The plain C implementation linked straight into a test (no shared library), for targets that run under qemu-user
   or anywhere dlopen is not handy: the official vectors (tests/official_hash.txt), all three modes, 131-byte outputs, whole
   and in pieces.  cc tests/static_test.c -o static_test && ./static_test tests/official_hash.txt */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../src/pblake3.c"
static void hex(const uint8_t *h, int n, char *o) { int i; for (i = 0; i < n; i++) sprintf(o + 2 * i, "%02x", h[i]); }
#define KEY "whats the Elvish word for friend"
#define CTX "BLAKE3 2019-12-27 16:29:52 test vectors context"
int main(int argc, char **argv) {
  FILE *f; char line[600], mode[32], want[300], got[300]; long n, i; int cells = 0, fails = 0; uint8_t out[131], *d; void *st;
  if (argc < 2 || !(f = fopen(argv[1], "r"))) { fprintf(stderr, "usage: static_test <official_hash.txt>\n"); return 2; }
  st = malloc((size_t)pblake3_state_size());
  printf("SIMD level here: %d\n", pblake3_chunks_level(-1));
  while (fgets(line, sizeof line, f)) {
    int step; static const int steps[] = {0, 1, 64, 1000, 1024, 3000};
    if (line[0] == '#' || sscanf(line, "%31s %ld %290s", mode, &n, want) != 3) continue;
    d = (uint8_t *)malloc(n ? n : 1); for (i = 0; i < n; i++) d[i] = (uint8_t)(i % 251);
    memset(out, 0, sizeof out);
    if (!strcmp(mode, "hash")) pblake3_hash(d, n, out, 131);
    else if (!strcmp(mode, "keyed_hash")) pblake3_keyed_hash(KEY, d, n, out, 131);
    else pblake3_derive_key(CTX, (intptr_t)strlen(CTX), d, n, out, 131);
    hex(out, 131, got); cells++; if (strcmp(got, want)) { fails++; printf("FAIL %s %ld one pass\n", mode, n); }
    for (step = 0; step < 6; step++) {
      long k = step ? steps[step] : (n ? n : 1), p = 0, c;
      if (!strcmp(mode, "hash")) pblake3_init(st); else if (!strcmp(mode, "keyed_hash")) pblake3_init_keyed(st, KEY, 32);
      else pblake3_init_derive_key(st, CTX, (intptr_t)strlen(CTX));
      while (p < n) { c = k; if (p + c > n) c = n - p; pblake3_update(st, d + p, c); p += c; }
      memset(out, 0, sizeof out); pblake3_final_xof(st, out, 131); hex(out, 131, got);
      cells++; if (strcmp(got, want)) { fails++; printf("FAIL %s %ld pieces %ld\n", mode, n, k); }
    }
    free(d);
  }
  fclose(f); free(st);
  printf("%d cells, %d failures\n", cells, fails);
  return fails != 0;
}
