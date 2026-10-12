#!/usr/bin/env python3
"""Taken app icon renderer.

Every shape is an analytic signed distance field evaluated on a supersampled
grid (default 4x, so 4096 px for a 1024 icon) and box-filtered down, which
gives exact, crisp anti-aliasing. Colours come from the Taken design tokens
(SPEC.md section 4). Run from the repo root:

    python3 brand/icon.py                      # final icon set (asset catalog), brand/*.svg, site icons in docs/
    python3 brand/icon.py --concept reticle --out /tmp/x.png --variant default
    python3 brand/icon.py --concepts brand/concepts   # render every concept

Variants:
    default  opaque sRGB, no alpha (App Store marketing icon rule)
    dark     artwork on a transparent background (the system draws its own dark backdrop)
    tinted   grayscale artwork on a transparent background (the system applies the tint)
"""
import argparse
import math
import os

import numpy as np
from PIL import Image, ImageCms

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
APPICON_DIR = os.path.join(REPO, "Taken", "Assets.xcassets", "AppIcon.appiconset")


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32) / 255.0


# Design tokens (SPEC.md section 4, lifted from badline.ai / lupolabs.ai)
BG = hexrgb("#08090A")
RAISED = hexrgb("#0F1012")
INSET = hexrgb("#16171A")
FG = hexrgb("#F4F4F5")
MUTED = hexrgb("#A1A1AA")
SUBTLE = hexrgb("#7C7C85")
FAINT = hexrgb("#52525B")
SIGNAL = hexrgb("#FFB000")

# Role colours per variant. Concepts paint roles, never raw colours.
PALETTES = {
    "default": {
        "lit": SIGNAL,
        "lit_hi": hexrgb("#FFC845"),
        "line": hexrgb("#8A8A93"),
        "line_dim": hexrgb("#3A3A41"),
        "fill": INSET,
        "fill_deep": RAISED,
        "fg": FG,
        "cut": BG,
    },
    "dark": {
        "lit": hexrgb("#F5A800"),
        "lit_hi": hexrgb("#FFC03A"),
        "line": hexrgb("#9A9AA3"),
        "line_dim": hexrgb("#4A4A52"),
        "fill": hexrgb("#1C1D21"),
        "fill_deep": hexrgb("#141518"),
        "fg": FG,
        "cut": None,  # cut = transparent
    },
    "tinted": {
        "lit": np.array([1.0, 1.0, 1.0], np.float32),
        "lit_hi": np.array([1.0, 1.0, 1.0], np.float32),
        "line": np.array([0.62, 0.62, 0.62], np.float32),
        "line_dim": np.array([0.30, 0.30, 0.30], np.float32),
        "fill": None,       # unlit areas stay empty so only the outline takes the tint
        "fill_deep": None,
        "fg": np.array([1.0, 1.0, 1.0], np.float32),
        "cut": None,
    },
}


# ---------------------------------------------------------------- SDF kit
# Coordinates are output pixels (0..1024), y down. Negative = inside.

def sd_circle(x, y, cx, cy, r):
    return np.hypot(x - cx, y - cy) - r


def sd_segment(x, y, ax, ay, bx, by):
    pax, pay = x - ax, y - ay
    bax, bay = bx - ax, by - ay
    h = np.clip((pax * bax + pay * bay) / max(bax * bax + bay * bay, 1e-9), 0.0, 1.0)
    return np.hypot(pax - bax * h, pay - bay * h)


def sd_capsule(x, y, ax, ay, bx, by, r):
    return sd_segment(x, y, ax, ay, bx, by) - r


def sd_box(x, y, cx, cy, hw, hh, r=0.0, angle=0.0):
    """Rounded box centred at (cx, cy), half extents hw/hh, rotated by angle (radians)."""
    dx, dy = x - cx, y - cy
    if angle:
        c, s = math.cos(angle), math.sin(angle)
        dx, dy = c * dx + s * dy, -s * dx + c * dy
    qx = np.abs(dx) - (hw - r)
    qy = np.abs(dy) - (hh - r)
    outside = np.hypot(np.maximum(qx, 0.0), np.maximum(qy, 0.0))
    inside = np.minimum(np.maximum(qx, qy), 0.0)
    return outside + inside - r


def sd_halfplane(x, y, px, py, nx, ny):
    """Positive on the side the normal points to."""
    return (x - px) * nx + (y - py) * ny


def op_union(*ds):
    out = ds[0]
    for d in ds[1:]:
        out = np.minimum(out, d)
    return out


def op_intersect(*ds):
    out = ds[0]
    for d in ds[1:]:
        out = np.maximum(out, d)
    return out


def op_subtract(a, b):
    return np.maximum(a, -b)


def op_inner_stroke(d, w):
    return np.maximum(d, -(d + w))


def op_stroke(d, w):
    return np.abs(d) - w / 2.0


# ---------------------------------------------------------------- renderer

