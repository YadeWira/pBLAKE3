/* The vector chunk routine against the plain one (same source built with -DB3_PLAIN and the
   symbol renamed): random bytes, 1..11 chunks, counters around 2^32. For any CPU that has a vector path. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
void pblake3_chunks(const uint8_t *in, intptr_t n, uint64_t counter, uint32_t *cv);
void pblake3_chunks_plain(const uint8_t *in, intptr_t n, uint64_t counter, uint32_t *cv);
static double bench(void (*f)(const uint8_t *, intptr_t, uint64_t, uint32_t *), const uint8_t *d, intptr_t n) {
  uint32_t *cv = (uint32_t *)malloc((size_t)n * 32); clock_t t0; int it = 0; double s;
  f(d, n, 0, cv); t0 = clock();
  do { f(d, n, (uint64_t)it, cv); it++; s = (double)(clock() - t0) / CLOCKS_PER_SEC; } while (s < 0.5);
  free(cv); return (double)it * (double)n * 1024.0 / s / 1e6;
}
int main(void) {
  static uint8_t buf[11 * 1024 + 7]; uint32_t a[88], b[88]; uint32_t x = 12345; int n, t, bad = 0, runs = 0;
  uint64_t ctrs[] = {0, 1, 3, 255, 0xFFFFFFFDull, 0xFFFFFFFFull, 0x100000000ull, 0x1FFFFFFFEull, 0xFFFFFFFFFFFFFFF0ull};
  for (t = 0; t < (int)sizeof buf; t++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; buf[t] = (uint8_t)(x >> 3); }
  for (n = 1; n <= 11; n++) for (t = 0; t < 9; t++) {
    int off = (n + t) % 7;  /* unaligned inputs too */
    memset(a, 0xAA, sizeof a); memset(b, 0xAA, sizeof b);
    pblake3_chunks(buf + off, n, ctrs[t], a); pblake3_chunks_plain(buf + off, n, ctrs[t], b);
    runs++; if (memcmp(a, b, (size_t)n * 32)) { bad++; printf("DIFF n=%d counter=%llx\n", n, (unsigned long long)ctrs[t]); }
    if (memcmp(a + 8 * n, b + 8 * n, (size_t)(88 - 8 * n) * 4)) { bad++; printf("WROTE PAST n=%d\n", n); }
  }
  printf("%d runs, %d differences\n", runs, bad);
  { intptr_t big = 2048; uint8_t *d = (uint8_t *)malloc((size_t)big * 1024); size_t i;
    for (i = 0; i < (size_t)big * 1024; i++) d[i] = (uint8_t)(i * 7);
    printf("chunks: %.0f MB/s here, %.0f MB/s plain\n", bench(pblake3_chunks, d, big), bench(pblake3_chunks_plain, d, big)); free(d); }
  return bad != 0;
}
