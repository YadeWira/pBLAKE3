/* pBLAKE3 in plain C: the whole of BLAKE3 (hash, keyed hash, derive_key, any output length, incremental) behind the
   C API of include/pblake3.h, with no FreePascal and no libc (no allocation, no library call). The chunk work goes
   through the SIMD routines of b3chunks.c (SSE2, AVX2, AVX-512, NEON, chosen at run time), which this file includes.
   For C projects (7-Zip plugins and the like) that cannot load the Pascal library; same output, same functions.
   Build it as a static or shared library by itself:  cc -O2 -c src/pblake3.c  */
#include "b3chunks.c"

#if defined(_WIN32) && defined(PBLAKE3_BUILD_DLL)
#define PB_EXPORT __declspec(dllexport)
#else
#define PB_EXPORT
#endif
enum { F_CHUNK_START = 1, F_CHUNK_END = 2, F_PARENT = 4, F_ROOT = 8, F_KEYED_HASH = 16, F_DERIVE_CTX = 32, F_DERIVE_MAT = 64 };

/* the compression function: 16 output words (the last 8 are what a chaining value is made of, the first 8 xor-ed) */
static void b3compress(const uint32_t cv[8], const uint8_t block[64], uint32_t block_len, uint64_t counter, uint32_t flags,
                       uint32_t out[16]) {
  uint32_t m[16], s[16];
  int i, r;
  for (i = 0; i < 16; i++) m[i] = b3load(block + 4 * i);
  for (i = 0; i < 8; i++) s[i] = cv[i];
  s[8] = B3IV[0]; s[9] = B3IV[1]; s[10] = B3IV[2]; s[11] = B3IV[3];
  s[12] = (uint32_t)counter; s[13] = (uint32_t)(counter >> 32); s[14] = block_len; s[15] = flags;
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
  for (i = 0; i < 8; i++) { out[i] = s[i] ^ s[i + 8]; out[i + 8] = s[i + 8] ^ cv[i]; }
}

typedef struct {
  uint32_t key[8];                 /* the starting chaining value: the IV, the key's words, or the context's hash */
  uint32_t cv[8];                  /* the current chunk's chaining value so far */
  uint64_t chunk;                  /* the number of the current chunk */
  uint8_t buf[64];
  uint32_t buf_len, blocks_done;   /* bytes waiting in buf; blocks of the chunk already compressed */
  uint32_t flags;                  /* 0, F_KEYED_HASH, F_DERIVE_MAT (or F_DERIVE_CTX while hashing the context) */
  uint32_t stack_len;
  uint32_t stack[54][8];           /* 2^54 chunks are 2^64 bytes */
} b3state;

static void st_reset_chunk(b3state *h) {
  int i;
  for (i = 0; i < 8; i++) h->cv[i] = h->key[i];
  for (i = 0; i < 64; i++) h->buf[i] = 0;
  h->buf_len = 0; h->blocks_done = 0;
}
static void st_start(b3state *h, const uint32_t key[8], uint32_t flags) {
  int i;
  for (i = 0; i < 8; i++) h->key[i] = key[i];
  h->chunk = 0; h->flags = flags; h->stack_len = 0;
  st_reset_chunk(h);
}
static uint32_t chunk_len(const b3state *h) { return h->blocks_done * 64 + h->buf_len; }

/* a finished chunk's (or subtree's) chaining value into the tree, merging every pair that is now complete */
static void push_cv(b3state *h, const uint32_t cv_in[8], uint64_t total_chunks) {
  uint32_t cv[8], blk[16], o[16];
  uint8_t pb[64];
  int i;
  for (i = 0; i < 8; i++) cv[i] = cv_in[i];
  while ((total_chunks & 1) == 0) {
    const uint32_t *left = h->stack[--h->stack_len];
    for (i = 0; i < 8; i++) { blk[i] = left[i]; blk[8 + i] = cv[i]; }
    for (i = 0; i < 16; i++) { pb[4 * i] = (uint8_t)blk[i]; pb[4 * i + 1] = (uint8_t)(blk[i] >> 8); pb[4 * i + 2] = (uint8_t)(blk[i] >> 16); pb[4 * i + 3] = (uint8_t)(blk[i] >> 24); }
    b3compress(h->key, pb, 64, 0, F_PARENT | h->flags, o);
    for (i = 0; i < 8; i++) cv[i] = o[i];
    total_chunks >>= 1;
  }
  for (i = 0; i < 8; i++) h->stack[h->stack_len][i] = cv[i];
  h->stack_len++;
}