class Renderer:
    def __init__(self, variant="default", size=1024, ss=4):
        self.variant = variant
        self.pal = PALETTES[variant]
        self.size = size
        self.ss = ss
        n = size * ss
        c = (np.arange(n, dtype=np.float32) + 0.5) / ss * (1024.0 / size)
        self.x = c[None, :]
        self.y = c[:, None]
        self.px = (1.0 / ss) * (1024.0 / size)
        self.rgb = np.zeros((size, size, 3), np.float32)  # premultiplied
        self.a = np.zeros((size, size), np.float32)
        # coarse grid (output res) for soft effects
        oc = (np.arange(size, dtype=np.float32) + 0.5) * (1024.0 / size)
        self.ox = oc[None, :]
        self.oy = oc[:, None]

    # coverage of an sdf, box-filtered to output resolution
    def cov(self, fn):
        d = fn(self.x, self.y)
        m = np.clip(0.5 - d / self.px, 0.0, 1.0).astype(np.float32)
        s = self.size
        return m.reshape(s, self.ss, s, self.ss).mean(axis=(1, 3))

    def over(self, color, alpha):
        alpha = np.clip(alpha, 0.0, 1.0)[..., None]
        self.rgb = self.rgb * (1.0 - alpha) + color[None, None, :] * alpha
        self.a = self.a * (1.0 - alpha[..., 0]) + alpha[..., 0]

    def fill(self, fn, role, opacity=1.0):
        col = self.pal[role]
        m = self.cov(fn) * opacity
        if col is None:  # punch out
            keep = 1.0 - m
            self.rgb *= keep[..., None]
            self.a *= keep
            return m
        self.over(col, m)
        return m

    def fill_cov(self, m, role, opacity=1.0):
        col = self.pal[role]
        if col is None:
            keep = 1.0 - m * opacity
            self.rgb *= keep[..., None]
            self.a *= keep
            return
        self.over(col, m * opacity)

    def background(self, lift=0.0, lift_radius=640.0, cx=512.0, cy=512.0):
        if self.variant != "default":
            return
        r = np.hypot(self.ox - cx, self.oy - cy) / lift_radius
        t = np.clip(1.0 - r, 0.0, 1.0)
        t = t * t * (3 - 2 * t)  # smoothstep
        col = BG[None, None, :] + (RAISED - BG)[None, None, :] * (t[..., None] * lift)
        self.rgb = np.broadcast_to(col, (self.size, self.size, 3)).astype(np.float32).copy()
        self.a = np.ones((self.size, self.size), np.float32)

    def glow(self, m, radius, strength, role="lit"):
        """Soft additive bloom from a coverage mask. Default variant only."""
        if self.variant != "default" or strength <= 0:
            return
        g = gaussian_blur(m, radius * self.size / 1024.0)
        col = self.pal[role]
        add = g[..., None] * col[None, None, :] * strength
        # screen blend so it never clips harshly
        self.rgb = 1.0 - (1.0 - self.rgb) * (1.0 - add)

    def grain(self, amount=1.0, seed=7):
        if self.variant != "default" or amount <= 0:
            return
        rng = np.random.default_rng(seed)
        n = rng.normal(0.0, amount / 255.0, (self.size, self.size)).astype(np.float32)
        self.rgb = self.rgb + n[..., None] * self.a[..., None]

    def image(self):
        a = np.clip(self.a, 0.0, 1.0)
        if self.variant == "default":
            rgb = np.clip(self.rgb, 0.0, 1.0)
            arr = np.round(rgb * 255.0).astype(np.uint8)
            return Image.fromarray(arr, "RGB")
        safe = np.where(a[..., None] > 1e-6, self.rgb / np.maximum(a[..., None], 1e-6), 0.0)
        if self.variant == "tinted":
            lum = (0.2126 * safe[..., 0] + 0.7152 * safe[..., 1] + 0.0722 * safe[..., 2])
            safe = np.repeat(lum[..., None], 3, axis=2)
        rgba = np.concatenate([np.clip(safe, 0, 1), a[..., None]], axis=2)
        arr = np.round(rgba * 255.0).astype(np.uint8)
        arr[arr[..., 3] == 0, :3] = 0
        return Image.fromarray(arr, "RGBA")


