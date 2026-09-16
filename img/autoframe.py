#!/usr/bin/env python3
"""Crop a rendered PCB image to the board, centred, using its alpha channel.

kicad-cli aims the camera at the board origin, not at the board's visual
centre, so a rotated or off-origin board sits off-centre in the frame and can
run off the sides. Predicting the right zoom from the board outline does not
fix that: it is a framing problem, not a size problem, and the outline does not
account for perspective, component height, or where the origin happens to be.

Measuring the render instead settles all of it at once. On a transparent
background every pixel the board covers has alpha above zero, so the board's
screen-space bounding box is exactly the non-transparent extent. Cropping to
that box centres the board by construction and trims the dead margin with it.

This deliberately does not scale. Resampling without an imaging library means
writing a resampler, and a tight crop of a transparent PNG is what a consumer
wants anyway -- it scales the image itself. The output is therefore the board
plus the requested margin, not the originally requested width and height.

Stdlib only: the KiCad base image has no Pillow, and adding one for a crop is
not worth an apt layer. Only 8-bit RGBA non-interlaced PNGs are handled, which
is what kicad-cli emits with a transparent background; anything else warns and
is left untouched, because a missing crop is a cosmetic problem and a corrupted
release asset is not.

Usage:
  autoframe.py IMAGE.png [--margin 0.04] [--min-alpha 8]
"""
import argparse
import struct
import sys
import zlib

PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def warn(msg):
    print(f"::warning::{msg}", file=sys.stderr)


def read_chunks(data):
    """Yield (type, payload) for each PNG chunk."""
    pos = len(PNG_MAGIC)
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        yield ctype, payload
        pos += 12 + length  # length + type + payload + crc


def chunk(ctype, payload):
    return (struct.pack(">I", len(payload)) + ctype + payload
            + struct.pack(">I", zlib.crc32(ctype + payload) & 0xFFFFFFFF))


def unfilter(raw, width, height, bpp):
    """Undo PNG per-scanline filtering. Returns a list of bytearrays."""
    stride = width * bpp
    rows = []
    prev = bytearray(stride)
    pos = 0
    for _ in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos:pos + stride])
        pos += stride
        if ftype == 1:      # Sub
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif ftype == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:    # Average
            for i in range(stride):
                left = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:    # Paeth
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                b = prev[i]
                c = prev[i - bpp] if i >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError(f"unknown PNG filter type {ftype}")
        rows.append(line)
        prev = line
    return rows


def alpha_bbox(rows, width, bpp, min_alpha):
    """Bounding box of pixels whose alpha exceeds min_alpha."""
    left, right = width, -1
    top, bottom = None, None
    for y, row in enumerate(rows):
        row_left, row_right = None, None
        for x in range(width):
            if row[x * bpp + 3] > min_alpha:
                if row_left is None:
                    row_left = x
                row_right = x
        if row_left is None:
            continue
        if top is None:
            top = y
        bottom = y
        left = min(left, row_left)
        right = max(right, row_right)
    if top is None:
        return None
    return left, top, right, bottom


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--margin", type=float, default=0.04,
                    help="Transparent border to keep, as a fraction of the "
                         "cropped size. Default 0.04.")
    ap.add_argument("--min-alpha", type=int, default=8,
                    help="Alpha above which a pixel counts as board. Default 8, "
                         "which ignores the faint fringe antialiasing leaves.")
    opts = ap.parse_args()

    data = open(opts.image, "rb").read()
    if not data.startswith(PNG_MAGIC):
        warn(f"{opts.image} is not a PNG; leaving it alone.")
        return 0

    idat = bytearray()
    ihdr = None
    for ctype, payload in read_chunks(data):
        if ctype == b"IHDR":
            ihdr = payload
        elif ctype == b"IDAT":
            idat += payload
        elif ctype == b"IEND":
            break

    if ihdr is None:
        warn(f"{opts.image} has no IHDR; leaving it alone.")
        return 0

    width, height, depth, colour, _comp, _filt, interlace = struct.unpack(">IIBBBBB", ihdr)
    if (depth, colour, interlace) != (8, 6, 0):
        warn(f"{opts.image} is not an 8-bit RGBA non-interlaced PNG "
             f"(depth={depth}, colour type={colour}, interlace={interlace}); "
             "leaving it alone. Autoframing needs an alpha channel, so render "
             "with pcb_output_image_background set to 'transparent'.")
        return 0

    bpp = 4
    rows = unfilter(zlib.decompress(bytes(idat)), width, height, bpp)
    box = alpha_bbox(rows, width, bpp, opts.min_alpha)
    if box is None:
        warn(f"{opts.image} is fully transparent; leaving it alone.")
        return 0

    left, top, right, bottom = box
    cw, ch = right - left + 1, bottom - top + 1
    if cw == width and ch == height:
        print(f"==> {opts.image}: board already fills the frame, nothing to crop")
        return 0

    pad = int(round(max(cw, ch) * max(0.0, opts.margin)))
    out_w, out_h = cw + 2 * pad, ch + 2 * pad

    # The margin is added by composing onto a transparent canvas rather than by
    # widening the crop, so that a board touching the frame edge still comes out
    # centred. Clamping the crop to the source instead would give it a margin on
    # one side and none on the other, which is the very thing being fixed.
    blank = bytes(out_w * bpp)
    raw = bytearray()
    for oy in range(out_h):
        raw.append(0)  # filter type 0; a crop is not worth re-filtering for
        sy = top - pad + oy
        if sy < 0 or sy >= height:
            raw += blank
            continue
        row = rows[sy]
        line = bytearray(blank)
        # Overlap of the output span [left-pad, left-pad+out_w) with [0, width)
        src_lo = max(0, left - pad)
        src_hi = min(width, left - pad + out_w)
        if src_lo < src_hi:
            dst = src_lo - (left - pad)
            line[dst * bpp:(dst + src_hi - src_lo) * bpp] = row[src_lo * bpp:src_hi * bpp]
        raw += line
    cw, ch = out_w, out_h

    new_ihdr = struct.pack(">IIBBBBB", cw, ch, 8, 6, 0, 0, 0)
    out = bytearray(PNG_MAGIC)
    out += chunk(b"IHDR", new_ihdr)
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += chunk(b"IEND", b"")
    open(opts.image, "wb").write(bytes(out))

    print(f"==> {opts.image}: cropped {width}x{height} -> {cw}x{ch} "
          f"(board centred, {opts.margin:.0%} margin)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
