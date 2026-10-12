#!/usr/bin/env python3
"""Taken store shots, step 2 of 2: every 2x render from generate.mjs becomes an App Store 6.9" frame, exactly
1320 x 2868, RGB with no alpha (Lanczos), and a contact sheet of the set is written beside them.

  python3 tools/store-shots/finish.py <2x renders dir> <out dir>
"""
import sys
from pathlib import Path

from PIL import Image

W, H = 1320, 2868
BG = (8, 9, 10)
LANCZOS = getattr(Image, "Resampling", Image).LANCZOS


def flatten(im):
    if im.mode in ("RGBA", "LA", "PA") or (im.mode == "P" and "transparency" in im.info):
        im = im.convert("RGBA")
        ground = Image.new("RGB", im.size, BG)
        ground.paste(im, mask=im.getchannel("A"))
        return ground
    return im.convert("RGB")


def main():
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    renders = sorted(src.glob("*.png"))
    if not renders:
        sys.exit(f"no renders in {src}")
    frames = []
    for p in renders:
        im = flatten(Image.open(p))
        if im.size != (W, H):
            im = im.resize((W, H), LANCZOS)
        dst = out / p.name
        im.save(dst, "PNG", optimize=True)
        check = Image.open(dst)
        if check.size != (W, H) or check.mode != "RGB":
            sys.exit(f"{dst}: {check.size} {check.mode}, want {(W, H)} RGB")
        frames.append(check)
        print(f"{dst.name}: {check.size[0]}x{check.size[1]} {check.mode}")
    # contact sheet: the set side by side at a quarter size, as the store lays it out
    tw, th, gap, pad = W // 4, H // 4, 28, 56
    sheet = Image.new("RGB", (pad * 2 + tw * len(frames) + gap * (len(frames) - 1), pad * 2 + th), (20, 21, 23))
    for i, im in enumerate(frames):
        sheet.paste(im.resize((tw, th), LANCZOS), (pad + i * (tw + gap), pad))
    sheet.save(out / "contact-sheet.jpg", "JPEG", quality=90, optimize=True)
    print(f"contact-sheet.jpg: {sheet.size[0]}x{sheet.size[1]}")


if __name__ == "__main__":
    main()
