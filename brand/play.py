#!/usr/bin/env python3
"""Taken's Google Play graphics (android/SPEC-ANDROID.md 14.2): the feature graphic and the store icon.

    python3 brand/play.py                 # writes both into android/store/play/en-US/images/
    python3 brand/play.py --check         # draws them again and compares with what is committed (android.yml)
    python3 brand/play.py --out x.png     # the feature graphic alone, for a look

The feature graphic is drawn here from Taken's own tokens and fonts, the same ones brand/icon.py draws the icons with
(SPEC.md section 4; brand/fonts is the app's Geist): the canvas warmed by Signal's amber, the question Taken answers, and
three rows of Today as the app draws them. The store icon is brand/icon.py's Play icon (android/store-assets/icon-512.png,
SPEC-ANDROID 6.5), copied byte for byte. The phone screenshots are not drawn here: they are the app itself, rendered by
Roborazzi (app/src/test/.../PlayStoreScreenshotTests.kt).

Google's rules, from "Add preview assets to showcase your app" (https://support.google.com/googleplay/android-developer/answer/9866151,
read 25 Oct 2026):
- Feature graphic: "JPEG or 24-bit PNG (no alpha)", "1024px by 500px". "Use graphics that convey app or game
  experiences, and highlight the core value proposition"; "Keep prominent visuals and the focal point towards the center
  of the graphic" and key elements ("brand logo, app name, primary slogan, and main UI") out of the cutoff zones at the
  edges; "Avoid using pure white, black, or dark gray as these colors can easily blend in with Google Play's background";
  "Do not use prominent branding that is similar to your app icon"; "Avoid overloading the graphic with fine details";
  no "Device imagery"; no words like "Best," "#1," "Top," "New," "Free," "Discount," "Sale," or "Million Downloads";
  no time-sensitive content.
- App icon: "32-bit PNG (with alpha)", "512px by 512px", "Maximum file size: 1024KB".

[Own choices] The layout: the words on the left, the rows on the right, the whole between x 92 and 940 so nothing sits
near an edge. The canvas is Signal's amber over a deep umber, not Taken's near-black, because of the rule above. The
rows are the neutral store set's (no medicine names, SPEC-ANDROID 14.2): Vitamin D3 and Magnesium taken, Fish Oil one of
two, Magnesium just tapped and washed in the signal as Today shows a fresh log (SPEC-ANDROID 7.2).
"""
import argparse
import os
import re
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import icon  # noqa: E402  (brand/icon.py: the tokens, the blur and save_png)

REPO = os.path.dirname(HERE)
IMAGES = os.path.join(REPO, "android", "store", "play", "en-US", "images")
FEATURE = os.path.join(IMAGES, "featureGraphic.png")
ICON = os.path.join(IMAGES, "icon.png")
FONTS = os.path.join(HERE, "fonts")

W, H = 1024, 500
SS = 4  # shapes and words are drawn 4 times larger and box-filtered down, as icon.py does

HEADLINE = ("Did I take it?", "Know for *sure.*")
ROWS = (
    # name, line under it, time, mark, washed (just logged)
    ("Vitamin D3", "Daily", "07:42", "taken", False),
    ("Fish Oil", "2x daily · 1 of 2", "07:43", "partial", False),
    ("Magnesium", "Daily", "21:41", "taken", True),
)

# Words Google lists for preview assets, and the house rules (no price, never "free", no exclamation mark, no dashes).
BANNED = [r"(?i)\bbest\b", r"#\s?1\b", r"(?i)\btop\b", r"(?i)\bnew\b", r"(?i)free", r"(?i)discount", r"(?i)\bsale\b",
          r"(?i)million", r"(?i)download", r"(?i)install", r"[$£€¥]\s?\d", "!", "—", "–"]


def words_ok():
    text = " ".join(HEADLINE) + " " + " ".join(f"{r[0]} {r[1]}" for r in ROWS)
    return [p for p in BANNED if re.search(p, text)]


def font(name, px):
    # The basic layout engine on every machine, so Linux and macOS lay the words out alike.
    return ImageFont.truetype(os.path.join(FONTS, name), int(round(px * SS)), layout_engine=ImageFont.Layout.BASIC)


def rgb8(c):
    return tuple(int(round(float(v) * 255)) for v in c)