/* the current chunk is full and more input follows: close it */
static void finish_chunk(b3state *h) {
  uint32_t o[16];
  b3compress(h->cv, h->buf, h->buf_len, h->chunk, h->flags | F_CHUNK_END | (h->blocks_done == 0 ? F_CHUNK_START : 0), o);
  h->chunk++;
  push_cv(h, o, h->chunk);
  st_reset_chunk(h);
}

static void st_update(b3state *h, const uint8_t *in, intptr_t len) {
  while (len > 0) {
    if (chunk_len(h) == 1024) finish_chunk(h);       /* more input is here, so that chunk is not the last */
    if (h->buf_len == 0 && h->blocks_done == 0 && len > 1024) {
      /* at a chunk's start with more than a chunk to come: whole chunks through the SIMD routine, all but the last */
      uint32_t cvs[32][8];
      intptr_t k = (len - 1) / 1024, j;
      if (k > 32) k = 32;
      pblake3_chunks_kf(in, k, h->chunk, h->key, h->flags, &cvs[0][0]);
      for (j = 0; j < k; j++) { h->chunk++; push_cv(h, cvs[j], h->chunk); }
      in += k * 1024; len -= k * 1024;
      continue;
    }
    if (h->buf_len == 64) {                            /* a full block is only compressed when more input follows */
      uint32_t o[16];
      int i;
      b3compress(h->cv, h->buf, 64, h->chunk, h->flags | (h->blocks_done == 0 ? F_CHUNK_START : 0), o);
      for (i = 0; i < 8; i++) h->cv[i] = o[i];
      h->blocks_done++;
      for (i = 0; i < 64; i++) h->buf[i] = 0;
      h->buf_len = 0;
    }
    {
      uint32_t take = 64 - h->buf_len, i;
      if ((intptr_t)take > len) take = (uint32_t)len;
      for (i = 0; i < take; i++) h->buf[h->buf_len + i] = in[i];
      h->buf_len += take; in += take; len -= take;
    }
  }
}

/* any number of output bytes; the state is not changed */
static void st_final(const b3state *h, uint8_t *out, intptr_t outlen) {
  uint32_t cv[8], block_cv[8], o[16];
  uint8_t blk[64];
  uint32_t blen, flags, remaining;
  uint64_t counter, ob = 0;
  int i;
  /* the root node: the last chunk's last block, unless there are parents */
  for (i = 0; i < 8; i++) cv[i] = h->cv[i];
  for (i = 0; i < 64; i++) blk[i] = h->buf[i];
  blen = h->buf_len; counter = h->chunk;
  flags = h->flags | F_CHUNK_END | (h->blocks_done == 0 ? F_CHUNK_START : 0);
  remaining = h->stack_len;
  while (remaining > 0) {
    uint32_t pw[16];
    /* this node's chaining value becomes the right child of the stack's top */
    b3compress(cv, blk, blen, counter, flags, o);
    for (i = 0; i < 8; i++) block_cv[i] = o[i];
    remaining--;
    for (i = 0; i < 8; i++) { pw[i] = h->stack[remaining][i]; pw[8 + i] = block_cv[i]; }
    for (i = 0; i < 16; i++) { blk[4 * i] = (uint8_t)pw[i]; blk[4 * i + 1] = (uint8_t)(pw[i] >> 8); blk[4 * i + 2] = (uint8_t)(pw[i] >> 16); blk[4 * i + 3] = (uint8_t)(pw[i] >> 24); }
    for (i = 0; i < 8; i++) cv[i] = h->key[i];
    blen = 64; counter = 0; flags = F_PARENT | h->flags;
  }
  while (outlen > 0) {
    intptr_t n = outlen < 64 ? outlen : 64, j;
    b3compress(cv, blk, blen, ob, flags | F_ROOT, o);
    for (j = 0; j < n; j++) out[j] = (uint8_t)(o[j / 4] >> (8 * (j % 4)));
    out += n; outlen -= n; ob++;
  }
}

