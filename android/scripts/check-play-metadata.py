#!/usr/bin/env python3
"""Checks Taken's Google Play listing text (android/store/play) against Google's limits and policies and the house copy
rules. android.yml runs it as a step of the core job; run it by hand from the repository root with:
    python3 android/scripts/check-play-metadata.py
Standard library only, no Gradle.

Layout: fastlane supply's (https://docs.fastlane.tools/actions/supply/ ; its field and folder names are the constants in
https://github.com/fastlane/fastlane/blob/master/supply/lib/supply.rb), so any publishing tool reads it:
  android/store/play/<locale>/{title,short_description,full_description}.txt   (video.txt allowed)
  android/store/play/<locale>/changelogs/{default,<versionCode>}.txt
  android/store/play/<locale>/images/  featureGraphic, icon, promoGraphic, tvBanner (.png .jpg .jpeg) and the folders
                                       phoneScreenshots, sevenInchScreenshots, tenInchScreenshots, tvScreenshots,
                                       wearScreenshots (the screenshot step fills them)
supply uploads each file exactly as it is on disk (File.read, no strip:
https://github.com/fastlane/fastlane/blob/master/supply/lib/supply/uploader.rb), so a trailing newline would be sent to
Play and counted. The text files therefore end without one, and every count below is of the file as it is.

Google's limits and policies, as of October 2026:
- App name 30, short description 80, full description 4000 characters ("Character limits apply to both full-width and
  half-width characters"): https://support.google.com/googleplay/android-developer/answer/9859152
- Release notes "up to 500 Unicode characters per language":
  https://support.google.com/googleplay/android-developer/answer/9859348
- Metadata policy: no emojis or ALL CAPS in the title, nothing that indicates price, promotion, store performance or a
  Google Play program ("New", "Editor's choice"); the title and description "accurately describe your app's
  functionality"; no misleading, improperly formatted or repetitive metadata and no unattributed testimonials:
  https://support.google.com/googleplay/android-developer/answer/9898842
- Store listing best practices: "Don't repeat your short description in your full description"; no "free", "discount",
  "#1" or "Best" in the short description; in app descriptions "your images and text should not indicate the price and
  promotional information", so no price anywhere in the listing:
  https://support.google.com/googleplay/android-developer/answer/13393723
- Health Content and Services: an app that is not a regulated medical device states it is "not a medical device and
  does not diagnose, treat, cure, or prevent any medical condition" in its description, and reminds users "to consult a
  healthcare professional for medical advice, diagnosis, or treatment"; a privacy policy link in the store listing:
  https://support.google.com/googleplay/android-developer/answer/16679511 . Both sentences, as SPEC-ANDROID 14.2 words
  them, must be in the full description word for word.
- Subscriptions: before enrollment, in the app ("in-app promotions, splash screens, and subscription plan selection
  screens"), the cost, the billing period, "whether a subscription is required to use the app", a trial's length, "how
  and when a free trial will convert to a paid subscription" and how to cancel; no wording is prescribed:
  https://support.google.com/googleplay/android-developer/answer/9900533 . The paywall carries them with Play's prices
  (SPEC-ANDROID 9.6); the listing names the plans, the trial and how it turns paid, renewal and cancelling, with no
  price, the iPhone listing's form (REDESIGN.md, "Review fixes and the Weight tab in 1.1").

The house rules (SPEC-ANDROID 6.4 and 14.2, REDESIGN.md "Extras policy, 2026-10-22", scripts/check-store-metadata.py
for the iPhone): plain ASCII text plus the bullet, so no em or en dash and no emoji; no spaced hyphen standing in for a
dash; no exclamation mark; never "free", even inside a word (the trial is "7 days on us", as in PRO.md and the iPhone
listing; Play's purchase sheet says the rest); no hype; Taken is its own brand; no Apple words (Taken for Android has no
Siri, Lock Screen, Control Center or Action button); US spelling; no medicine name, brand or generic, from the catalog
(the en-US listing is Play's default for every country, and the iPhone check holds every storefront to the same rule),
and no "GLP-1", "jab" or "pen"; no feature Android 1.0 does not show ("Keep as one" waits for an on-device model,
SPEC-ANDROID 11); the extras never in the title, the short description or the description's first lines, voice to-dos
as the last feature paragraph, right before Taken Pro, and the Weight tab never named at all (REDESIGN.md, "Weight tab
in 1.1, 2026-10-23": "never in the name, subtitle, keywords, description, promotional text or screenshots").

The graphics in images/ (SPEC-ANDROID 14.2), from "Add preview assets to showcase your app"
(https://support.google.com/googleplay/android-developer/answer/9866151, read 25 Oct 2026), each read from the file's
own header with the standard library:
- Phone screenshots: "JPEG or 24-bit PNG (no alpha)", "Minimum dimension: 320px", "Maximum dimension: 3840px", "The
  maximum dimension of your screenshot can't be more than twice as long as the minimum dimension", "up to 8
  screenshots"; for promotion "at least four screenshots with minimum 1080px resolution" in 9:16 portrait. So 4 to 8,
  named 1.png to n.png in the order Play shows them, each 9:16 and at least 1080 x 1920 (Tom's brief, 25 Oct 2026).
- Feature graphic: "JPEG or 24-bit PNG (no alpha)", "1024px by 500px".
- App icon: "32-bit PNG (with alpha)", "512px by 512px", "Maximum file size: 1024KB"; it must be
  android/store-assets/icon-512.png byte for byte, the file brand/icon.py draws and checks.
With --rendered DIR (the screenshots job), every phone screenshot must also be byte for byte the frame the app draws now
(app/src/test/.../PlayStoreScreenshotTests.kt writes them to DIR), so the listing never shows an older app.
Exits 1 with every problem listed; prints each field's count against its limit.
"""
import argparse
import re
import struct
import sys
import zlib
from pathlib import Path