def canvas():
    """Signal's amber over a deep umber: lit towards the centre, deeper at the edges."""
    y, x = np.mgrid[0:H, 0:W].astype(np.float32) + 0.5
    centre, edge = icon.hexrgb("#3A2706"), icon.hexrgb("#221704")
    v = np.clip(np.hypot((x - W / 2) / (W * 0.62), (y - H / 2) / (H * 0.9)), 0.0, 1.0)
    col = centre[None, None, :] * (1 - v[..., None]) + edge[None, None, :] * v[..., None]
    r = np.hypot((x - 600.0) / 640.0, (y - 230.0) / (640.0 * 0.62))
    t = np.clip(1.0 - r, 0.0, 1.0)
    t = t * t * (3 - 2 * t)  # smoothstep, as icon.py's lift
    add = icon.SIGNAL[None, None, :] * (t * 0.42)[..., None]
    return 1.0 - (1.0 - col) * (1.0 - add)  # screen, so the light never clips


def feature_graphic():
    col = canvas()
    layer = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    lit = Image.new("L", (W * SS, H * SS), 0)  # the lit discs, for their glow
    d = ImageDraw.Draw(layer)
    g = ImageDraw.Draw(lit)
    s = SS
    fg, subtle, signal, ink = rgb8(icon.FG), rgb8(icon.SUBTLE), rgb8(icon.SIGNAL), rgb8(icon.BG)
    raised = rgb8(icon.RAISED)

    def on_card(white):
        """Signal's white lines are white at an opacity over the card; ImageDraw replaces pixels, so blend here."""
        return tuple(int(round(raised[k] * (1 - white) + 255 * white)) for k in range(3)) + (255,)

    # The question, one word lit (the iPhone store frames' rule).
    head = font("Geist-SemiBold.ttf", 54)
    x0, y0, lead = 92, 178, 66
    for i, line in enumerate(HEADLINE):
        x = x0 * s
        for j, part in enumerate(line.split("*")):
            d.text((x, (y0 + i * lead) * s), part, font=head, fill=(signal if j % 2 else fg) + (255,))
            x += d.textlength(part, font=head)

    # Today's rows on a raised card, as the app draws them (ItemRow): 1.53 px to the dp.
    cx0, cy0, cw, rh, radius = 548, 112, 392, 92, 18
    ch = rh * len(ROWS)
    line = on_card(0.10)  # Signal's line
    d.rounded_rectangle([cx0 * s, cy0 * s, (cx0 + cw) * s, (cy0 + ch) * s], radius=radius * s, fill=raised + (255,),
                        outline=on_card(0.14), width=int(1.5 * s))
    name_f = font("Geist-Medium.ttf", 25)
    sub_f = font("Geist-Regular.ttf", 19)
    time_f = font("GeistMono-Medium.ttf", 22)
    wash = tuple(int(round(raised[k] * 0.9 + signal[k] * 0.1)) for k in range(3))  # signalWash 0.10
    for i, (name, sub, time, mark, washed) in enumerate(ROWS):
        top = cy0 + i * rh
        if washed:
            last = i == len(ROWS) - 1
            d.rounded_rectangle([cx0 * s + 6, top * s, (cx0 + cw) * s - 6, (top + rh) * s - 6], radius=(radius - 1.5) * s,
                                fill=wash + (255,), corners=(False, False, last, last))
        if i > 0:
            d.line([((cx0 + 22) * s, top * s), ((cx0 + cw) * s - 6, top * s)], fill=line, width=int(1.5 * s))
        d.text(((cx0 + 22) * s, (top + 20) * s), name, font=name_f, fill=fg + (255,))
        d.text(((cx0 + 22) * s, (top + 52) * s), sub, font=sub_f, fill=subtle + (255,))
        dcx, dcy, dr = cx0 + cw - 44, top + rh / 2, 21
        tw = d.textlength(time, font=time_f)
        d.text(((dcx - dr - 16) * s - tw, (top + rh / 2 - 13) * s), time, font=time_f, fill=signal + (255,))
        box = [(dcx - dr) * s, (dcy - dr) * s, (dcx + dr) * s, (dcy + dr) * s]
        if mark == "taken":
            d.ellipse(box, fill=signal + (255,))
            g.ellipse(box, fill=255)
            tick = [((dcx - 8) * s, (dcy + 0.5) * s), ((dcx - 2.5) * s, (dcy + 6) * s), ((dcx + 8.5) * s, (dcy - 6) * s)]
            d.line(tick, fill=ink + (255,), width=int(3.4 * s), joint="curve")
        else:
            inset = [box[0] + 1.5 * s, box[1] + 1.5 * s, box[2] - 1.5 * s, box[3] - 1.5 * s]
            d.ellipse(inset, outline=on_card(0.18), width=int(3 * s))
            d.arc(inset, -90, 90, fill=signal + (255,), width=int(3.4 * s))

    # The lit discs' glow (Signal's phosphor bloom), screened onto the canvas under the card's words.
    glow = icon.gaussian_blur(np.asarray(lit.reduce(SS), np.float32) / 255.0, 9.0)
    col = 1.0 - (1.0 - col) * (1.0 - icon.SIGNAL[None, None, :] * (glow * 0.55)[..., None])

    small = np.asarray(layer.reduce(SS), np.float32) / 255.0
    a = small[..., 3:4]
    out = col * (1.0 - a) + small[..., :3] * a
    # The discs keep their glow on the card around them, never over the disc and its tick.
    around = glow * 0.30 * a[..., 0] * (1.0 - np.asarray(lit.reduce(SS), np.float32) / 255.0)
    out = 1.0 - (1.0 - out) * (1.0 - icon.SIGNAL[None, None, :] * around[..., None])
    # A whisper of grain, seeded, so the warm gradient does not band in 8 bits.
    rng = np.random.default_rng(7)
    out = out + rng.normal(0.0, 0.8 / 255.0, (H, W)).astype(np.float32)[..., None]
    return Image.fromarray(np.round(np.clip(out, 0.0, 1.0) * 255.0).astype(np.uint8), "RGB")


