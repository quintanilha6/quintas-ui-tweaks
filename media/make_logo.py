"""Draws media/logo.png (400x400): three settings sliders on a dark tile.
Pure Python (no Pillow): 3x3 supersampling for smooth edges."""
import math, struct, zlib, os

SIZE, SS = 400, 3
BG_TOP, BG_BOT = (38, 46, 70), (18, 22, 34)
TRACK = (70, 82, 110)
SLIDERS = [  # y, knob x, color
    (120, 270, (255, 186, 40)),
    (200, 140, (64, 200, 190)),
    (280, 220, (240, 100, 60)),
]
X0, X1, TR, KR = 80, 320, 9, 30  # track ends, track half-height, knob radius


def rounded_rect(x, y, x0, y0, x1, y1, r):
    cx = min(max(x, x0 + r), x1 - r)
    cy = min(max(y, y0 + r), y1 - r)
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def color_at(x, y):
    if not rounded_rect(x, y, 8, 8, SIZE - 8, SIZE - 8, 70):
        return None
    t = y / SIZE
    c = [BG_TOP[i] * (1 - t) + BG_BOT[i] * t for i in range(3)]
    for sy, kx, kc in SLIDERS:
        # filled part of the track (left of the knob) in the knob color, rest grey
        if rounded_rect(x, y, X0, sy - TR, X1, sy + TR, TR):
            c = list(kc) if x <= kx else list(TRACK)
        d = math.hypot(x - kx, y - sy)
        if d <= KR + 5:
            c = [10, 12, 20]                     # dark outline
        if d <= KR:
            c = [255, 255, 255]                  # white knob
        if d <= KR - 9:
            c = list(kc)                         # colored center
    return c


rows = []
for py in range(SIZE):
    row = bytearray([0])
    for px in range(SIZE):
        acc, n = [0, 0, 0], 0
        for sy in range(SS):
            for sx in range(SS):
                c = color_at(px + (sx + 0.5) / SS, py + (sy + 0.5) / SS)
                if c:
                    n += 1
                    for i in range(3):
                        acc[i] += c[i]
        if n:
            row += bytes(int(acc[i] / n) for i in range(3)) + bytes([int(255 * n / SS / SS)])
        else:
            row += b"\0\0\0\0"
    rows.append(bytes(row))


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(b"".join(rows), 9)) + chunk(b"IEND", b"")
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logo.png")
open(out, "wb").write(png)
print("wrote", out)