ANDROID = Path(__file__).resolve().parent.parent
PLAY = ANDROID / "store" / "play"
CATALOG = ANDROID / "core" / "src" / "main" / "kotlin" / "com" / "tombaxter" / "taken" / "core" / "catalog" / "Catalog.kt"

LOCALES = ["en-US"]
LIMITS = {"title": 30, "short_description": 80, "full_description": 4000}
OPTIONAL_FIELDS = {"video"}
CHANGELOG_LIMIT = 500
IMAGE_NAMES = {"featureGraphic", "icon", "promoGraphic", "tvBanner"}
SCREENSHOT_FOLDERS = {"phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots", "tvScreenshots",
                      "wearScreenshots"}
IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg"}
# Google's sizes (answer/9866151) and the set Tom asked for: 4 to 8 phone screenshots at 9:16, 1080 x 1920 or larger.
SCREENSHOTS_MIN, SCREENSHOTS_MAX = 4, 8
SCREENSHOT_MIN_SIDE, SCREENSHOT_MAX_SIDE, PROMOTION_MIN_SIDE = 320, 3840, 1080
FEATURE_SIZE = (1024, 500)
ICON_SIZE = (512, 512)
ICON_MAX_BYTES = 1024 * 1024
PLAY_ICON = ANDROID / "store-assets" / "icon-512.png"
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# Health Content and Services (answer/16679511), in SPEC-ANDROID 14.2's words.
DISCLAIMERS = [
    "Taken is not a medical device and does not diagnose, treat, cure, or prevent any medical condition.",
    "Always consult a healthcare professional for medical advice, diagnosis, or treatment.",
]
PRIVACY_URL = "https://tjbaxter.github.io/taken/privacy.html"
# Taken's own terms for Google Play (docs/terms.html); Apple's standard EULA does not apply there (SPEC-ANDROID 19.9).
TERMS_URL = "https://tjbaxter.github.io/taken/terms.html"
ALLOWED_URLS = {PRIVACY_URL, TERMS_URL, "https://tjbaxter.github.io/taken/"}
CONTACT_EMAIL = "tjpb2@cantab.ac.uk"