def png_header(path):
    with open(path, "rb") as f:
        raw = f.read()
    return raw, raw[24], raw[25]  # bit depth, colour type (IHDR)


def write():
    bad = words_ok()
    if bad:
        raise SystemExit(f"the feature graphic's words break a rule: {bad}")
    os.makedirs(IMAGES, exist_ok=True)
    icon.save_png(feature_graphic(), FEATURE)
    print("wrote", os.path.relpath(FEATURE, REPO), f"({os.path.getsize(FEATURE)} bytes)")
    shutil.copyfile(icon.PLAY_ICON, ICON)
    print("wrote", os.path.relpath(ICON, REPO), "(a copy of", os.path.relpath(icon.PLAY_ICON, REPO) + ")")


def check(out_dir=None):
    failures = []

    def report(ok, what):
        print(("OK   " if ok else "FAIL ") + what)
        if not ok:
            failures.append(what)

    bad = words_ok()
    report(not bad, "the feature graphic's words have no price, ranking or promotion word" + (f" ({bad})" if bad else ""))
    rel = os.path.relpath(FEATURE, REPO)
    fresh = feature_graphic()
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        icon.save_png(fresh, os.path.join(out_dir, "featureGraphic.png"))
    if not os.path.isfile(FEATURE):
        report(False, f"{rel} exists")
    else:
        raw, depth, colour = png_header(FEATURE)
        have = Image.open(FEATURE)
        have.load()
        report(have.size == (W, H), f"{rel} is {W} x {H}")
        report(raw[:8] == b"\x89PNG\r\n\x1a\n" and depth == 8 and colour == 2 and b"tRNS" not in raw,
               f"{rel} is a 24-bit PNG with no alpha")
        if have.size == (W, H):
            diff = np.abs(np.asarray(fresh, np.int16) - np.asarray(have.convert("RGB"), np.int16))
            # numpy's maths and FreeType's edges may differ by a level here and there between machines; the art may not.
            report(diff.max() <= 3 and diff.mean() <= 0.1,
                   f"{rel} is what play.py draws (largest difference {diff.max()}, mean {diff.mean():.4f})")
    rel = os.path.relpath(ICON, REPO)
    same = os.path.isfile(ICON) and open(ICON, "rb").read() == open(icon.PLAY_ICON, "rb").read()
    report(same, f"{rel} is {os.path.relpath(icon.PLAY_ICON, REPO)}, byte for byte (icon.py checks that one)")
    return not failures


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="compare with the committed files, write nothing there")
    ap.add_argument("--fresh-out", help="with --check: also save the fresh feature graphic in this folder")
    ap.add_argument("--out", help="write the feature graphic alone to this path")
    a = ap.parse_args()
    if a.check:
        raise SystemExit(0 if check(a.fresh_out) else 1)
    if a.out:
        icon.save_png(feature_graphic(), a.out)
        print("wrote", a.out)
        return
    write()


if __name__ == "__main__":
    main()
