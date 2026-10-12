#!/usr/bin/env python3
"""Taken app icon renderer.

Every shape is an analytic signed distance field evaluated on a supersampled
grid (default 4x, so 4096 px for a 1024 icon) and box-filtered down, which
gives exact, crisp anti-aliasing. Colours come from the Taken design tokens
(SPEC.md section 4). Run from the repo root:

    python3 brand/icon.py                      # final icon set into the asset catalog + brand/
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
        "fill": np.array([0.16, 0.16, 0.16], np.float32),
        "fill_deep": np.array([0.10, 0.10, 0.10], np.float32),
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
    h = np.clip((pax * bax + pay * bay) / (bax * bax + bay * bay), 0.0, 1.0)
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


CONCEPTS = {
    "split": concept_split,
}

FINAL = "split"


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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--concept", default=FINAL, choices=sorted(CONCEPTS))
    ap.add_argument("--variant", default="default", choices=sorted(PALETTES))
    ap.add_argument("--out")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--ss", type=int, default=4)
    ap.add_argument("--concepts", help="render every concept (all variants) into this folder")
    a = ap.parse_args()
    if a.concepts:
        for name in sorted(CONCEPTS):
            for variant in ("default", "dark", "tinted"):
                img = render(name, variant, a.size, a.ss)
                suffix = "" if variant == "default" else "-" + variant
                save_png(img, os.path.join(a.concepts, f"{name}{suffix}.png"))
                print("wrote", name, variant)
        return
    if a.out:
        save_png(render(a.concept, a.variant, a.size, a.ss), a.out)
        print("wrote", a.out)
        return
    write_asset_catalog(a.concept, a.ss)
    print("wrote asset catalog icons for", a.concept)


if __name__ == "__main__":
    main()
