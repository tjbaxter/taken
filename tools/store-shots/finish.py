#!/usr/bin/env python3
"""Taken store shots, step 2 of 2: every 2x render of one set from generate.mjs becomes an App Store frame at each
iPhone size the pack carries, RGB with no alpha (Lanczos), and a contact sheet of the set is written beside them.

  python3 tools/store-shots/finish.py <2x renders dir> <out dir> <set>

writes <out>/iphone-6.9/<set>/NN.png (1320 x 2868, iPhone with Dynamic Island, large display), <out>/iphone-6.3/<set>/
NN.png (1206 x 2622, the medium display App Store Connect lists as the required iPhone size) and
<out>/contact-sheet-<set>.jpg. Both sizes come from the same 2x render (2640 x 5736), whose aspect ratio differs from
1206 x 2622 by under 0.1 percent.
"""
import sys
from pathlib import Path

from PIL import Image

SIZES = {"iphone-6.9": (1320, 2868), "iphone-6.3": (1206, 2622)}
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
    src, out, name = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    renders = sorted(src.glob("*.png"))
    if not renders:
        sys.exit(f"no renders in {src}")
    frames = []
    for p in renders:
        im = flatten(Image.open(p))
        for device, (w, h) in SIZES.items():
            folder = out / device / name
            folder.mkdir(parents=True, exist_ok=True)
            sized = im if im.size == (w, h) else im.resize((w, h), LANCZOS)
            dst = folder / p.name
            sized.save(dst, "PNG", optimize=True)
            check = Image.open(dst)
            if check.size != (w, h) or check.mode != "RGB":
                sys.exit(f"{dst}: {check.size} {check.mode}, want {(w, h)} RGB")
            print(f"{device}/{name}/{dst.name}: {check.size[0]}x{check.size[1]} {check.mode}")
            if device == "iphone-6.9":
                frames.append(check)
    # contact sheet: the set side by side at a quarter size, as the store lays it out
    w, h = SIZES["iphone-6.9"]
    tw, th, gap, pad = w // 4, h // 4, 28, 56
    sheet = Image.new("RGB", (pad * 2 + tw * len(frames) + gap * (len(frames) - 1), pad * 2 + th), (20, 21, 23))
    for i, im in enumerate(frames):
        sheet.paste(im.resize((tw, th), LANCZOS), (pad + i * (tw + gap), pad))
    sheet.save(out / f"contact-sheet-{name}.jpg", "JPEG", quality=90, optimize=True)
    print(f"contact-sheet-{name}.jpg: {sheet.size[0]}x{sheet.size[1]}")


if __name__ == "__main__":
    main()