def gaussian_blur(m, sigma):
    """FFT gaussian blur of a float mask with zero padding (no wraparound)."""
    if sigma <= 0:
        return m
    pad = int(math.ceil(sigma * 3))
    h, w = m.shape
    P = np.zeros((h + 2 * pad, w + 2 * pad), np.float32)
    P[pad:pad + h, pad:pad + w] = m
    fy = np.fft.fftfreq(P.shape[0])[:, None]
    fx = np.fft.rfftfreq(P.shape[1])[None, :]
    k = np.exp(-2.0 * (math.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    out = np.fft.irfft2(np.fft.rfft2(P) * k, s=P.shape)
    return out[pad:pad + h, pad:pad + w].astype(np.float32)


# ---------------------------------------------------------------- shared pieces

def viewfinder(r, half=300.0, arm=86.0, t=18.0, role="line", opacity=1.0, cx=512.0, cy=512.0, round_=3.0):
    """Four corner brackets (viewfinder) around a square of half-size `half`."""
    def fn(x, y):
        ds = []
        for sx in (-1, 1):
            for sy in (-1, 1):
                ox = cx + sx * half
                oy = cy + sy * half
                # horizontal arm
                hx = ox - sx * arm / 2.0
                ds.append(sd_box(x, y, hx, oy - sy * t / 2.0, arm / 2.0, t / 2.0, round_))
                # vertical arm
                vy = oy - sy * arm / 2.0
                ds.append(sd_box(x, y, ox - sx * t / 2.0, vy, t / 2.0, arm / 2.0, round_))
        return op_union(*ds)
    return r.fill(fn, role, opacity)


def edge_ticks(r, half=300.0, length=30.0, t=12.0, role="line_dim", opacity=1.0, cx=512.0, cy=512.0):
    """Centre tick marks on each side of the viewfinder square (HUD reticle)."""
    def fn(x, y):
        return op_union(
            sd_box(x, y, cx, cy - half + length / 2.0, t / 2.0, length / 2.0, 2.0),
            sd_box(x, y, cx, cy + half - length / 2.0, t / 2.0, length / 2.0, 2.0),
            sd_box(x, y, cx - half + length / 2.0, cy, length / 2.0, t / 2.0, 2.0),
            sd_box(x, y, cx + half - length / 2.0, cy, length / 2.0, t / 2.0, 2.0),
        )
    return r.fill(fn, role, opacity)


# ---------------------------------------------------------------- concepts

def concept_split(r, angle_deg=45.0, half_len=150.0, rad=112.0, gap=16.0, stroke=16.0,
                  vf=True, ticks=True, glow=0.28):
    """A capsule split across its waist: the lit half in signal amber (taken),
    the other half an outlined dark shell, inside viewfinder brackets."""
    r.background(lift=0.9)
    if vf:
        viewfinder(r, half=318.0, arm=92.0, t=18.0, role="line", opacity=0.85)
    if ticks:
        edge_ticks(r, half=318.0, length=34.0, t=12.0, role="line_dim")
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), -math.sin(a)  # axis, pointing up-right
    cx = cy = 512.0
    ax, ay = cx - ux * half_len, cy - uy * half_len
    bx, by = cx + ux * half_len, cy + uy * half_len

    def cap(x, y):
        return sd_capsule(x, y, ax, ay, bx, by, rad)

    def lit(x, y):  # lower-left half
        return op_intersect(cap(x, y), sd_halfplane(x, y, cx, cy, ux, uy) + gap / 2.0)

    def shell(x, y):  # upper-right half
        return op_intersect(cap(x, y), -sd_halfplane(x, y, cx, cy, ux, uy) + gap / 2.0)

    r.fill(shell, "fill")
    r.fill(lambda x, y: op_inner_stroke(shell(x, y), stroke), "line")
    m = r.fill(lit, "lit")
    r.glow(m, radius=46.0, strength=glow)
    r.grain(0.9)


def capsule_halves(cx, cy, angle_deg, half_len, rad, gap):
    """SDFs for a capsule cut across its waist: (whole, lower-left half, upper-right half)."""
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), -math.sin(a)
    ax, ay = cx - ux * half_len, cy - uy * half_len
    bx, by = cx + ux * half_len, cy + uy * half_len

    def cap(x, y):
        return sd_capsule(x, y, ax, ay, bx, by, rad)

    def near(x, y):
        return op_intersect(cap(x, y), sd_halfplane(x, y, cx, cy, ux, uy) + gap / 2.0)

    def far(x, y):
        return op_intersect(cap(x, y), -sd_halfplane(x, y, cx, cy, ux, uy) + gap / 2.0)

    return cap, near, far


def concept_reticle(r):
    """A lit capsule at the centre of a 24-hour tick dial; one amber tick marks the time it was taken."""
    r.background(lift=0.9)
    cx = cy = 512.0
    n = 24
    lit_index = 8  # 07:42 rounds to the 08 hour tick on a 24 h dial, 00 at the top

    def ticks(major, lit):
        def fn(x, y):
            ds = []
            for i in range(n):
                is_major = i % 6 == 0
                if lit and i != lit_index:
                    continue
                if not lit and (is_major != major or i == lit_index):
                    continue
                th = math.radians(i * 360.0 / n)
                ro = 372.0
                ri = 316.0 if is_major else 336.0
                if lit:
                    ri = 300.0
                rm = (ro + ri) / 2.0
                px, py = cx + math.sin(th) * rm, cy - math.cos(th) * rm
                w = 16.0 if (is_major or lit) else 12.0
                ds.append(sd_box(x, y, px, py, w / 2.0, (ro - ri) / 2.0, 3.0, angle=-th))
            return op_union(*ds)
        return fn

    r.fill(ticks(False, False), "line_dim")
    r.fill(ticks(True, False), "line")
    lm = r.fill(ticks(False, True), "lit")
    cap, near, far = capsule_halves(cx, cy, 45.0, 118.0, 92.0, 14.0)
    r.fill(far, "fill")
    r.fill(lambda x, y: op_inner_stroke(far(x, y), 14.0), "line")
    m = r.fill(near, "lit")
    r.glow(np.maximum(m, lm), radius=40.0, strength=0.26)
    r.grain(0.9)


