#!/usr/bin/env bash
# Regenerate fixtures/: the small images the tests decode. The outputs are committed, so the
# tests need neither this script nor ImageMagick; run it only to change a fixture.
# Needs python3 and ImageMagick (`convert`).
set -euo pipefail

cd "$(dirname "$0")/.."
out=fixtures
mkdir -p "$out"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

python3 - "$out" <<'PY'
import struct, sys, zlib

out = sys.argv[1]

def chunk(t, d):
    c = struct.pack(">I", len(d)) + t + d
    return c + struct.pack(">I", zlib.crc32(t + d))

def png(w, h, rows, extra=b"", color=2):
    raw = b"".join(b"\0" + r for r in rows)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, color, 0, 0, 0))
            + extra + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

px = [[(255, 0, 0), (0, 255, 0), (0, 0, 255)], [(255, 255, 0), (0, 255, 255), (255, 0, 255)]]
rows = [b"".join(bytes(p) for p in r) for r in px]
good = png(3, 2, rows)
open(f"{out}/px.png", "wb").write(good)

# The same pixels with text chunks, for the metadata test.
text = chunk(b"tEXt", b"Author\0Hyperquader") + chunk(b"tEXt", b"Title\0six pixels")
open(f"{out}/meta.png", "wb").write(png(3, 2, rows, text))

# Hostile inputs: cut off mid-stream, a valid header over damaged data, a header that claims
# 65535 x 65535 pixels (12 GiB as RGB8) with a few bytes of data, and bytes no loader knows.
open(f"{out}/truncated.png", "wb").write(good[: len(good) - 30])
bad = bytearray(good)
for i in range(len(bad) - 40, len(bad) - 20):
    bad[i] ^= 0xFF
open(f"{out}/damaged.png", "wb").write(bytes(bad))
huge = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 65535, 65535, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(b"\0" * 64)) + chunk(b"IEND", b""))
open(f"{out}/huge.png", "wb").write(huge)
open(f"{out}/unknown.bin", "wb").write(bytes((i * 37 + 11) & 0xFF for i in range(256)))
open(f"{out}/empty.png", "wb").write(b"")
PY

# JPEG, 24x8: left half red, right half blue, no chroma subsampling so the halves stay clean.
convert -size 12x8 xc:'#ff0000' -size 12x8 xc:'#0000ff' +append -quality 100 -sampling-factor 1x1 "$out/halves.jpg"
head -c 200 "$out/halves.jpg" > "$out/truncated.jpg"
# The same JPEG with an EXIF APP1 segment holding Orientation = 6 (rotate 90 degrees
# clockwise to display), spliced in right after SOI.
python3 - "$out/halves.jpg" "$out/orient6.jpg" <<'PY'
import struct, sys
src = open(sys.argv[1], "rb").read()
assert src[:2] == b"\xff\xd8"
tiff = b"II*\x00" + struct.pack("<I", 8) + struct.pack("<H", 1) + struct.pack("<HHIHH", 0x0112, 3, 1, 6, 0) + struct.pack("<I", 0)
body = b"Exif\x00\x00" + tiff
open(sys.argv[2], "wb").write(src[:2] + b"\xff\xe1" + struct.pack(">H", len(body) + 2) + body + src[2:])
PY
# Animated GIF: three frames of delays 70, 30 and 120 ms.
convert -delay 7 -size 4x4 xc:red -delay 3 -size 4x4 xc:green -delay 12 -size 4x4 xc:blue -loop 0 "$out/anim.gif"

cat > "$out/box.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="8" height="4"><rect width="8" height="4" fill="#336699"/></svg>
SVG
