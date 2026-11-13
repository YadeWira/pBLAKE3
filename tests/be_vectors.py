#!/usr/bin/env python3
"""tests/official_hash.txt -> tests/be_vectors.h, for tests/be_selftest.c.   usage: be_vectors.py <in> <out>"""
import sys
rows = [l.split() for l in open(sys.argv[1]) if l.strip() and not l.startswith('#')]
with open(sys.argv[2], 'w') as f:
    f.write('static const struct { const char *mode; long n; const char *hex; } VEC[] = {\n')
    for m, n, h in rows: f.write('  {"%s", %s, "%s"},\n' % (m, n, h))
    f.write('};\n#define VEC_N (sizeof(VEC) / sizeof(VEC[0]))\n')