def concept_engraved(r):
    """A solid amber capsule with a check cut clean through it, inside viewfinder brackets."""
    r.background(lift=0.9)
    viewfinder(r, half=318.0, arm=92.0, t=18.0, role="line", opacity=0.85)
    cx = cy = 512.0
    a = math.radians(45.0)
    ux, uy = math.cos(a), -math.sin(a)
    hl, rad = 150.0, 132.0
    ax, ay = cx - ux * hl, cy - uy * hl
    bx, by = cx + ux * hl, cy + uy * hl
    # check mark centred on the capsule
    p1 = (cx - 92.0, cy + 6.0)
    p2 = (cx - 26.0, cy + 72.0)
    p3 = (cx + 104.0, cy - 58.0)

    def check(x, y):
        return op_union(sd_capsule(x, y, *p1, *p2, 21.0), sd_capsule(x, y, *p2, *p3, 21.0))

    def body(x, y):
        return op_subtract(sd_capsule(x, y, ax, ay, bx, by, rad), check(x, y))

    m = r.fill(body, "lit")
    r.glow(m, radius=46.0, strength=0.24)
    r.grain(0.9)


def concept_monogram(r):
    """A 'T': the crossbar is a half-lit capsule, the stem a tick ruler (a timeline)."""
    r.background(lift=0.9)
    cx = 512.0
    bar_y = 348.0
    hl, rad, gap = 186.0, 70.0, 16.0

    def cap(x, y):
        return sd_capsule(x, y, cx - hl, bar_y, cx + hl, bar_y, rad)

    def left(x, y):
        return op_intersect(cap(x, y), (x - cx) + gap / 2.0)

    def right(x, y):
        return op_intersect(cap(x, y), -(x - cx) + gap / 2.0)

    r.fill(right, "fill")
    r.fill(lambda x, y: op_inner_stroke(right(x, y), 15.0), "line")
    m = r.fill(left, "lit")
    top, bottom = bar_y + rad + 38.0, 808.0

    def stem(x, y):
        return sd_box(x, y, cx, (top + bottom) / 2.0, 9.0, (bottom - top) / 2.0, 3.0)

    def rungs(major):
        def fn(x, y):
            ds = []
            k = 0
            yy = top + 18.0
            while yy < bottom - 4.0:
                is_major = k % 4 == 0
                if is_major == major:
                    w = 96.0 if is_major else 54.0
                    ds.append(sd_box(x, y, cx, yy, w / 2.0, 7.0, 2.5))
                yy += 38.0
                k += 1
            return op_union(*ds)
        return fn

    r.fill(stem, "line")
    r.fill(rungs(False), "line_dim")
    r.fill(rungs(True), "line")
    r.glow(m, radius=40.0, strength=0.26)
    r.grain(0.9)


def concept_grid(r):
    """Five weeks of days as a lit grid: the history view as a mark. Today outlined."""
    r.background(lift=0.9)
    n, cell, gap = 5, 92.0, 22.0
    total = n * cell + (n - 1) * gap
    x0 = 512.0 - total / 2.0 + cell / 2.0
    # 0 = dim, 1 = half, 2 = lit, 3 = today (outlined)
    pattern = [
        [2, 2, 2, 1, 2],
        [2, 2, 2, 2, 2],
        [2, 0, 2, 2, 2],
        [2, 2, 2, 2, 2],
        [2, 2, 2, 2, 3],
    ]

    def cells(kind):
        def fn(x, y):
            ds = []
            for j in range(n):
                for i in range(n):
                    if pattern[j][i] == kind:
                        ds.append(sd_box(x, y, x0 + i * (cell + gap), x0 + j * (cell + gap), cell / 2.0, cell / 2.0, 14.0))
            return op_union(*ds) if ds else np.full_like(x + y, 1e6)
        return fn

    r.fill(cells(0), "fill")
    r.fill(lambda x, y: op_inner_stroke(cells(0)(x, y), 10.0), "line_dim")
    r.fill(cells(1), "lit", opacity=0.42)
    m = r.fill(cells(2), "lit")
    r.fill(lambda x, y: op_inner_stroke(cells(3)(x, y), 12.0), "lit")
    r.glow(m, radius=34.0, strength=0.18)
    r.grain(0.9)