# Taken Pro (SPEC-ANDROID 9.1 and 9.2) and the Subscriptions policy's terms (answer/9900533). Each phrase must be in
# the full description's Taken Pro paragraph. No price anywhere (best practices, answer/13393723): Play's en-US listing
# shows in every country, and the paywall and Play's purchase sheet show the price in the buyer's currency.
PRO_HEADING = "Taken Pro"
PRO_PHRASES = {
    "a yearly plan": "the yearly plan",
    "a monthly plan": "the monthly plan",
    "one payment for good": "that the lifetime is one payment",
    "7 days on us": "the trial's length",
    "New subscribers": "who the trial is for",
    "When the 7 days are up, Google Play charges the yearly price": "when the trial turns into the paid yearly plan",
    "unless you cancel before the trial ends": "how to avoid the charge",
    "renew automatically until you cancel": "that the subscriptions renew",
    "Cancel anytime in Google Play": "how to cancel",
    "first dose": "whether a subscription is needed to use the app",
    "in your currency": "that Google Play shows the price before the purchase",
}
PRICE = re.compile(r"(?:US)?[$£€¥]\s?\d|\d+[.,]\d\d\s?(?:usd|gbp|eur)\b|\b(?:usd|us dollars?)\b", re.I)

# Apple's surfaces and brands. "Home Screen" is Apple's capitalization; Android says "home screen".
APPLE_WORDS = [r"(?i)\bsiri\b", r"(?i)\biphone", r"(?i)\bipad", r"(?i)\bios\b", r"(?i)\bicloud", r"(?i)app store",
               r"(?i)\bapple", r"(?i)lock screen", r"Home Screen", r"(?i)control cent(?:er|re)", r"(?i)action button",
               r"(?i)face id", r"(?i)dynamic island", r"(?i)\bstandby\b", r"(?i)carplay", r"(?i)healthkit",
               r"(?i)testflight", r"(?i)live activit", r"(?i)\bwatchos\b", r"(?i)apple watch"]
OTHER_BRANDS = [r"(?i)pestline", r"(?i)\blupo\b", r"(?i)badline"]
# Hype, store performance and Google Play programs (Metadata policy, answer/9898842; best practices, answer/13393723).
HYPE = [r"(?i)\bbest\b", r"#\s?1\b", r"(?i)number one", r"(?i)top[- ]rated", r"(?i)\bultimate\b",
        r"(?i)revolution", r"(?i)\bamazing\b", r"(?i)\bincredible\b", r"(?i)\bperfect\b", r"(?i)world'?s\b",
        r"(?i)award", r"(?i)guarantee", r"(?i)must[- ]have", r"(?i)game[- ]chang", r"(?i)editor'?s choice",
        r"(?i)\bdiscount", r"(?i)\bon sale\b", r"(?i)% off", r"(?i)limited time", r"(?i)\bpowerful\b",
        r"(?i)\bseamless", r"(?i)\beffortless", r"(?i)\bsupercharge"]
# Words the title and short description must not carry at all (Google Play programs and promotions).
TITLE_ONLY = [r"(?i)\bnew\b", r"(?i)\bno ads\b", r"(?i)\bsale\b"]
BRANDS = ["ozempic", "wegovy", "mounjaro", "zepbound", "rybelsus", "saxenda", "trulicity", "propecia", "proscar",
          "rogaine", "regaine", "glucophage", "yasmin", "microgynon"]
BANNED_WORDS = [r"glp-?1", r"jabs?", r"pens?"]
# Weight words as stems from the start of a word, as the iPhone check has them.
WEIGHT_STEMS = [r"weigh\w*", r"slim\w*", r"fat(?:s|ty|ter|test|ten\w*)?", r"diet\w*", r"calor\w*", r"obes\w*",
                r"los(?:e|es|er|ers|ing|s|t)", r"pounds?", r"lbs?", r"kgs?", r"kilo\w*", r"bmi", r"waist\w*",
                r"bell(?:y|ies)", r"trim\w*", r"burn\w*"]