static void key_words(uint32_t w[8], const uint8_t *k) { int i; for (i = 0; i < 8; i++) w[i] = b3load(k + 4 * i); }

static void st_init_derive(b3state *h, const uint8_t *ctx, intptr_t ctxlen) {
  b3state c;
  uint8_t kb[32];
  uint32_t kw[8];
  st_start(&c, B3IV, F_DERIVE_CTX);
  st_update(&c, ctx, ctxlen);
  st_final(&c, kb, 32);
  key_words(kw, kb);
  st_start(h, kw, F_DERIVE_MAT);
}

/* ---- the C API (include/pblake3.h) ---- */
PB_EXPORT int pblake3_version(void) { return 2; }
PB_EXPORT int pblake3_uses_c(void) { return 1; }
PB_EXPORT intptr_t pblake3_state_size(void) { return (intptr_t)sizeof(b3state); }

PB_EXPORT int pblake3_init(void *st) { if (!st) return -1; st_start((b3state *)st, B3IV, 0); return 0; }
PB_EXPORT int pblake3_init_keyed(void *st, const void *key, intptr_t keyLen) {
  uint32_t kw[8];
  if (!st || !key || keyLen != 32) return -1;
  key_words(kw, (const uint8_t *)key); st_start((b3state *)st, kw, F_KEYED_HASH); return 0;
}
PB_EXPORT int pblake3_init_derive_key(void *st, const void *ctx, intptr_t ctxLen) {
  if (!st || ctxLen < 0 || (!ctx && ctxLen > 0)) return -1;
  st_init_derive((b3state *)st, (const uint8_t *)ctx, ctxLen); return 0;
}
PB_EXPORT int pblake3_update(void *st, const void *data, intptr_t len) {
  if (!st || len < 0 || (!data && len > 0)) return -1;
  if (len > 0) st_update((b3state *)st, (const uint8_t *)data, len);
  return 0;
}
PB_EXPORT int pblake3_final_xof(void *st, uint8_t *out, intptr_t outLen) {
  if (!st || outLen < 0 || (!out && outLen > 0)) return -1;
  if (outLen > 0) st_final((const b3state *)st, out, outLen);
  return 0;
}
PB_EXPORT int pblake3_final(void *st, uint8_t out[16]) { if (!st || !out) return -1; return pblake3_final_xof(st, out, 16); }

PB_EXPORT int pblake3_hash(const void *data, intptr_t len, uint8_t *out, intptr_t outLen) {
  b3state s;
  if (len < 0 || (!data && len > 0)) return -1;
  st_start(&s, B3IV, 0);
  if (len > 0) st_update(&s, (const uint8_t *)data, len);
  return pblake3_final_xof(&s, out, outLen);
}
PB_EXPORT int pblake3_128(const void *data, intptr_t len, uint8_t out[16]) { if (!out) return -1; return pblake3_hash(data, len, out, 16); }
PB_EXPORT int pblake3_keyed_hash(const void *key32, const void *data, intptr_t len, uint8_t *out, intptr_t outLen) {
  b3state s;
  uint32_t kw[8];
  if (len < 0 || (!data && len > 0) || !key32) return -1;
  key_words(kw, (const uint8_t *)key32); st_start(&s, kw, F_KEYED_HASH);
  if (len > 0) st_update(&s, (const uint8_t *)data, len);
  return pblake3_final_xof(&s, out, outLen);
}
PB_EXPORT int pblake3_derive_key(const void *ctx, intptr_t ctxLen, const void *material, intptr_t matLen, uint8_t *out, intptr_t outLen) {
  b3state s;
  if (ctxLen < 0 || (!ctx && ctxLen > 0) || matLen < 0 || (!material && matLen > 0)) return -1;
  st_init_derive(&s, (const uint8_t *)ctx, ctxLen);
  if (matLen > 0) st_update(&s, (const uint8_t *)material, matLen);
  return pblake3_final_xof(&s, out, outLen);
}
