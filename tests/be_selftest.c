/* The plain C implementation on a big-endian CPU with no libc at all (qemu-user: there is no cross libc to link
   against): freestanding, raw Linux syscalls, the official vectors of tests/official_hash.txt turned into a header
   by tests/be_vectors.py. Targets: powerpc64 (and s390x). Exit status 0 = every vector matched. */
#include "../src/pblake3.c"
#include "be_vectors.h"          /* generated into the build dir by tests/be_vectors.py: static const struct { const char *mode; long n; const char *hex; } VEC[]; VEC_N */

#if defined(__powerpc64__)
static long sys3(long n, long a, long b, long c) {
  register long r0 __asm__("r0") = n, r3 __asm__("r3") = a, r4 __asm__("r4") = b, r5 __asm__("r5") = c;
  __asm__ volatile("sc" : "+r"(r3) : "r"(r0), "r"(r4), "r"(r5) : "memory", "cr0", "r6", "r7", "r8", "r9", "r10", "r11", "r12", "ctr", "xer");
  return r3;
}
#define SYS_WRITE 4
#define SYS_EXIT 1
#elif defined(__s390x__)
static long sys3(long n, long a, long b, long c) {
  register long r1 __asm__("1") = n, r2 __asm__("2") = a, r3 __asm__("3") = b, r4 __asm__("4") = c;
  __asm__ volatile("svc 0" : "+r"(r2) : "r"(r1), "r"(r3), "r"(r4) : "memory");
  return r2;
}
#define SYS_WRITE 4
#define SYS_EXIT 1
#else
#error "a big-endian target with syscalls written here: powerpc64 or s390x"
#endif
static void out(const char *s) { long n = 0; while (s[n]) n++; sys3(SYS_WRITE, 1, (long)s, n); }
static void outnum(long v) { char b[24]; int i = 23; b[i] = 0; if (v == 0) b[--i] = '0'; while (v > 0) { b[--i] = (char)('0' + v % 10); v /= 10; } out(b + i); }
static int hexeq(const uint8_t *o, const char *hex) {
  static const char H[] = "0123456789abcdef"; int i;
  for (i = 0; i < 131; i++) if (hex[2 * i] != H[o[i] >> 4] || hex[2 * i + 1] != H[o[i] & 15]) return 0;
  return 1;
}
static uint8_t data[102400 + 8], res[131];
static uint64_t statebuf[(sizeof(b3state) + 7) / 8];
static int strcmp_(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return *a - *b; }
static long slen(const char *s) { long n = 0; while (s[n]) n++; return n; }
static const char KEY[] = "whats the Elvish word for friend";
static const char CTX[] = "BLAKE3 2019-12-27 16:29:52 test vectors context";
static void run(void) {
  static const int steps[] = {0, 1, 64, 1000, 1024, 3000};
  int v, cells = 0, fails = 0, s, i;
  void *st = statebuf;
  out("big-endian self test, SIMD level "); outnum(pblake3_chunks_level(-1)); out("\n");
  for (v = 0; v < VEC_N; v++) {
    long n = VEC[v].n, i2;
    const char *mode = VEC[v].mode;
    for (i2 = 0; i2 < n; i2++) data[i2] = (uint8_t)(i2 % 251);
    for (i = 0; i < 131; i++) res[i] = 0;
    if (!strcmp_(mode, "hash")) pblake3_hash(data, n, res, 131);
    else if (!strcmp_(mode, "keyed_hash")) pblake3_keyed_hash(KEY, data, n, res, 131);
    else pblake3_derive_key(CTX, slen(CTX), data, n, res, 131);
    cells++; if (!hexeq(res, VEC[v].hex)) { fails++; out("FAIL "); out(mode); out(" "); outnum(n); out("\n"); }
    for (s = 0; s < 6; s++) {
      long k = s ? steps[s] : (n ? n : 1), p = 0, c;
      if (!strcmp_(mode, "hash")) pblake3_init(st); else if (!strcmp_(mode, "keyed_hash")) pblake3_init_keyed(st, KEY, 32);
      else pblake3_init_derive_key(st, CTX, slen(CTX));
      while (p < n) { c = k; if (p + c > n) c = n - p; pblake3_update(st, data + p, c); p += c; }
      for (i = 0; i < 131; i++) res[i] = 0;
      pblake3_final_xof(st, res, 131);
      cells++; if (!hexeq(res, VEC[v].hex)) { fails++; out("FAIL pieces "); out(mode); out(" "); outnum(n); out(" step "); outnum(k); out("\n"); }
    }
  }
  outnum(cells); out(" cells, "); outnum(fails); out(" failures\n");
  sys3(SYS_EXIT, fails != 0, 0, 0);
}
void _start(void) { run(); for (;;) {} }