TODO_WORDS = [r"to-?dos?", r"voice\w*", r"mic\b", r"speech", r"notes?"]
TODO_HEADING = "Voice to-dos"
# Built but not shown on Android 1.0: Keep as one is offered only after a model split a note, and 1.0 has no model
# (SPEC-ANDROID 11; TodoExtraction.kt, keepable needs TodoSorting.MODEL). Remove a phrase here once it ships.
NOT_IN_1_0 = [r"keep as one"]
# The chips that are medicines, as in the iPhone check; every other chip is a supplement.
CHIP_MEDICINES = ["Melatonin", "Finasteride", "Minoxidil", "Birth Control", "Metformin", "Semaglutide", "Tirzepatide"]
UK_SPELLINGS = [r"colour", r"favourite", r"organis", r"personalis", r"customis", r"recognis", r"centre", r"licence",
                r"cancelled", r"cancelling", r"travelled", r"programme", r"\bmum\b", r"analyse", r"realis",
                r"behaviour", r"\bgrey\b", r"catalogue", r"\bcheque", r"judgement", r"enrol\b", r"enrolment",
                r"fulfil\b", r"practise"]
ALLOWED_CAPS = {"CSV"}

problems = []

arguments = argparse.ArgumentParser(description="Checks the Google Play listing in android/store/play.")
arguments.add_argument("--rendered", type=Path, help="the phone screenshots the app draws now "
                       "(app/build/outputs/roborazzi/play/phoneScreenshots); each committed one must match it byte for byte")
ARGS = arguments.parse_args()


def problem(where, text):
    problems.append(f"{where}: {text}")


def read(path, where):
    if not path.is_file():
        problem(where, "missing")
        return ""
    raw = path.read_bytes()
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        problem(where, f"not UTF-8 ({error})")
        return ""
    if raw.startswith(b"\xef\xbb\xbf"):
        problem(where, "starts with a byte order mark")
    if text != text.strip():
        problem(where, "starts or ends with whitespace or a newline; supply uploads the file exactly as it is")
    if "\r" in text or "\t" in text:
        problem(where, "contains a carriage return or a tab")
    if "\n\n\n" in text:
        problem(where, "more than one blank line in a row")
    for number, line in enumerate(text.split("\n"), 1):
        if line != line.rstrip():
            problem(where, f"line {number} ends with spaces")
    return text


def catalog_medicines():
    """Every medicine in the Android catalog (core/catalog/Catalog.kt, ported from Shared/Catalog.swift) with its other
    names, lower case: the medicines list and the chips in CHIP_MEDICINES. Misspellings are never shown, so left out."""
    if not CATALOG.is_file():
        problem("Catalog.kt", f"missing at {CATALOG}")
        return []
    source = CATALOG.read_text(encoding="utf-8")

    def entries(name):
        block = re.search(rf"private val {name}: List<CatalogEntry> = listOf\((.*?)\n    \)", source, re.S)
        if not block:
            problem("Catalog.kt", f"no {name} list; the parser no longer matches the file")
            return {}
        found = {}
        for chunk in block.group(1).split("CatalogEntry(")[1:]:
            entry = re.match(r'\s*"([^"]+)"', chunk)
            aliases = re.search(r"aliases\s*=\s*listOf\(([^)]*)\)", chunk, re.S)
            if entry:
                found[entry.group(1)] = re.findall(r'"([^"]+)"', aliases.group(1)) if aliases else []
        return found

    chips = entries("chips")
    medicines = entries("medicines")
    for name in CHIP_MEDICINES:
        if name not in chips:
            problem("Catalog.kt", f'no chip "{name}" (CHIP_MEDICINES)')
        else:
            medicines[name] = chips[name]
    if len(medicines) < 100:
        problem("Catalog.kt", f"found only {len(medicines)} medicines; the parser no longer matches the file")
    names = set(BRANDS)
    for name, aliases in medicines.items():
        names.add(name.lower())
        names.update(alias.lower() for alias in aliases)
    return sorted(names)


MEDICINES = catalog_medicines()


def search_all(patterns, text):
    for pattern in patterns:
        hit = re.search(pattern, text)
        if hit:
            yield hit.group(0)


