#!/usr/bin/env python3
"""
make_test_bmps.py - builds the Step 1 test images in ../tests and checks them
against a Python re-implementation of Bmp_Parse / Pix_Index (same order of
checks as engine/bmp.asm). Run:  python make_test_bmps.py

Pixel pattern: colour byte number n holds (n mod 256); padding bytes hold 0xEE
(238). So in the CLI, "Byte value" for Pix_Index(n) must equal n mod 256.
"""
import os, struct

MAX_BMP = 8 * 1024 * 1024
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests")

def make_bmp(w, h, bpp=24, comp=0, topdown=False, truncate=0,
             magic=b"BM", dib=40, pixel_fill=True):
    ah = abs(h)
    row_bytes = w * 3
    stride = (row_bytes + 3) & ~3
    pix = bytearray()
    n = 0
    for _ in range(ah):
        pix += bytes((n + i) & 0xFF for i in range(row_bytes))
        n += row_bytes
        pix += b"\xEE" * (stride - row_bytes)
    if truncate:
        pix = pix[:-truncate]
    total = 54 + len(pix)
    hdr = magic + struct.pack("<IHHI", total, 0, 0, 54)
    hdr += struct.pack("<IiiHHIIiiII", dib, w, -ah if topdown else h,
                       1, bpp, comp, len(pix), 2835, 2835, 0, 0)
    return bytes(hdr + pix)

# ---- reference implementation of the assembly (same check order) -----------
def ref_parse(data):
    if len(data) > MAX_BMP:
        return 6, None
    size = len(data)
    if size < 2 or data[0:2] != b"BM": return 2, None
    if size < 54: return 5, None
    off, = struct.unpack_from("<I", data, 10)
    if off < 54: return 5, None
    dibsz, = struct.unpack_from("<I", data, 14)
    if dibsz < 40: return 5, None
    bpp, = struct.unpack_from("<H", data, 28)
    if bpp != 24: return 3, None
    comp, = struct.unpack_from("<I", data, 30)
    if comp != 0: return 4, None
    w, h = struct.unpack_from("<ii", data, 18)
    if w <= 0 or h == 0 or h == -2**31: return 5, None
    h = abs(h)
    row = w * 3
    stride = (row + 3) & ~3
    if off + stride * h > size: return 5, None
    return 0, dict(off=off, w=w, h=h, row=row, stride=stride, colour=row * h)

def ref_pix_index(info, n):
    if n >= info["colour"]: return None
    r, c = divmod(n, info["row"])
    return info["off"] + r * info["stride"] + c

# ---- test set ---------------------------------------------------------------
tests = [
    # name,                 bytes,                                   expected code
    ("ok_4x4.bmp",          make_bmp(4, 4),                          0),
    ("ok_5x3_padded.bmp",   make_bmp(5, 3),                          0),
    ("ok_7x2_padded.bmp",   make_bmp(7, 2),                          0),
    ("ok_1x1.bmp",          make_bmp(1, 1),                          0),
    ("ok_topdown_5x3.bmp",  make_bmp(5, 3, topdown=True),            0),
    ("bad_notbm.bmp",       b"PK" + make_bmp(4, 4)[2:],              2),
    ("bad_empty.bmp",       b"",                                     2),
    ("bad_tiny.bmp",        b"BM" + bytes(10),                       5),
    ("bad_8bit.bmp",        make_bmp(4, 4, bpp=8),                   3),
    ("bad_32bit.bmp",       make_bmp(4, 4, bpp=32),                  3),
    ("bad_compressed.bmp",  make_bmp(4, 4, comp=1),                  4),
    ("bad_truncated.bmp",   make_bmp(5, 3, truncate=10),             5),
    ("bad_zero_width.bmp",  make_bmp(0, 3),                          5),
    ("bad_toobig.bmp",      make_bmp(2000, 1500),                    6),
]

os.makedirs(OUT, exist_ok=True)
print(f"{'file':24} {'expected':>8} {'reference':>9}")
ok = True
for name, data, expect in tests:
    with open(os.path.join(OUT, name), "wb") as f:
        f.write(data)
    code, info = ref_parse(data)
    flag = "" if code == expect else "   <-- MISMATCH"
    ok &= (code == expect)
    print(f"{name:24} {expect:8} {code:9}{flag}")

# Pix_Index expectations for the padded 5x3 image
_, info = ref_parse(make_bmp(5, 3))
print("\nPix_Index on ok_5x3_padded.bmp (rowBytes=15, stride=16, dataOffset=54):")
for n in (0, 14, 15, 29, 30, 44, 45):
    idx = ref_pix_index(info, n)
    print(f"  n={n:3}  expected offset = {idx if idx is not None else 'INVALID'}"
          + ("" if idx is None else f"   expected byte value = {n & 0xFF}"))
print("\nALL REFERENCE CHECKS PASSED" if ok else "\nSOME CHECKS FAILED")