def concept_checkpills(r):
    """A check mark built from two capsules, each with its waist seam, in viewfinder brackets."""
    r.background(lift=0.9)
    viewfinder(r, half=318.0, arm=92.0, t=18.0, role="line", opacity=0.85)
    rad, gap = 58.0, 14.0
    v = (446.0, 640.0)
    e1 = (318.0, 512.0)
    e2 = (716.0, 370.0)

    def seamed(p, q):
        mx, my = (p[0] + q[0]) / 2.0, (p[1] + q[1]) / 2.0
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        ux, uy = (q[0] - p[0]) / L, (q[1] - p[1]) / L

        def fn(x, y):
            cap = sd_capsule(x, y, *p, *q, rad)
            seam = np.abs(sd_halfplane(x, y, mx, my, ux, uy)) - gap / 2.0
            return op_subtract(cap, seam)
        return fn

    s1, s2 = seamed(v, e1), seamed(v, e2)
    m = r.fill(lambda x, y: op_union(s1(x, y), s2(x, y)), "lit")
    r.glow(m, radius=44.0, strength=0.24)
    r.grain(0.9)


def half_capsule_outline_points(cx, cy, angle_deg, half_len, rad, gap, inset, step=2.0):
    """Points along the centre line of an inner stroke around the far (unlit) half of a
    capsule: cut edge, side, round cap, side. Returns a list of (x, y) and the total length."""
    a = math.radians(angle_deg)
    ux, uy = math.cos(a), -math.sin(a)
    nx, ny = -uy, ux  # perpendicular
    rr = rad - inset  # stroke centre radius
    g = gap / 2.0 + inset
    pts = []

    def add_line(p, q):
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        k = max(2, int(L / step))
        for i in range(k):
            t = i / k
            pts.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))

    # cap centre of the far half
    ccx, ccy = cx + ux * half_len, cy + uy * half_len
    p0 = (cx + ux * g + nx * rr, cy + uy * g + ny * rr)
    p1 = (cx + ux * g - nx * rr, cy + uy * g - ny * rr)
    q1 = (ccx - nx * rr, ccy - ny * rr)
    q0 = (ccx + nx * rr, ccy + ny * rr)
    add_line(p0, p1)          # cut edge
    add_line(p1, q1)          # side
    # cap arc from -n to +n through +u
    k = max(8, int(math.pi * rr / step))
    for i in range(k):
        t = math.pi * i / k
        dx = -nx * math.cos(t) + ux * math.sin(t)
        dy = -ny * math.cos(t) + uy * math.sin(t)
        pts.append((ccx + dx * rr, ccy + dy * rr))
    add_line(q0, p0)          # other side, back to start
    return pts


def dashes_along(pts, dash, period, phase=0.0, closed=True):
    """Split a dense polyline into dash polylines by arc length."""
    if closed:
        pts = pts + [pts[0]]
    out, cur, s = [], [], -phase
    for i in range(len(pts) - 1):
        p, q = pts[i], pts[i + 1]
        L = math.hypot(q[0] - p[0], q[1] - p[1])
        on = (s % period) < dash
        if on:
            cur.append(p)
        elif cur:
            cur.append(p)
            out.append(cur)
            cur = []
        s += L
    if cur:
        out.append(cur)
    return out


