/* Many threads, each with its own state (and some one-shot calls), hashing different data at once through the plain C
   implementation: under ThreadSanitizer there must be no data race (the SIMD level is detected on first use; the C API
   promises that distinct states are independent).  cc -fsanitize=thread -g -O1 tests/tsan_threads.c -lpthread */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include "../src/pblake3.c"
#define NT 8
static uint8_t ref[NT][64];
static pthread_barrier_t gate;
static void *worker(void *arg) {
  long id = (long)arg, r, i; uint8_t *d = (uint8_t *)malloc(300000), out[64]; void *st = malloc((size_t)pblake3_state_size());
  for (i = 0; i < 300000; i++) d[i] = (uint8_t)(i * (id + 3));
  pthread_barrier_wait(&gate);   /* everybody into the first call at once: the SIMD level is detected right here */
  for (r = 0; r < 30; r++) {
    long p = 0, k = 1 + id * 997;
    pblake3_init(st);
    while (p < 300000) { long c = k; if (p + c > 300000) c = 300000 - p; pblake3_update(st, d + p, c); p += c; }
    pblake3_final_xof(st, out, 64);
    if (r == 0) memcpy(ref[id], out, 64);
    else if (memcmp(ref[id], out, 64)) { printf("thread %ld: result changed\n", id); exit(1); }
    pblake3_hash(d, 300000, out, 64);
    if (memcmp(ref[id], out, 64)) { printf("thread %ld: one pass differs from pieces\n", id); exit(1); }
    pblake3_keyed_hash(d, d + 1, 5000 + r, out, 32);
  }
  free(d); free(st); return 0;
}
int main(void) {
  pthread_t t[NT]; long i;
  pthread_barrier_init(&gate, 0, NT);
  for (i = 0; i < NT; i++) pthread_create(&t[i], 0, worker, (void *)i);   /* all of them first-call the SIMD detection together */
  for (i = 0; i < NT; i++) pthread_join(t[i], 0);
  printf("%d threads done, no mismatch\n", NT);
  return 0;
}
