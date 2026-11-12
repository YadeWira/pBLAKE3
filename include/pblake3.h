/* pBLAKE3: C API (BLAKE3 hash, keyed hash, derive_key, any output length).
   One implementation (the Pascal unit pjablake3), exported by the shared
   library pblake3 (pblake3.dll, libpblake3.so, libpblake3.dylib).

   - The output is the official BLAKE3's, always (the first 16 bytes are BLAKE3-128).
   - Every function returns 0 on success and -1 on a bad argument (NULL with
     a length > 0, a negative length, a key that is not 32 bytes). No
     Pascal exception crosses this interface.
   - The caller owns all memory. A state is pblake3_state_size() bytes (aligned
     as malloc's); the library allocates nothing.
   - pblake3_final / pblake3_final_xof do not consume the state: they can be
     called again, or more data can follow with pblake3_update.
   - Thread safety: distinct states are independent; one state is not shared. */
#ifndef PBLAKE3_H
#define PBLAKE3_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
#ifdef _WIN32
#define PBLAKE3_CALL __cdecl
#else
#define PBLAKE3_CALL
#endif

#define PBLAKE3_API_VERSION 2
#define PBLAKE3_KEY_LEN 32
#define PBLAKE3_OUT_LEN 32           /* the usual output; the 128-bit one is its first 16 bytes */

int    PBLAKE3_CALL pblake3_version(void);               /* PBLAKE3_API_VERSION */
int    PBLAKE3_CALL pblake3_uses_c(void);                /* 1 if the SSE2 chunk routine is installed */
intptr_t PBLAKE3_CALL pblake3_state_size(void);

/* incremental */
int    PBLAKE3_CALL pblake3_init(void *st);
int    PBLAKE3_CALL pblake3_init_keyed(void *st, const void *key, intptr_t keyLen);        /* keyLen = 32 */
int    PBLAKE3_CALL pblake3_init_derive_key(void *st, const void *ctx, intptr_t ctxLen);   /* then update with the key material */
int    PBLAKE3_CALL pblake3_update(void *st, const void *data, intptr_t len);
int    PBLAKE3_CALL pblake3_final(void *st, uint8_t out[16]);                              /* BLAKE3-128 */
int    PBLAKE3_CALL pblake3_final_xof(void *st, uint8_t *out, intptr_t outLen);            /* any length */

/* one pass */
int    PBLAKE3_CALL pblake3_128(const void *data, intptr_t len, uint8_t out[16]);
int    PBLAKE3_CALL pblake3_hash(const void *data, intptr_t len, uint8_t *out, intptr_t outLen);
int    PBLAKE3_CALL pblake3_keyed_hash(const void *key32, const void *data, intptr_t len, uint8_t *out, intptr_t outLen);
int    PBLAKE3_CALL pblake3_derive_key(const void *ctx, intptr_t ctxLen, const void *material, intptr_t matLen,
                                       uint8_t *out, intptr_t outLen);

#ifdef __cplusplus
}
#endif
#endif