def concept_split2(r, dashed=False, core=0.0):
    """Refined split capsule: bigger mark, finer brackets, the unlit half reads as PENDING."""
    r.background(lift=1.0)
    viewfinder(r, half=322.0, arm=104.0, t=16.0, role="line", opacity=0.9)
    edge_ticks(r, half=322.0, length=40.0, t=12.0, role="line_dim")
    cx = cy = 512.0
    hl, rad, gap, stroke = 156.0, 116.0, 18.0, 16.0
    cap, near, far = capsule_halves(cx, cy, 45.0, hl, rad, gap)
    r.fill(far, "fill_deep")
    if dashed:
        pts = half_capsule_outline_points(cx, cy, 45.0, hl, rad, gap, stroke / 2.0)
        segs = dashes_along(pts, dash=34.0, period=56.0, phase=-6.0)

        def dash_fn(x, y):
            ds = []
            for seg in segs:
                sub = seg[:: max(1, len(seg) // 6)] + [seg[-1]]
                for i in range(len(sub) - 1):
                    ds.append(sd_capsule(x, y, *sub[i], *sub[i + 1], stroke / 2.0))
            return op_union(*ds)
        r.fill(dash_fn, "line")
    else:
        r.fill(lambda x, y: op_inner_stroke(far(x, y), stroke), "line")
    m = r.fill(near, "lit")
    if core > 0 and r.variant != "tinted":
        # phosphor core: a faint hotter centre that falls off toward the edges of the lit half
        inner = gaussian_blur(r.cov(lambda x, y: near(x, y) + 44.0), 38.0 * r.size / 1024.0)
        r.over(r.pal["lit_hi"], np.clip(inner, 0, 1) * m * core)
    r.glow(m, radius=50.0, strength=0.30)
    r.grain(0.9)


def concept_reticle2(r):
    """Capsule inside a bold 12-hour tick dial; the lit tick sits at 8, beside the lit half."""
    r.background(lift=1.0)
    cx = cy = 512.0
    lit_hour = 8

    def ticks(kind):
        def fn(x, y):
            ds = []
            for i in range(12):
                major = i % 3 == 0
                lit = i == lit_hour
                k = "lit" if lit else ("major" if major else "minor")
                if k != kind:
                    continue
                th = math.radians(i * 30.0)
                ro = 374.0
                ri = 318.0 if (major or lit) else 338.0
                rm = (ro + ri) / 2.0
                px, py = cx + math.sin(th) * rm, cy - math.cos(th) * rm
                w = 18.0 if (major or lit) else 14.0
                ds.append(sd_box(x, y, px, py, w / 2.0, (ro - ri) / 2.0, 3.0, angle=-th))
            return op_union(*ds)
        return fn

    r.fill(ticks("minor"), "line_dim")
    r.fill(ticks("major"), "line")
    lm = r.fill(ticks("lit"), "lit")
    cap, near, far = capsule_halves(cx, cy, 45.0, 138.0, 104.0, 16.0)
    r.fill(far, "fill_deep")
    r.fill(lambda x, y: op_inner_stroke(far(x, y), 15.0), "line")
    m = r.fill(near, "lit")
    r.glow(np.maximum(m, lm), radius=46.0, strength=0.28)
    r.grain(0.9)


def concept_glyph(r, k=1.62, stroke=34.0, gap=30.0):
    """Favicon / small-size glyph: the capsule alone, scaled up, no brackets."""
    r.background(lift=1.0)
    cap, near, far = capsule_halves(512.0, 512.0, 45.0, 156.0 * k, 116.0 * k, gap)
    r.fill(far, "fill_deep")
    r.fill(lambda x, y: op_inner_stroke(far(x, y), stroke), "line")
    m = r.fill(near, "lit")
    r.glow(m, radius=60.0, strength=0.22)


CONCEPTS = {
    "glyph": concept_glyph,
    "split": concept_split,
    "split2": concept_split2,
    "split2dash": lambda r: concept_split2(r, dashed=True),
    "split2core": lambda r: concept_split2(r, core=0.55),
    "taken": lambda r: concept_split2(r, core=0.3),
    "reticle2": concept_reticle2,
    "reticle": concept_reticle,
    "engraved": concept_engraved,
    "monogram": concept_monogram,
    "grid": concept_grid,
    "checkpills": concept_checkpills,
}

FINAL = "taken"  # the shipped icon: split2 with a faint phosphor core


def render(concept, variant="default", size=1024, ss=4, **kw):
    r = Renderer(variant=variant, size=size, ss=ss)
    CONCEPTS[concept](r, **kw)
    return r.image()


def save_png(img, path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    icc = ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes()
    img.save(path, "PNG", optimize=True, icc_profile=icc)


def write_asset_catalog(concept, ss=4):
    os.makedirs(APPICON_DIR, exist_ok=True)
    out = {}
    for variant, name in (("default", "AppIcon.png"), ("dark", "AppIcon-dark.png"), ("tinted", "AppIcon-tinted.png")):
        img = render(concept, variant, 1024, ss)
        save_png(img, os.path.join(APPICON_DIR, name))
        out[variant] = img
    save_png(out["default"], os.path.join(HERE, "icon-1024.png"))
    return out


def _capsule_paths(hl, rad, gap, stroke):
    """SVG path data in a frame where the capsule axis is +x, centred at 0,0."""
    g = gap / 2.0
    lit = f"M{-g:g} {-rad:g}H{-hl:g}A{rad:g} {rad:g} 0 0 0 {-hl:g} {rad:g}H{-g:g}Z"
    shell = f"M{g:g} {-rad:g}H{hl:g}A{rad:g} {rad:g} 0 0 1 {hl:g} {rad:g}H{g:g}Z"
    i = stroke / 2.0
    ri = rad - i
    outline = f"M{g + i:g} {-ri:g}H{hl:g}A{ri:g} {ri:g} 0 0 1 {hl:g} {ri:g}H{g + i:g}Z"
    return lit, shell, outline


def svg_mark(full=True):
    """The icon as SVG. full=True: the whole 1024 icon (square, background, brackets).
    full=False: the capsule glyph alone on a transparent background, tightly framed."""
    hl, rad, gap, stroke = 156.0, 116.0, 18.0, 16.0
    lit, shell, outline = _capsule_paths(hl, rad, gap, stroke)
    capsule = (
        f'<g transform="translate(512 512) rotate(-45)">'
        f'<path d="{shell}" fill="#0F1012"/>'
        f'<path d="{outline}" fill="none" stroke="#8A8A93" stroke-width="{stroke:g}"/>'
        f'<path d="{lit}" fill="#FFB000"/>'
        f"</g>"
    )
    if not full:
        ext = hl * math.cos(math.radians(45)) + rad + 6
        v = f"{512 - ext:.1f} {512 - ext:.1f} {2 * ext:.1f} {2 * ext:.1f}"
        return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{v}" role="img" aria-label="Taken">'
                f"{capsule}</svg>\n")
    half, arm, t = 322.0, 104.0, 16.0
    rects = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            ox, oy = 512 + sx * half, 512 + sy * half
            hx0 = ox if sx < 0 else ox - arm
            hy0 = oy if sy < 0 else oy - t
            vx0 = ox if sx < 0 else ox - t
            vy0 = oy if sy < 0 else oy - arm
            rects.append(f'<rect x="{hx0:g}" y="{hy0:g}" width="{arm:g}" height="{t:g}" rx="3"/>')
            rects.append(f'<rect x="{vx0:g}" y="{vy0:g}" width="{t:g}" height="{arm:g}" rx="3"/>')
    tl, tt = 40.0, 12.0
    ticks = [
        (512 - tt / 2, 512 - half, tt, tl), (512 - tt / 2, 512 + half - tl, tt, tl),
        (512 - half, 512 - tt / 2, tl, tt), (512 + half - tl, 512 - tt / 2, tl, tt),
    ]
    tick_svg = "".join(f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="2"/>' for x, y, w, h in ticks)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" role="img" aria-label="Taken">'
        '<defs><filter id="glow" x="-50%" y="-50%" width="200%" height="200%">'
        '<feGaussianBlur stdDeviation="40"/></filter></defs>'
        '<rect width="1024" height="1024" fill="#08090A"/>'
        f'<g fill="#8A8A93" opacity="0.9">{"".join(rects)}</g>'
        f'<g fill="#3A3A41">{tick_svg}</g>'
        f'<g transform="translate(512 512) rotate(-45)" opacity="0.35" filter="url(#glow)">'
        f'<path d="{lit}" fill="#FFB000"/></g>'
        f"{capsule}</svg>\n"
    )


def svg_favicon():
    """Rounded dark tile with the capsule glyph, legible in a 16 px browser tab."""
    k, gap, stroke = 1.62, 30.0, 34.0
    hl, rad = 156.0 * k, 116.0 * k
    lit, shell, outline = _capsule_paths(hl, rad, gap, stroke)
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">'
        '<rect width="1024" height="1024" rx="228" fill="#08090A"/>'
        f'<g transform="translate(512 512) rotate(-45)">'
        f'<path d="{shell}" fill="#0F1012"/>'
        f'<path d="{outline}" fill="none" stroke="#8A8A93" stroke-width="{stroke:g}"/>'
        f'<path d="{lit}" fill="#FFB000"/></g></svg>\n'
    )


def og_card(out, icon_img):
    """1200x630 link-preview card for the site."""
    from PIL import ImageDraw, ImageFont
    W, H = 1200, 630
    img = Image.new("RGB", (W, H), tuple(int(c * 255) for c in BG))
    d = ImageDraw.Draw(img)
    sans = ImageFont.truetype(os.path.join(HERE, "fonts", "Geist-Medium.ttf"), 64)
    mono = ImageFont.truetype(os.path.join(HERE, "fonts", "GeistMono-Medium.ttf"), 20)

    def tracked(x, y, text, font, fill, track):
        for ch in text:
            d.text((x, y), ch, font=font, fill=fill)
            x += d.textlength(ch, font=font) + track
        return x

    line = (34, 35, 38)
    # frame + dashed rules, like the sites
    d.rectangle([24, 24, W - 25, H - 25], outline=line, width=1)
    for x in range(24, W - 24, 8):
        d.line([(x, 112), (x + 3, 112)], fill=(52, 53, 58))
        d.line([(x, H - 112), (x + 3, H - 112)], fill=(52, 53, 58))
    sub = (124, 124, 133)
    tracked(64, 62, "TAKEN", mono, (244, 244, 245), 4)
    tracked(W - 64 - 330, 62, "PILL & SUPPLEMENT LOG", mono, sub, 2.6)
    tile = icon_img.resize((300, 300), Image.LANCZOS)
    img.paste(tile, (64, (H - 300) // 2), squircle_mask(300))
    tx = 420
    d.text((tx, 232), "Did I take it?", font=sans, fill=(244, 244, 245))
    d.text((tx, 310), "Know for sure.", font=sans, fill=(161, 161, 170))
    y = H - 84
    x = tracked(64, y, "ONE TAP", mono, sub, 3)
    x = tracked(x + 18, y, "/", mono, (82, 82, 91), 0)
    x = tracked(x + 18, y, "NOTHING TO READ", mono, sub, 3)
    x = tracked(x + 18, y, "/", mono, (82, 82, 91), 0)
    tracked(x + 18, y, "NOTHING LEAVES YOUR PHONE", mono, sub, 3)
    d.ellipse([W - 64 - 10, y + 6, W - 64, y + 16], fill=(255, 176, 0))
    save_png(img, out)


def write_web_assets(docs_dir):
    """Favicons, touch icon and the link-preview card for the GitHub Pages site."""
    os.makedirs(docs_dir, exist_ok=True)
    with open(os.path.join(docs_dir, "favicon.svg"), "w") as f:
        f.write(svg_favicon())
    glyph = render("glyph", "default", 256, 4)
    save_png(glyph.resize((32, 32), Image.LANCZOS), os.path.join(docs_dir, "favicon-32.png"))
    full = render(FINAL, "default", 1024, 4)
    save_png(full.resize((180, 180), Image.LANCZOS), os.path.join(docs_dir, "apple-touch-icon.png"))
    save_png(full.resize((512, 512), Image.LANCZOS), os.path.join(docs_dir, "icon-512.png"))
    og_card(os.path.join(docs_dir, "og.png"), full)


def write_svgs():
    with open(os.path.join(HERE, "mark.svg"), "w") as f:
        f.write(svg_mark(full=True))
    with open(os.path.join(HERE, "glyph.svg"), "w") as f:
        f.write(svg_mark(full=False))


def squircle_mask(size, n=5.0, ss=4):
    """iOS-like continuous-corner mask (superellipse approximation) for previews."""
    s = size * ss
    c = (np.arange(s, dtype=np.float32) + 0.5) / s * 2.0 - 1.0
    v = np.abs(c[None, :]) ** n + np.abs(c[:, None]) ** n
    m = (v <= 1.0).astype(np.float32).reshape(size, ss, size, ss).mean(axis=(1, 3))
    return Image.fromarray(np.round(m * 255).astype(np.uint8), "L")


def contact_sheet(names, out, ss=2):
    """Each concept large, then home-screen 180 px and 60 px, masked, on a dark and a light wall."""
    tile_w, pad = 620, 28
    W = pad + len(names) * (tile_w + pad)
    H = 900
    sheet = Image.new("RGB", (W, H), (20, 21, 24))
    try:
        from PIL import ImageDraw, ImageFont
        font = ImageFont.truetype(os.path.join(HERE, "fonts", "GeistMono-Medium.ttf"), 22)
        draw = ImageDraw.Draw(sheet)
    except Exception:
        draw, font = None, None
    for k, name in enumerate(names):
        img = render(name, "default", 1024, ss)
        x = pad + k * (tile_w + pad)
        big = img.resize((560, 560), Image.LANCZOS)
        sheet.paste(big, (x + 30, 60), squircle_mask(560))
        if draw:
            draw.text((x + 30, 22), name.upper(), fill=(161, 161, 170), font=font)
        # a mid-dark wallpaper strip with home-screen and spotlight sizes
        sheet.paste(Image.new("RGB", (tile_w, 250), (46, 50, 58)), (x, 640))
        for sz, ox in ((180, 40), (120, 260), (60, 420), (40, 520)):
            small = img.resize((sz, sz), Image.LANCZOS)
            sheet.paste(small, (x + ox, 640 + (250 - sz) // 2), squircle_mask(sz))
    sheet.save(out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", help="write a contact sheet of every concept to this PNG")
    ap.add_argument("--names", help="comma separated concepts for --sheet")
    ap.add_argument("--concept", default=FINAL, choices=sorted(CONCEPTS))
    ap.add_argument("--variant", default="default", choices=sorted(PALETTES))
    ap.add_argument("--out")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--ss", type=int, default=4)
    ap.add_argument("--concepts", help="render every concept (default variant) into this folder")
    ap.add_argument("--web-only", action="store_true", help="only the SVG marks and the site icons")
    a = ap.parse_args()
    if a.sheet:
        names = a.names.split(",") if a.names else sorted(CONCEPTS)
        print("wrote", contact_sheet(names, a.sheet, ss=a.ss))
        return
    if a.concepts:
        names = a.names.split(",") if a.names else sorted(CONCEPTS)
        for name in names:
            img = render(name, "default", a.size, a.ss)
            save_png(img, os.path.join(a.concepts, f"{name}.png"))
            print("wrote", name)
        return
    if a.out:
        save_png(render(a.concept, a.variant, a.size, a.ss), a.out)
        print("wrote", a.out)
        return
    if not a.web_only:
        write_asset_catalog(a.concept, a.ss)
        print("wrote asset catalog icons for", a.concept)
    write_svgs()
    write_web_assets(os.path.join(REPO, "docs"))
    print("wrote brand/mark.svg, brand/glyph.svg and the site icons in docs/")


if __name__ == "__main__":
    main()
