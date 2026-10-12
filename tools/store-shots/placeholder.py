#!/usr/bin/env python3
"""Stand-in raw screens for the store-shots pipeline, drawn after SPEC section 3 and 4 (1320 x 2868, the
status bar and home indicator included, as a simulator capture has them). They exist only so the composer can
be built and tuned before ci.yml produces the app's own captures; store-shots.yml falls back to them and says
so. Never ship a frame made from them.

  python3 tools/store-shots/placeholder.py   # writes store/placeholder/{today,today-done,add,day,settings,log}.png
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "store" / "placeholder"
FONTS = ROOT / "brand" / "fonts"
P = 3  # px per point
W, H = 440, 956  # points

BG, RAISED, INSET = (8, 9, 10), (15, 16, 18), (22, 23, 26)
FG, MUTED, SUBTLE, FAINT = (244, 244, 245), (161, 161, 170), (124, 124, 133), (82, 82, 91)
LINE, STRONG, DASH = (33, 34, 35), (52, 53, 54), (39, 39, 42)
SIGNAL, SIG_LINE, SIG_DIM = (255, 176, 0), (119, 84, 5), (38, 29, 9)
BTN, BTN_FG, DANGER = (228, 228, 231), (17, 17, 19), (255, 95, 87)


def font(name, pt):
    return ImageFont.truetype(str(FONTS / f"{name}.ttf"), round(pt * P))


SANS_M = lambda pt: font("Geist-Medium", pt)
SANS_S = lambda pt: font("Geist-SemiBold", pt)
MONO = lambda pt: font("GeistMono-Regular", pt)
MONO_M = lambda pt: font("GeistMono-Medium", pt)
MONO_S = lambda pt: font("GeistMono-SemiBold", pt)


class Screen:
    def __init__(self, bg=BG):
        self.im = Image.new("RGB", (W * P, H * P), bg)
        self.d = ImageDraw.Draw(self.im)

    def text(self, x, y, s, f, fill, track=0.0, anchor="l"):
        """y is the baseline in points; track in em; anchor l, m or r."""
        widths = [f.getlength(c) for c in s]
        total = sum(widths) + track * f.size * (len(s) - 1)
        px = x * P - (total if anchor == "r" else total / 2 if anchor == "m" else 0)
        for c, w in zip(s, widths):
            self.d.text((px, y * P), c, font=f, fill=fill, anchor="ls")
            px += w + track * f.size
        return total / P

    def rect(self, x0, y0, x1, y1, r=0, fill=None, outline=None, width=1.0):
        self.d.rounded_rectangle([x0 * P, y0 * P, x1 * P, y1 * P], radius=r * P, fill=fill, outline=outline, width=max(1, round(width * P)))

    def line(self, x0, y0, x1, y1, fill, width=1.0, dash=None):
        if not dash:
            self.d.line([x0 * P, y0 * P, x1 * P, y1 * P], fill=fill, width=max(1, round(width * P)))
            return
        on, off = dash
        x = x0
        while x < x1:
            self.d.line([x * P, y0 * P, min(x + on, x1) * P, y1 * P], fill=fill, width=max(1, round(width * P)))
            x += on + off

    def circle(self, cx, cy, r, fill=None, outline=None, width=1.0):
        self.d.ellipse([(cx - r) * P, (cy - r) * P, (cx + r) * P, (cy + r) * P], fill=fill, outline=outline, width=max(1, round(width * P)))

    def dashed_circle(self, cx, cy, r, fill, width=1.5, n=14):
        for i in range(n):
            a0 = i * 360 / n
            self.d.arc([(cx - r) * P, (cy - r) * P, (cx + r) * P, (cy + r) * P], a0, a0 + 360 / n * 0.55, fill=fill, width=round(width * P))

    def glow(self, cx, cy, r, color=SIGNAL, alpha=110, blur=10):
        layer = Image.new("RGBA", self.im.size, (0, 0, 0, 0))
        ImageDraw.Draw(layer).ellipse([(cx - r) * P, (cy - r) * P, (cx + r) * P, (cy + r) * P], fill=color + (alpha,))
        layer = layer.filter(ImageFilter.GaussianBlur(blur * P))
        base = self.im.convert("RGBA")
        base.alpha_composite(layer)
        self.im = base.convert("RGB")
        self.d = ImageDraw.Draw(self.im)

    def brackets(self, x0, y0, x1, y1, arm, color, width=1.5):
        for (x, y, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
            self.line(x, y, x + sx * arm, y, color, width)
            self.line(x, y, x, y + sy * arm, color, width)

    def status_bar(self, ink=FG):
        self.text(76, 37, "9:41", SANS_S(17), ink, anchor="m")
        for i in range(4):  # signal
            h = 3.6 + i * 2.5
            self.rect(331 + i * 4.7, 37 - h, 334.1 + i * 4.7, 37, 0.9, fill=ink)
        d = self.d  # wifi
        for r0, r1 in ((8.6, 11.4), (4.6, 7.3)):
            d.pieslice([(364 - r1) * P, (38 - r1) * P, (364 + r1) * P, (38 + r1) * P], 223, 317, fill=ink)
            d.pieslice([(364 - r0) * P, (38 - r0) * P, (364 + r0) * P, (38 + r0) * P], 223, 317, fill=BG)
        d.pieslice([(364 - 3.4) * P, (38 - 3.4) * P, (364 + 3.4) * P, (38 + 3.4) * P], 223, 317, fill=ink)
        self.rect(380, 25, 405, 37, 3.9, outline=(100, 100, 102), width=1)
        self.rect(382, 27, 403, 35, 2.3, fill=ink)
        self.rect(406.3, 29, 407.8, 33, 0.8, fill=(100, 100, 102))

    def home(self):
        self.rect(147, 943, 293, 948, 2.5, fill=(231, 231, 232))

    def gear(self, cx, cy):
        import math
        for i in range(8):
            a = i * math.pi / 4
            self.line(cx + math.cos(a) * 7, cy + math.sin(a) * 7, cx + math.cos(a) * 10.5, cy + math.sin(a) * 10.5, MUTED, 2.6)
        self.circle(cx, cy, 7.5, outline=MUTED, width=2)
        self.circle(cx, cy, 3, outline=MUTED, width=1.6)


STACK = [("VD3", "Vitamin D3", "DAILY"), ("FSH", "Fish Oil", "DAILY"), ("FIN", "Finasteride", "ALT DAYS")]


def row(s, y, code, name, freq, at=None, ago=None, action=None):
    taken = at is not None
    s.rect(22, y + 25, 72, y + 53, 4, outline=SIG_LINE if taken else STRONG, width=1)
    s.text(47, y + 44, code, MONO_M(13), SIGNAL if taken else FG, 0.06, "m")
    s.text(88, y + 38, name, SANS_M(19), FG)
    s.text(88, y + 59, freq, MONO(11), FAINT, 0.16)
    if taken:
        s.glow(404, y + 41, 12, alpha=120, blur=7)
        s.circle(404, y + 41, 11, fill=SIGNAL)
        s.text(382, y + 38, at, MONO_M(17), FG, 0.02, "r")
        if ago:
            s.text(382, y + 58, ago, MONO(11), SUBTLE, 0.14, "r")
    else:
        s.dashed_circle(404, y + 41, 11, FAINT)
        s.text(382, y + 46, action or "PENDING", MONO_M(11.5), SIGNAL if action else FAINT, 0.16, "r")


def history(s, y):
    s.text(22, y, "HISTORY / 5 WEEKS", MONO(11), SUBTLE, 0.16)
    s.text(418, y, "MON FIRST", MONO(11), FAINT, 0.16, "r")
    cw, ch, g = (396 - 6 * 6) / 7, 26, 6
    for i, c in enumerate("MTWTFSS"):
        s.text(22 + i * (cw + g) + cw / 2, y + 26, c, MONO(10.5), FAINT, anchor="m")
    grid = "LLLHLLL LLLLLNL LLHLLLL LLLLLLL LLLLTFF".split()
    for r, wk in enumerate(grid):
        for c, k in enumerate(wk):
            x0, y0 = 22 + c * (cw + g), y + 38 + r * (ch + g)
            if k == "L":
                s.rect(x0, y0, x0 + cw, y0 + ch, 3, fill=SIGNAL)
            elif k == "H":
                s.rect(x0, y0, x0 + cw, y0 + ch, 3, fill=SIG_DIM, outline=SIG_LINE, width=1)
                s.rect(x0, y0 + ch / 2, x0 + cw, y0 + ch, 3, fill=(150, 104, 6))
            elif k == "N":
                s.rect(x0, y0, x0 + cw, y0 + ch, 3, fill=INSET)
                s.line(x0 + cw / 2, y0 + ch / 2 - 3, x0 + cw / 2, y0 + ch / 2 + 3, FAINT, 1.2)
            elif k == "T":
                s.rect(x0, y0, x0 + cw, y0 + ch, 3, fill=SIG_DIM, outline=FG, width=1.5)
            else:
                s.rect(x0, y0, x0 + cw, y0 + ch, 3, outline=LINE, width=1)
    ys = y + 38 + 5 * ch + 4 * g + 38
    w = s.text(22, ys, "STREAK ", MONO(13), SUBTLE, 0.14)
    s.text(22 + w + 4, ys, "14D", MONO_M(13), FG, 0.14)
    s.text(418, ys, "97%", MONO_M(13), FG, 0.14, "r")
    s.text(418 - 40, ys, "30D", MONO(13), SUBTLE, 0.14, "r")


def today(done=False, status=True):
    s = Screen()
    if status:
        s.status_bar()
    s.text(22, 92, "TAKEN", MONO_M(14), FG, 0.3)
    s.text(386, 92, "MON 12 OCT", MONO(12), SUBTLE, 0.16, "r")
    s.gear(410, 87.5)
    col = SIGNAL if done else SUBTLE
    s.brackets(20, 112, 420, 258, 14, col, 1.5)
    count = "3/3" if done else "1/3"
    if done:
        s.glow(80, 170, 40, alpha=60, blur=22)
    w = s.text(38, 198, count, MONO_M(66), SIGNAL if done else FG, -0.02)
    s.text(38 + w + 14, 194, "ALL TAKEN" if done else "TAKEN TODAY", MONO_M(12), SIGNAL if done else SUBTLE, 0.16)
    lit = 3 if done else 1
    sw = (364 - 2 * 5) / 3
    for i in range(3):
        x0 = 38 + i * (sw + 5)
        if i < lit:
            s.glow(x0 + sw / 2, 228, 10, alpha=50, blur=6)
        s.rect(x0, 225, x0 + sw, 231, 1, fill=SIGNAL if i < lit else STRONG)
    y = 280
    times = [("07:42", "2H AGO")] * 3 if done else [("07:42", "2H AGO"), (None, None), (None, None)]
    for i, (code, name, freq) in enumerate(STACK):
        at, ago = times[i]
        row(s, y, code, name, freq, at, ago)
        if i < 2:
            s.line(22, y + 82, 418, y + 82, LINE, 1, dash=(3, 3))
        y += 82
    if done:
        s.text(220, y + 40, "ALL TAKEN 07:42", MONO_M(12), SIGNAL, 0.2, "m")
        history(s, y + 92)
    else:
        s.rect(20, y + 18, 420, y + 74, 6, fill=BTN)
        s.text(220, y + 52, "TAKE ALL", MONO_S(15), BTN_FG, 0.2, "m")
        history(s, y + 118)
    s.home()
    return s.im


def sheet_over(back, top, dim=0.42):
    """An iOS sheet: the presenting screen pushed back and dimmed, the sheet rising from `top` (pt)."""
    bg = Image.new("RGB", back.size, (0, 0, 0))
    k = 0.93
    small = back.resize((round(back.width * k), round(back.height * k)), Image.LANCZOS)
    small = Image.blend(Image.new("RGB", small.size, (0, 0, 0)), small, dim)
    mask = Image.new("L", small.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, small.width, small.height], radius=38 * P, fill=255)
    bg.paste(small, ((back.width - small.width) // 2, round(14 * P)), mask)
    s = Screen()
    s.im = bg
    s.d = ImageDraw.Draw(s.im)
    s.rect(0, top, W, H + 40, 38, fill=RAISED)
    s.rect(202, top + 6, 238, top + 11, 2.5, fill=(78, 78, 84))
    s.status_bar()
    return s


CHIPS = ["VITAMIN D3", "FISH OIL", "OMEGA-3", "MAGNESIUM", "CREATINE", "MULTIVITAMIN", "ZINC", "VITAMIN C",
         "VITAMIN B12", "IRON", "PROBIOTIC", "ASHWAGANDHA", "MELATONIN", "COLLAGEN", "FINASTERIDE", "MINOXIDIL",
         "METFORMIN", "ELECTROLYTES", "VITAMIN K2", "FOLATE", "CALCIUM", "TURMERIC", "COQ10", "L-THEANINE", "+ CUSTOM"]


def add():
    s = sheet_over(today(status=False), 58)
    s.text(22, 108, "CANCEL", MONO_M(12.5), SUBTLE, 0.12)
    s.text(220, 108, "ADD TO STACK", MONO_M(14), FG, 0.2, "m")
    s.text(22, 152, "TAP TO PICK. NO TYPING.", MONO(11), FAINT, 0.16)
    f = MONO_M(12.5)
    picked = {"VITAMIN D3", "FISH OIL", "FINASTERIDE"}
    x, y = 22, 168
    for c in CHIPS:
        w = f.getlength(c) / P + 0.06 * 12.5 * (len(c) - 1) + 28
        if x + w > 418:
            x, y = 22, y + 50
        on = c in picked
        s.rect(x, y, x + w, y + 40, 6, fill=SIG_DIM if on else RAISED, outline=SIG_LINE if on else (58, 59, 61), width=1)
        s.text(x + w / 2, y + 25, c, f, SIGNAL if on else (FAINT if c.startswith("+") else FG), 0.06, "m")
        x += w + 8
    y += 84
    s.text(22, y, "FREQUENCY", MONO(11), FAINT, 0.16)
    s.rect(20, y + 14, 420, y + 58, 8, fill=INSET)
    segs = ["DAILY", "2X DAILY", "3X DAILY", "ALT DAYS"]
    sw = 396 / 4
    for i, t in enumerate(segs):
        x0 = 22 + i * sw
        if i == 0:
            s.rect(x0, y + 16, x0 + sw, y + 56, 6, fill=(48, 49, 53))
        s.text(x0 + sw / 2, y + 41, t, MONO_M(11.5), FG if i == 0 else SUBTLE, 0.1, "m")
    s.rect(20, 864, 420, 920, 6, fill=BTN)
    s.text(220, 898, "ADD (3)", MONO_S(15), BTN_FG, 0.2, "m")
    return s.im


def day():
    s = sheet_over(today(status=False), 448, dim=0.5)
    y = 448
    s.text(24, y + 56, "SAT 10 OCT", MONO_M(15), FG, 0.2)
    s.text(416, y + 56, "2/3 TAKEN", MONO_M(12), SIGNAL, 0.16, "r")
    s.line(22, y + 76, 418, y + 76, (39, 40, 42), 1)
    y += 84
    rows = [("07:38", None), ("07:38", None), (None, "MARK TAKEN 09:00")]
    for i, (code, name, freq) in enumerate(STACK):
        at, action = rows[i]
        row(s, y, code, name, freq, at, None, action)
        if i < 2:
            s.line(22, y + 82, 418, y + 82, (39, 40, 42), 1, dash=(3, 3))
        y += 82
    s.rect(20, 864, 420, 920, 6, fill=BTN)
    s.text(220, 898, "DONE", MONO_S(15), BTN_FG, 0.2, "m")
    s.home()
    return s.im


def settings():
    s = Screen()
    s.status_bar()
    s.text(22, 92, "CLOSE", MONO_M(12.5), SUBTLE, 0.12)
    s.text(220, 92, "SETTINGS", MONO_M(14), FG, 0.2, "m")

    def group(y, label, rows, foot=None):
        s.text(24, y, label, MONO(11), SUBTLE, 0.16)
        y0 = y + 12
        s.rect(20, y0, 420, y0 + 52 * len(rows), 6, fill=RAISED, outline=LINE, width=1)
        for i, r in enumerate(rows):
            yy = y0 + i * 52
            if i:
                s.line(36, yy, 420, yy, LINE, 1)
            r(yy)
        y = y0 + 52 * len(rows)
        if foot:
            s.text(24, y + 22, foot, SANS_M(13), SUBTLE)
            y += 22
        return y + 40

    def item(code, name, freq):
        def f(yy):
            s.text(36, yy + 32, code, MONO_M(12.5), SUBTLE, 0.08)
            s.text(82, yy + 32, name, SANS_M(17), FG)
            s.text(372, yy + 32, freq, MONO(11), FAINT, 0.16, "r")
            s.line(392, yy + 21, 392, yy + 31, FAINT, 1.4)
            s.line(398, yy + 21, 398, yy + 31, FAINT, 1.4)
        return f

    def plain(label, value=None, color=FG, mono=False):
        def f(yy):
            s.text(36, yy + 32, label, MONO_M(13) if mono else SANS_M(17), color, 0.12 if mono else 0)
            if value:
                s.text(404, yy + 32, value, MONO_M(15), FG, 0.04, "r")
        return f

    def toggle(label):
        def f(yy):
            s.text(36, yy + 32, label, SANS_M(17), FG)
            s.rect(354, yy + 11, 404, yy + 41, 15, fill=SIGNAL)
            s.circle(389, yy + 26, 13, fill=(255, 255, 255))
        return f

    y = group(140, "STACK", [item(*r) for r in STACK] + [plain("+ ADD", color=SIGNAL, mono=True)])
    y = group(y, "REMINDER", [toggle("Nudge me"), plain("Time", "21:00")], "If anything is still pending at this time, nudge me.")
    y = group(y, "DAY STARTS AT", [plain("Day starts at", "04:00")])
    y = group(y, "HAPTICS", [toggle("Haptics")])
    y = group(y, "DATA", [plain("Export CSV"), plain("Erase all data", color=DANGER)])
    s.text(24, y, "ABOUT", MONO(11), SUBTLE, 0.16)
    s.text(24, y + 26, "Everything stays on this iPhone. No accounts.", SANS_M(14), MUTED)
    s.text(24, y + 46, "No ads. No tracking.", SANS_M(14), MUTED)
    s.home()
    return s.im


def log():
    """TODAY scrolled to its log: five weeks, the streak, the footer, the TAKE ALL dock."""
    s = Screen()
    s.status_bar()
    s.text(22, 92, "TAKEN", MONO_M(14), FG, 0.3)
    s.text(386, 92, "MON 12 OCT", MONO(12), SUBTLE, 0.16, "r")
    s.gear(410, 87.5)
    s.line(0, 112, 440, 112, LINE, 1)
    row(s, 120, "MAG", "Magnesium", "DAILY")
    history(s, 260)
    s.text(22, 690, "LOCAL ONLY / NO ACCOUNTS / NO ADS / NO TRACKING", MONO(11), FAINT, 0.12)
    s.rect(20, 860, 420, 916, 6, fill=BTN)
    s.text(220, 894, "TAKE ALL (2)", MONO_S(15), BTN_FG, 0.2, "m")
    s.home()
    return s.im


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, im in (("today", today()), ("today-done", today(True)), ("add", add()), ("day", day()), ("settings", settings()), ("log", log())):
        assert im.size == (1320, 2868) and im.mode == "RGB"
        im.save(OUT / f"{name}.png", optimize=True)
        print(OUT / f"{name}.png")


if __name__ == "__main__":
    main()
