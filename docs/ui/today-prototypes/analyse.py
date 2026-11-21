#!/usr/bin/env python3
"""Measure the prototype screenshots from real pixels.

Reports, per image: background colour, ink coverage overall and per horizontal
band (so I can see where content actually sits), the vertical rhythm of
non-background rows (rule lines and text baselines), and the contrast ratio
between the dominant ink colour and the background.

This is evidence extraction, not aesthetic judgement -- it exists because the
agent cannot see the images directly.
"""
import struct, zlib, sys, os
from collections import Counter


def read_png(path):
    with open(path, "rb") as f:
        data = f.read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos = 8
    width = height = None
    idat = b""
    bitdepth = colortype = None
    while pos < len(data):
        ln = struct.unpack(">I", data[pos:pos + 4])[0]
        typ = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + ln]
        if typ == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", chunk[:10])
        elif typ == b"IDAT":
            idat += chunk
        elif typ == b"IEND":
            break
        pos += 12 + ln
    raw = zlib.decompress(idat)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colortype]
    assert bitdepth == 8, (path, bitdepth, colortype)
    stride = width * channels
    out = bytearray(width * height * channels)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        ft = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        if ft == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ft == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ft == 3:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif ft == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return width, height, channels, bytes(out)


def rel_lum(rgb):
    def f(c):
        c /= 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (f(v) for v in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = rel_lum(a), rel_lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def analyse(path):
    w, h, ch, px = read_png(path)
    def at(x, y):
        o = (y * w + x) * ch
        return (px[o], px[o + 1], px[o + 2])
    # background = most common colour on the left/right margins (pure screen bg)
    margin = Counter()
    for y in range(60, h - 20, 7):
        for x in list(range(4, 24)) + list(range(w - 24, w - 4)):
            margin[at(x, y)] += 1
    bg = margin.most_common(1)[0][0]
    # ink = colours far from background
    ink_hist = Counter()
    row_ink = []
    for y in range(h):
        c = 0
        for x in range(0, w, 3):
            p = at(x, y)
            if max(abs(p[i] - bg[i]) for i in range(3)) > 28:
                c += 1
                ink_hist[p] += 1
        row_ink.append(c)
    total_ink = sum(row_ink)
    # The most common "ink" colour is the antialias halo, not the text core.
    # Real text sits at the far end of the luminance distribution away from the
    # background, so take the extreme that is furthest from bg.
    ink = ink_hist.most_common(1)[0][0] if ink_hist else (0, 0, 0)
    bg_is_dark = sum(bg) / 3 < 128
    cands = [c for c, n in ink_hist.items() if n >= 20]
    cands.sort(key=lambda c: sum(c), reverse=bg_is_dark)
    core = cands[0] if cands else ink
    # band coverage (10 bands)
    bands = []
    for i in range(10):
        lo, hi = h * i // 10, h * (i + 1) // 10
        bands.append(sum(row_ink[lo:hi]) / max(1, (hi - lo) * ((w + 2) // 3)))
    # content extent: first/last row with meaningful ink
    thr = 2
    first = next((y for y, c in enumerate(row_ink) if c > thr), None)
    last = next((y for y in range(h - 1, -1, -1) if row_ink[y] > thr), None)
    # horizontal rule detection: rows that are nearly full-width ink and thin
    rules = 0
    run = 0
    fullish = w // 3 * 0.75
    for c in row_ink[:2700]:
        if c > fullish:
            run += 1
        else:
            if 0 < run <= 4:
                rules += 1
            run = 0
    print(f"\n=== {os.path.basename(path)}  {w}x{h} ch={ch}")
    print(f"  bg {bg}   halo {ink}   text core {core}   core contrast {contrast(core, bg):.2f}:1")
    lums = sorted((sum(c) // 3, n) for c, n in ink_hist.items() if n >= 300)
    top = sorted(ink_hist.items(), key=lambda kv: -kv[1])[:8]
    print("  ink palette (>=300px): " + ", ".join(
        f"{sum(c)//3}:{n}" for c, n in sorted(ink_hist.items(), key=lambda kv: sum(kv[0])) if n >= 300))
    print("  top colours: " + ", ".join(f"{c}x{n}" for c, n in top))
    sat = [(c, n) for c, n in ink_hist.items() if n >= 100 and max(c) - min(c) >= 24]
    print(f"  chromatic pixels: {sum(n for _, n in sat)} ({len(sat)} colours)"
          + ("  e.g. " + ", ".join(f"{c}x{n}" for c, n in sorted(sat, key=lambda kv: -kv[1])[:4]) if sat else ""))
    print(f"  ink px {total_ink}  ({100*total_ink/(h*((w+2)//3)):.1f}% of sampled)")
    print(f"  content rows {first}..{last} of {h}  ({'FULL' if last and last>h-30 else 'stops early'})")
    print(f"  thin full-width rules: {rules}")
    print("  band coverage %: " + " ".join(f"{b*100:4.1f}" for b in bands))
    return dict(path=path, bg=bg, ink=ink, core=core,
                contrast=contrast(core, bg),
                first=first, last=last, rules=rules, bands=bands,
                coverage=total_ink / (h * ((w + 2) // 3)))


if __name__ == "__main__":
    for p in sorted(sys.argv[1:]):
        analyse(p)
