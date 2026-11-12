/* pBLAKE3: BLAKE3 chunks, several at once (pjablake3.Blake3Chunks).
   Every full chunk that is not the last one of the input gets its chaining
   value here, four at a time in SSE2 or NEON (one chunk per 32-bit lane),
   the rest one at a time. No memory taken, no library called. Plain path: build with
   -DB3_PLAIN (or no SSE2); both give the same words. */
#include <stdint.h>
#if defined(__SSE2__) && !defined(B3_PLAIN)
#include <emmintrin.h>
#define B3_SSE2 1
#elif defined(__aarch64__) && defined(__ARM_NEON) && !defined(B3_PLAIN) && \
      (!defined(__BYTE_ORDER__) || __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
#include <arm_neon.h>
#define B3_NEON 1
#endif
enum { B3_CHUNK_START = 1, B3_CHUNK_END = 2, B3_BLOCKS = 16 };

static const uint32_t B3IV[8] = {0x6A09E667u, 0xBB67AE85u, 0x3C6EF372u, 0xA54FF53Au,
                                 0x510E527Fu, 0x9B05688Cu, 0x1F83D9ABu, 0x5BE0CD19u};
static const uint8_t B3SCHED[7][16] = {
  {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15},
  {2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8},
  {3, 4, 10, 12, 13, 2, 7, 14, 6, 5, 9, 0, 11, 15, 8, 1},
  {10, 7, 12, 9, 14, 3, 13, 15, 4, 0, 11, 2, 5, 8, 1, 6},
  {12, 13, 9, 11, 15, 10, 14, 8, 7, 2, 5, 3, 0, 1, 6, 4},
  {9, 14, 11, 5, 8, 12, 15, 1, 13, 3, 0, 10, 2, 6, 4, 7},
  {11, 15, 5, 0, 1, 9, 8, 6, 14, 10, 2, 12, 3, 4, 7, 13}};

static inline uint32_t b3rot(uint32_t w, int c) { return (w >> c) | (w << (32 - c)); }
static inline uint32_t b3load(const uint8_t *p) {
  return (uint32_t)p[0] | (uint32_t)p[1] << 8 | (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}
static inline void b3g(uint32_t *s, int a, int b, int c, int d, uint32_t x, uint32_t y) {
  s[a] = s[a] + s[b] + x; s[d] = b3rot(s[d] ^ s[a], 16); s[c] = s[c] + s[d]; s[b] = b3rot(s[b] ^ s[c], 12);
  s[a] = s[a] + s[b] + y; s[d] = b3rot(s[d] ^ s[a], 8); s[c] = s[c] + s[d]; s[b] = b3rot(s[b] ^ s[c], 7);
}

/* one chunk of 1024 bytes, number counter: its chaining value */
static void b3chunk(const uint8_t *in, uint64_t counter, uint32_t *cv) {
  uint32_t h[8], s[16], m[16];
  int i, b, r;
  for (i = 0; i < 8; i++) h[i] = B3IV[i];
  for (b = 0; b < B3_BLOCKS; b++) {
    for (i = 0; i < 16; i++) m[i] = b3load(in + 64 * b + 4 * i);
    for (i = 0; i < 8; i++) { s[i] = h[i]; s[i + 8] = B3IV[i]; }
    s[12] = (uint32_t)counter; s[13] = (uint32_t)(counter >> 32); s[14] = 64;
    s[15] = (b == 0 ? B3_CHUNK_START : 0) | (b == B3_BLOCKS - 1 ? B3_CHUNK_END : 0);
    for (r = 0; r < 7; r++) {
      const uint8_t *q = B3SCHED[r];
      b3g(s, 0, 4, 8, 12, m[q[0]], m[q[1]]);
      b3g(s, 1, 5, 9, 13, m[q[2]], m[q[3]]);
      b3g(s, 2, 6, 10, 14, m[q[4]], m[q[5]]);
      b3g(s, 3, 7, 11, 15, m[q[6]], m[q[7]]);
      b3g(s, 0, 5, 10, 15, m[q[8]], m[q[9]]);
      b3g(s, 1, 6, 11, 12, m[q[10]], m[q[11]]);
      b3g(s, 2, 7, 8, 13, m[q[12]], m[q[13]]);
      b3g(s, 3, 4, 9, 14, m[q[14]], m[q[15]]);
    }
    for (i = 0; i < 8; i++) h[i] = s[i] ^ s[i + 8];
  }
  for (i = 0; i < 8; i++) cv[i] = h[i];
}

#ifdef B3_SSE2
#define ROTV(x, c) _mm_or_si128(_mm_srli_epi32((x), (c)), _mm_slli_epi32((x), 32 - (c)))
static inline __m128i rot16v(__m128i x) { return _mm_shufflehi_epi16(_mm_shufflelo_epi16(x, 0xB1), 0xB1); }
static inline void g4(__m128i *v, int a, int b, int c, int d, __m128i x, __m128i y) {
  v[a] = _mm_add_epi32(_mm_add_epi32(v[a], v[b]), x); v[d] = rot16v(_mm_xor_si128(v[d], v[a]));
  v[c] = _mm_add_epi32(v[c], v[d]); v[b] = ROTV(_mm_xor_si128(v[b], v[c]), 12);
  v[a] = _mm_add_epi32(_mm_add_epi32(v[a], v[b]), y); v[d] = ROTV(_mm_xor_si128(v[d], v[a]), 8);
  v[c] = _mm_add_epi32(v[c], v[d]); v[b] = ROTV(_mm_xor_si128(v[b], v[c]), 7);
}
/* rows (one lane's 4 words each) to columns (one word of the 4 lanes each), and back */
static inline void transpose4(__m128i *a, __m128i *b, __m128i *c, __m128i *d) {
  __m128i ab0 = _mm_unpacklo_epi32(*a, *b), ab1 = _mm_unpackhi_epi32(*a, *b);
  __m128i cd0 = _mm_unpacklo_epi32(*c, *d), cd1 = _mm_unpackhi_epi32(*c, *d);
  *a = _mm_unpacklo_epi64(ab0, cd0); *b = _mm_unpackhi_epi64(ab0, cd0);
  *c = _mm_unpacklo_epi64(ab1, cd1); *d = _mm_unpackhi_epi64(ab1, cd1);
}
/* four consecutive chunks, numbers counter .. counter + 3 */
static void b3chunk4(const uint8_t *in, uint64_t counter, uint32_t *cv) {
  __m128i h[8], v[16], m[16];
  int i, b, r;
  uint64_t c0 = counter, c1 = counter + 1, c2 = counter + 2, c3 = counter + 3;
  __m128i lo = _mm_set_epi32((int)(uint32_t)c3, (int)(uint32_t)c2, (int)(uint32_t)c1, (int)(uint32_t)c0);
  __m128i hi = _mm_set_epi32((int)(uint32_t)(c3 >> 32), (int)(uint32_t)(c2 >> 32), (int)(uint32_t)(c1 >> 32),
                             (int)(uint32_t)(c0 >> 32));
  for (i = 0; i < 8; i++) h[i] = _mm_set1_epi32((int)B3IV[i]);
  for (b = 0; b < B3_BLOCKS; b++) {
    for (i = 0; i < 4; i++) {
      const uint8_t *p = in + 64 * b + 16 * i;
      m[4 * i] = _mm_loadu_si128((const __m128i *)p);
      m[4 * i + 1] = _mm_loadu_si128((const __m128i *)(p + 1024));
      m[4 * i + 2] = _mm_loadu_si128((const __m128i *)(p + 2048));
      m[4 * i + 3] = _mm_loadu_si128((const __m128i *)(p + 3072));
      transpose4(&m[4 * i], &m[4 * i + 1], &m[4 * i + 2], &m[4 * i + 3]);
    }
    for (i = 0; i < 8; i++) v[i] = h[i];
    for (i = 0; i < 4; i++) v[i + 8] = _mm_set1_epi32((int)B3IV[i]);
    v[12] = lo; v[13] = hi; v[14] = _mm_set1_epi32(64);
    v[15] = _mm_set1_epi32((b == 0 ? B3_CHUNK_START : 0) | (b == B3_BLOCKS - 1 ? B3_CHUNK_END : 0));
    for (r = 0; r < 7; r++) {
      const uint8_t *q = B3SCHED[r];
      g4(v, 0, 4, 8, 12, m[q[0]], m[q[1]]);
      g4(v, 1, 5, 9, 13, m[q[2]], m[q[3]]);
      g4(v, 2, 6, 10, 14, m[q[4]], m[q[5]]);
      g4(v, 3, 7, 11, 15, m[q[6]], m[q[7]]);
      g4(v, 0, 5, 10, 15, m[q[8]], m[q[9]]);
      g4(v, 1, 6, 11, 12, m[q[10]], m[q[11]]);
      g4(v, 2, 7, 8, 13, m[q[12]], m[q[13]]);
      g4(v, 3, 4, 9, 14, m[q[14]], m[q[15]]);
    }
    for (i = 0; i < 8; i++) h[i] = _mm_xor_si128(v[i], v[i + 8]);
  }
  transpose4(&h[0], &h[1], &h[2], &h[3]);
  transpose4(&h[4], &h[5], &h[6], &h[7]);
  for (i = 0; i < 4; i++) {
    _mm_storeu_si128((__m128i *)(cv + 8 * i), h[i]);
    _mm_storeu_si128((__m128i *)(cv + 8 * i + 4), h[i + 4]);
  }
}
#endif

#ifdef B3_NEON
/* the same four-chunks-at-once as the SSE2 one: a vector's lane k is chunk k */
#define ROTN(x, c) vsriq_n_u32(vshlq_n_u32((x), 32 - (c)), (x), (c))
static inline uint32x4_t rot16n(uint32x4_t x) { return vreinterpretq_u32_u16(vrev32q_u16(vreinterpretq_u16_u32(x))); }
static inline void g4n(uint32x4_t *v, int a, int b, int c, int d, uint32x4_t x, uint32x4_t y) {
  v[a] = vaddq_u32(vaddq_u32(v[a], v[b]), x); v[d] = rot16n(veorq_u32(v[d], v[a]));
  v[c] = vaddq_u32(v[c], v[d]); v[b] = ROTN(veorq_u32(v[b], v[c]), 12);
  v[a] = vaddq_u32(vaddq_u32(v[a], v[b]), y); v[d] = ROTN(veorq_u32(v[d], v[a]), 8);
  v[c] = vaddq_u32(v[c], v[d]); v[b] = ROTN(veorq_u32(v[b], v[c]), 7);
}
static inline void transpose4n(uint32x4_t *a, uint32x4_t *b, uint32x4_t *c, uint32x4_t *d) {
  uint32x4_t t0 = vtrn1q_u32(*a, *b), t1 = vtrn2q_u32(*a, *b), t2 = vtrn1q_u32(*c, *d), t3 = vtrn2q_u32(*c, *d);
  *a = vreinterpretq_u32_u64(vtrn1q_u64(vreinterpretq_u64_u32(t0), vreinterpretq_u64_u32(t2)));
  *b = vreinterpretq_u32_u64(vtrn1q_u64(vreinterpretq_u64_u32(t1), vreinterpretq_u64_u32(t3)));
  *c = vreinterpretq_u32_u64(vtrn2q_u64(vreinterpretq_u64_u32(t0), vreinterpretq_u64_u32(t2)));
  *d = vreinterpretq_u32_u64(vtrn2q_u64(vreinterpretq_u64_u32(t1), vreinterpretq_u64_u32(t3)));
}
static inline uint32x4_t ld4n(const uint8_t *p) { return vreinterpretq_u32_u8(vld1q_u8(p)); }
/* four consecutive chunks, numbers counter .. counter + 3 */
static void b3chunk4(const uint8_t *in, uint64_t counter, uint32_t *cv) {
  uint32x4_t h[8], v[16], m[16];
  int i, b, r;
  uint32_t lw[4], hw[4];
  uint32x4_t lo, hi;
  for (i = 0; i < 4; i++) { lw[i] = (uint32_t)(counter + (uint64_t)i); hw[i] = (uint32_t)((counter + (uint64_t)i) >> 32); }
  lo = vld1q_u32(lw); hi = vld1q_u32(hw);
  for (i = 0; i < 8; i++) h[i] = vdupq_n_u32(B3IV[i]);
  for (b = 0; b < B3_BLOCKS; b++) {
    for (i = 0; i < 4; i++) {
      const uint8_t *p = in + 64 * b + 16 * i;
      m[4 * i] = ld4n(p);
      m[4 * i + 1] = ld4n(p + 1024);
      m[4 * i + 2] = ld4n(p + 2048);
      m[4 * i + 3] = ld4n(p + 3072);
      transpose4n(&m[4 * i], &m[4 * i + 1], &m[4 * i + 2], &m[4 * i + 3]);
    }
    for (i = 0; i < 8; i++) v[i] = h[i];
    for (i = 0; i < 4; i++) v[i + 8] = vdupq_n_u32(B3IV[i]);
    v[12] = lo; v[13] = hi; v[14] = vdupq_n_u32(64);
    v[15] = vdupq_n_u32((b == 0 ? B3_CHUNK_START : 0) | (b == B3_BLOCKS - 1 ? B3_CHUNK_END : 0));
    for (r = 0; r < 7; r++) {
      const uint8_t *q = B3SCHED[r];
      g4n(v, 0, 4, 8, 12, m[q[0]], m[q[1]]);
      g4n(v, 1, 5, 9, 13, m[q[2]], m[q[3]]);
      g4n(v, 2, 6, 10, 14, m[q[4]], m[q[5]]);
      g4n(v, 3, 7, 11, 15, m[q[6]], m[q[7]]);
      g4n(v, 0, 5, 10, 15, m[q[8]], m[q[9]]);
      g4n(v, 1, 6, 11, 12, m[q[10]], m[q[11]]);
      g4n(v, 2, 7, 8, 13, m[q[12]], m[q[13]]);
      g4n(v, 3, 4, 9, 14, m[q[14]], m[q[15]]);
    }
    for (i = 0; i < 8; i++) h[i] = veorq_u32(v[i], v[i + 8]);
  }
  transpose4n(&h[0], &h[1], &h[2], &h[3]);
  transpose4n(&h[4], &h[5], &h[6], &h[7]);
  for (i = 0; i < 4; i++) {
    vst1q_u32(cv + 8 * i, h[i]);
    vst1q_u32(cv + 8 * i + 4, h[i + 4]);
  }
}
#endif

/* n full chunks at in, the first numbered counter: their chaining values,
   8 words each, into cv */
void pblake3_chunks(const uint8_t *in, intptr_t n, uint64_t counter, uint32_t *cv) {
  intptr_t k = 0;
#if defined(B3_SSE2) || defined(B3_NEON)
  for (; k + 4 <= n; k += 4) b3chunk4(in + 1024 * k, counter + (uint64_t)k, cv + 8 * k);
#endif
  for (; k < n; k++) b3chunk(in + 1024 * k, counter + (uint64_t)k, cv + 8 * k);
}