def copy_rules(where, text):
    # Plain ASCII and the bullet: no em or en dash, no curly quotes, no emoji or other symbol.
    odd = sorted({c for c in text if not (c == "\n" or " " <= c <= "~" or c == "•")})
    if odd:
        problem(where, "characters outside plain ASCII and the bullet: " + " ".join(f"U+{ord(c):04X}" for c in odd))
    if re.search(r"\s-+\s", text):
        problem(where, "a spaced hyphen stands in for a dash")
    if "!" in text:
        problem(where, "contains an exclamation mark")
    if re.search(r"(?i)free", text):
        problem(where, 'contains "free" (the trial is "7 days on us")')
    for phrase in NOT_IN_1_0:
        hit = re.search(rf"(?i){phrase}", text)
        if hit:
            problem(where, f'promises "{hit.group(0)}", which Android 1.0 does not show')
    for hit in search_all(APPLE_WORDS, text):
        problem(where, f'names an Apple surface or brand: "{hit}"')
    for hit in search_all(OTHER_BRANDS, text):
        problem(where, f'names another company of Tom\'s: "{hit}"')
    for hit in search_all(HYPE, text):
        problem(where, f'hype or a store claim: "{hit}"')
    for word in BANNED_WORDS:
        hit = re.search(rf"(?i)\b{word}\b", text)
        if hit:
            problem(where, f'contains "{hit.group(0)}"')
    for name in MEDICINES:
        hit = re.search(rf"(?i)(?<![\w-]){re.escape(name)}(?![\w-])", text)
        if hit:
            problem(where, f'names the medicine "{hit.group(0)}"')
    for pattern in UK_SPELLINGS:
        hit = re.search(rf"(?i){pattern}", text)
        if hit:
            problem(where, f'UK spelling "{hit.group(0)}" in a US English listing')
    for word in re.findall(r"\b[A-Z]{3,}\b", text):
        if word not in ALLOWED_CAPS:
            problem(where, f'ALL CAPS "{word}"')
    for url in re.findall(r"https?://[^\s)]+", text):
        if url.rstrip(".,;") not in ALLOWED_URLS:
            problem(where, f"unexpected link {url}")
    emails = set(re.findall(r"[\w.+-]+@[\w-]+\.[\w.]+", text))
    if emails - {CONTACT_EMAIL}:
        problem(where, f"unexpected email address {sorted(emails - {CONTACT_EMAIL})}")


def words_in(patterns, text):
    hits = []
    for word in patterns:
        hits += [m.group(0) for m in re.finditer(rf"(?i)\b{word}\b", text)]
    return hits


def check_extras_out(where, text):
    """Voice to-dos and the Weight tab are extras: never in the title, the short description or the opening lines
    (REDESIGN.md "Extras policy, 2026-10-22", point 5, and "listed last in the description")."""
    for hit in words_in(WEIGHT_STEMS, text) + words_in(TODO_WORDS, text):
        problem(where, f'names an extra ("{hit}"); Taken is sold as the pill and supplement log')


def png_facts(raw, where):
    """Width, height, bit depth, colour type and whether it has alpha, from a PNG's chunks; every chunk's CRC checked."""
    if not raw.startswith(PNG_SIGNATURE):
        return None
    pos, kinds, header = 8, [], None
    while pos + 12 <= len(raw):
        length, kind = struct.unpack(">I4s", raw[pos:pos + 8])
        data = raw[pos + 8:pos + 8 + length]
        if pos + 12 + length > len(raw):
            problem(where, "the PNG is cut short")
            return None
        (crc,) = struct.unpack(">I", raw[pos + 8 + length:pos + 12 + length])
        if zlib.crc32(kind + data) & 0xFFFFFFFF != crc:
            problem(where, f"the PNG's {kind.decode('latin-1')} chunk is damaged")
            return None
        kinds.append(kind)
        if kind == b"IHDR":
            header = struct.unpack(">IIBB", data[:10])
        pos += 12 + length
        if kind == b"IEND":
            break
    if header is None or kinds[0] != b"IHDR" or kinds[-1] != b"IEND":
        problem(where, "not a whole PNG (IHDR first, IEND last)")
        return None
    width, height, depth, colour = header
    return {"format": "PNG", "size": (width, height), "depth": depth, "colour": colour,
            "alpha": colour in (4, 6) or b"tRNS" in kinds}


