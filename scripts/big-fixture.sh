#!/usr/bin/env bash
# Write build/big.png: a valid 65535 x 65535 16-bit grey PNG of zeros, 8.6 GB once decoded,
# about 37 MB on disk. glycin refuses any frame over 8 GB; make test-big decodes this one.
#   scripts/big-fixture.sh [out]
set -euo pipefail

out=${1:-"$(dirname "$0")/../build/big.png"}
mkdir -p "$(dirname "$out")"
python3 - "$out" <<'PY'
import struct, sys, zlib

W = H = 65535
row = b"\0" + b"\0" * (W * 2)

def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d))

with open(sys.argv[1], "wb") as f:
    f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 16, 0, 0, 0, 0)))
    z = zlib.compressobj(1)
    block = row * 256
    left = H
    buf = b""
    while left:
        n = min(left, 256)
        buf += z.compress(block if n == 256 else row * n)
        left -= n
        if len(buf) > (1 << 20):
            f.write(chunk(b"IDAT", buf))
            buf = b""
    buf += z.flush()
    if buf:
        f.write(chunk(b"IDAT", buf))
    f.write(chunk(b"IEND", b""))
PY
