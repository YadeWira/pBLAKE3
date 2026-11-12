/* Every vector level of the chunk routine (4, 8 or 16 chunks at a time, as far as this CPU goes) against the
   plain one (the same source built with -DB3_PLAIN, its symbol renamed): random bytes, 1..40 chunks, unaligned
   inputs, counters around 2^32; then how fast each is. */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
void pblake3_chunks(const uint8_t *in, intptr_t n, uint64_t counter, uint32_t *cv);
int pblake3_chunks_level(int max);
void pblake3_chunks_kf(const uint8_t *in, intptr_t n, uint64_t counter, const uint32_t *key, uint32_t fl, uint32_t *cv);
void pblake3_chunks_kf_plain(const uint8_t *in, intptr_t n, uint64_t counter, const uint32_t *key, uint32_t fl, uint32_t *cv);
void pblake3_chunks_plain(const uint8_t *in, intptr_t n, uint64_t counter, uint32_t *cv);
#define MAXN 40
static double bench(void (*f)(const uint8_t *, intptr_t, uint64_t, uint32_t *), const uint8_t *d, intptr_t n) {
  uint32_t *cv = (uint32_t *)malloc((size_t)n * 32); clock_t t0; int it = 0; double s;
  f(d, n, 0, cv); t0 = clock();
  do { f(d, n, (uint64_t)it, cv); it++; s = (double)(clock() - t0) / CLOCKS_PER_SEC; } while (s < 0.4);
  free(cv); return (double)it * (double)n * 1024.0 / s / 1e6;
}
int main(void) {
  static uint8_t buf[MAXN * 1024 + 7]; static uint32_t a[MAXN * 8 + 8], b[MAXN * 8 + 8];
  uint32_t x = 12345; int n, t, lv, bad = 0, runs = 0, top = pblake3_chunks_level(-1);
  uint64_t ctrs[] = {0, 1, 3, 255, 0xFFFFFFFDull, 0xFFFFFFFFull, 0x100000000ull, 0x1FFFFFFFEull, 0xFFFFFFFFFFFFFFF0ull};
  intptr_t big = 2048; uint8_t *d; size_t i;
  static const char *names[] = {"one at a time", "4 at a time (SSE2/NEON)", "8 at a time (AVX2)", "16 at a time (AVX-512)"};
  for (t = 0; t < (int)sizeof buf; t++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; buf[t] = (uint8_t)(x >> 3); }
  printf("this CPU: level %d (%s)\n", top, names[top]);
  d = (uint8_t *)malloc((size_t)big * 1024); for (i = 0; i < (size_t)big * 1024; i++) d[i] = (uint8_t)(i * 7);
  printf("plain: %.0f MB/s\n", bench(pblake3_chunks_plain, d, big));
  for (lv = 0; lv <= top; lv++) {
    int before = bad;
    pblake3_chunks_level(lv);
    for (n = 1; n <= MAXN; n++) for (t = 0; t < 9; t++) {
      int off = (n + t) % 7;
      memset(a, 0xAA, sizeof a); memset(b, 0xAA, sizeof b);
      pblake3_chunks(buf + off, n, ctrs[t], a); pblake3_chunks_plain(buf + off, n, ctrs[t], b);
      runs++;
      if (memcmp(a, b, sizeof a)) { bad++; printf("DIFF level %d n=%d counter=%llx\n", lv, n, (unsigned long long)ctrs[t]); }
    }
    /* a key and the keyed / derive_key flags */
    for (n = 1; n <= MAXN; n += 3) for (t = 0; t < 4; t++) {
      uint32_t key[8], fl = (t & 1) ? 16u : 64u; int q;
      for (q = 0; q < 8; q++) { x ^= x << 13; x ^= x >> 17; x ^= x << 5; key[q] = x; }
      memset(a, 0xAA, sizeof a); memset(b, 0xAA, sizeof b);
      pblake3_chunks_kf(buf + t, n, ctrs[t], key, fl, a); pblake3_chunks_kf_plain(buf + t, n, ctrs[t], key, fl, b);
      runs++;
      if (memcmp(a, b, sizeof a)) { bad++; printf("DIFF level %d keyed n=%d flags=%u\n", lv, n, fl); }
    }
    printf("level %d, %s: %s, %.0f MB/s\n", lv, names[lv], bad == before ? "same as plain" : "DIFFERENT", bench(pblake3_chunks, d, big));
  }
  free(d);
  printf("%d runs, %d differences\n", runs, bad);
  return bad != 0;
}