def jpeg_facts(raw, where):
    """Width, height and components from a JPEG's frame header (SOF0 to SOF15, not DHT, JPG or DAC)."""
    if not raw.startswith(b"\xff\xd8"):
        return None
    pos = 2
    while pos + 4 <= len(raw):
        if raw[pos] != 0xFF:
            break
        marker = raw[pos + 1]
        (length,) = struct.unpack(">H", raw[pos + 2:pos + 4])
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            height, width, components = struct.unpack(">HHB", raw[pos + 5:pos + 10])
            return {"format": "JPEG", "size": (width, height), "depth": raw[pos + 4], "colour": components,
                    "alpha": components == 4}
        pos += 2 + length
    problem(where, "a JPEG without a frame header")
    return None


def image_facts(path, where):
    raw = path.read_bytes()
    if raw.startswith(PNG_SIGNATURE):
        facts = png_facts(raw, where)
    elif raw.startswith(b"\xff\xd8"):
        facts = jpeg_facts(raw, where)
    else:
        problem(where, "neither a PNG nor a JPEG")
        return None
    if facts is not None:
        facts["bytes"] = len(raw)
        facts["raw"] = raw
    return facts


def no_alpha(where, facts):
    """Google's "JPEG or 24-bit PNG (no alpha)": 8-bit RGB without a transparency chunk, or an RGB JPEG."""
    if facts["format"] == "PNG" and not (facts["depth"] == 8 and facts["colour"] == 2 and not facts["alpha"]):
        problem(where, f"must be a 24-bit PNG with no alpha (bit depth {facts['depth']}, colour type {facts['colour']}"
                       + (", has alpha" if facts["alpha"] else "") + ")")
    if facts["format"] == "JPEG" and facts["colour"] != 3:
        problem(where, f"a JPEG with {facts['colour']} components; Play takes RGB")


graphics = []


def check_images(folder, locale):
    images = folder / "images"
    shots = images / "phoneScreenshots"
    files = sorted(p for p in shots.iterdir() if p.name != ".gitkeep") if shots.is_dir() else []
    where = f"{locale}/images/phoneScreenshots"
    if not SCREENSHOTS_MIN <= len(files) <= SCREENSHOTS_MAX:
        problem(where, f"{len(files)} screenshots; the set is {SCREENSHOTS_MIN} to {SCREENSHOTS_MAX}")
    names = [p.name for p in files]
    stems = sorted(p.stem for p in files)
    if stems != [str(n) for n in range(1, len(files) + 1)]:
        problem(where, f"must be named 1 to {len(files)} in Play's order, found {names}")
    if (shots / ".gitkeep").exists() and files:
        problem(f"{where}/.gitkeep", "no longer needed once the screenshots are there")
    for path in files:
        w = f"{where}/{path.name}"
        facts = image_facts(path, w)
        if not facts:
            continue
        no_alpha(w, facts)
        width, height = facts["size"]
        short, long = min(width, height), max(width, height)
        if short < SCREENSHOT_MIN_SIDE or long > SCREENSHOT_MAX_SIDE:
            problem(w, f"{width} x {height}; each side must be {SCREENSHOT_MIN_SIDE} to {SCREENSHOT_MAX_SIDE} px")
        if long > 2 * short:
            problem(w, f"{width} x {height}; the long side may be at most twice the short")
        if width * 16 != height * 9 or width < PROMOTION_MIN_SIDE:
            problem(w, f"{width} x {height}; the set is 9:16 portrait at 1080 x 1920 or larger, as promotion needs")
        graphics.append(f"{w}: {width} x {height}, {facts['format']} {facts['depth']}-bit colour type {facts['colour']}, "
                        f"{facts['bytes']} bytes")
        if ARGS.rendered is not None:
            fresh = ARGS.rendered / path.name
            if not fresh.is_file():
                problem(w, f"the app drew no {fresh}")
            elif fresh.read_bytes() != facts["raw"]:
                problem(w, f"is not what the app draws now; copy {path.name} from the android-screenshots artifact "
                           f"(play/phoneScreenshots) into {where}, after looking at it")
    if ARGS.rendered is not None and ARGS.rendered.is_dir():
        extra = sorted(p.name for p in ARGS.rendered.iterdir() if p.name not in names)
        if extra:
            problem(where, f"the app draws {extra} too, which are not committed")
    elif ARGS.rendered is not None:
        problem(where, f"no rendered screenshots in {ARGS.rendered}")

    feature = [p for p in images.glob("featureGraphic.*")]
    if len(feature) != 1:
        problem(f"{locale}/images/featureGraphic", f"needs exactly one feature graphic, found {len(feature)}")
    for path in feature:
        w = f"{locale}/images/{path.name}"
        facts = image_facts(path, w)
        if facts:
            no_alpha(w, facts)
            if facts["size"] != FEATURE_SIZE:
                problem(w, "{} x {}; must be 1024 x 500".format(*facts["size"]))
            graphics.append(f"{w}: {facts['size'][0]} x {facts['size'][1]}, {facts['format']} {facts['depth']}-bit "
                            f"colour type {facts['colour']}, {facts['bytes']} bytes")

    icon = images / "icon.png"
    w = f"{locale}/images/icon.png"
    if not icon.is_file():
        problem(w, "missing")
    else:
        facts = image_facts(icon, w)
        if facts:
            if facts["format"] != "PNG" or facts["depth"] != 8 or facts["colour"] != 6:
                problem(w, "must be a 32-bit PNG (8-bit RGBA)")
            if facts["size"] != ICON_SIZE:
                problem(w, "{} x {}; must be 512 x 512".format(*facts["size"]))
            if facts["bytes"] > ICON_MAX_BYTES:
                problem(w, f"{facts['bytes']} bytes; at most 1024 KB")
            if not PLAY_ICON.is_file() or facts["raw"] != PLAY_ICON.read_bytes():
                problem(w, f"must be {PLAY_ICON.relative_to(ANDROID)} byte for byte (brand/play.py copies it)")
            graphics.append(f"{w}: {facts['size'][0]} x {facts['size'][1]}, PNG {facts['depth']}-bit colour type "
                            f"{facts['colour']}, {facts['bytes']} bytes")


counts = {}
for locale in LOCALES:
    folder = PLAY / locale
    values = {}
    for field, limit in LIMITS.items():
        where = f"{locale}/{field}"
        text = read(folder / f"{field}.txt", where)
        values[field] = text
        counts[where] = (len(text), limit)
        if len(text) > limit:
            problem(where, f"{len(text)} characters, limit {limit}")
        if not text:
            problem(where, "empty")
    for path in sorted(folder.glob("*")):
        if path.is_file() and path.stem not in set(LIMITS) | OPTIONAL_FIELDS:
            problem(f"{locale}/{path.name}", "not a file supply reads")

    title, short, full = values["title"], values["short_description"], values["full_description"]

    # Title and short description: one line, Taken's name first, no promotion, no extras.
    for field, text in [("title", title), ("short_description", short)]:
        where = f"{locale}/{field}"
        copy_rules(where, text)
        if "\n" in text:
            problem(where, "more than one line")
        for hit in search_all(TITLE_ONLY, text):
            problem(where, f'promotional or program word "{hit}"')
        if PRICE.search(text):
            problem(where, "shows a price")
        check_extras_out(where, text)
    if not title.startswith("Taken"):
        problem(f"{locale}/title", 'must start with "Taken"')
    if re.search(r"[^\w\s:&'.,]", title):
        problem(f"{locale}/title", "special characters beyond a colon and an ampersand")
    if not re.search(r"(?i)\bpill", title + " " + short):
        problem(f"{locale}/title", "neither the title nor the short description says pill")

    # Full description.
    where = f"{locale}/full_description"
    copy_rules(where, full)
    paragraphs = full.split("\n\n")

    # The opening lines Play shows first sell the log, never an extra.
    for paragraph in paragraphs[:3]:
        check_extras_out(f"{where} (first three paragraphs)", paragraph)

    # The Weight tab is never in the description, as on the iPhone.
    for hit in words_in(WEIGHT_STEMS, full):
        problem(where, f'weight word "{hit}"; the Weight tab stays out of the listing')

    # Not the short description again.
    if short and short.lower() in full.lower():
        problem(where, "repeats the short description")
    for sentence in re.findall(r"[^.?]+[.?]", short):
        sentence = sentence.strip()
        if len(sentence) >= 20 and sentence.lower() in full.lower():
            problem(where, f'repeats the short description\'s sentence "{sentence}"')

    # Health disclaimer and privacy policy (Health Content and Services).
    for sentence in DISCLAIMERS:
        if sentence not in full:
            problem(where, f'lacks the health disclaimer sentence "{sentence}"')
    if PRIVACY_URL not in full:
        problem(where, f"lacks the privacy policy link {PRIVACY_URL}")
    if TERMS_URL not in full:
        problem(where, f"lacks the Terms of Use link {TERMS_URL}")
    if PRICE.search(full):
        problem(where, f'shows a price: "{PRICE.search(full).group(0)}"')

    # Taken Pro's terms (Subscriptions policy), and voice to-dos as the last feature, right before it.
    pro_at = [i for i, p in enumerate(paragraphs) if p.split("\n", 1)[0] == PRO_HEADING]
    todo_at = [i for i, p in enumerate(paragraphs) if p.split("\n", 1)[0] == TODO_HEADING]
    if len(pro_at) != 1:
        problem(where, f'needs exactly one paragraph headed "{PRO_HEADING}", found {len(pro_at)}')
    else:
        pro = paragraphs[pro_at[0]]
        for phrase, why in PRO_PHRASES.items():
            if phrase not in pro:
                problem(where, f'Taken Pro paragraph lacks "{phrase}" ({why})')
        if len(todo_at) > 1:
            problem(where, f'more than one "{TODO_HEADING}" paragraph')
        for i in todo_at:
            if i != pro_at[0] - 1:
                problem(where, f'the "{TODO_HEADING}" paragraph must come right before "{PRO_HEADING}"; extras are '
                               "listed last")

    # Release notes.
    changelogs = sorted((folder / "changelogs").glob("*")) if (folder / "changelogs").is_dir() else []
    if not any(p.name == "default.txt" for p in changelogs):
        problem(f"{locale}/changelogs", "no default.txt")
    for path in changelogs:
        where = f"{locale}/changelogs/{path.name}"
        if not re.fullmatch(r"(default|\d+)\.txt", path.name):
            problem(where, "must be default.txt or <versionCode>.txt")
            continue
        text = read(path, where)
        copy_rules(where, text)
        counts[where] = (len(text), CHANGELOG_LIMIT)
        if len(text) > CHANGELOG_LIMIT:
            problem(where, f"{len(text)} characters, limit {CHANGELOG_LIMIT}")
        if PRICE.search(text):
            problem(where, "shows a price")

    # Images: only the names supply reads (the screenshot step fills them).
    images = folder / "images"
    if not images.is_dir():
        problem(f"{locale}/images", "missing")
    else:
        for path in sorted(images.iterdir()):
            name = f"{locale}/images/{path.name}"
            if path.is_dir():
                if path.name not in SCREENSHOT_FOLDERS:
                    problem(name, "not a screenshot folder supply reads")
                    continue
                for shot in path.iterdir():
                    if shot.name != ".gitkeep" and shot.suffix.lower() not in IMAGE_EXTENSIONS:
                        problem(f"{name}/{shot.name}", "not a PNG or JPEG")
            elif path.name != ".gitkeep" and (path.stem not in IMAGE_NAMES or path.suffix.lower() not in IMAGE_EXTENSIONS):
                problem(name, "not an image supply reads")
        check_images(folder, locale)

width = max(len(k) for k in counts)
for key, (n, limit) in counts.items():
    print(f"{key:<{width}}  {n:5d} / {limit} characters")
print(f"medicine names from Catalog.kt: {len(MEDICINES)}")
for line in graphics:
    print(line)
if ARGS.rendered is not None:
    print(f"phone screenshots compared with {ARGS.rendered}")
if problems:
    print("\nProblems:", file=sys.stderr)
    for p in problems:
        print(f"- {p}", file=sys.stderr)
    sys.exit(1)
print("Play metadata OK")
