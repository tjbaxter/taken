#!/usr/bin/env python3
"""Checks Taken's App Store pack for 1.1 (store/SUBMISSION-1.1.md) against Apple's limits and the listing's own rules.
CI runs it (ci.yml, "Store metadata"); run it by hand with:  python3 scripts/check-store-metadata.py

Layout (fastlane deliver's file names, https://docs.fastlane.tools/actions/deliver/):
  store/metadata/<set>/{name,subtitle,promotional_text,description,keywords,release_notes,support_url,
                       marketing_url,privacy_url}.txt     one folder per set: en-US and neutral
  store/metadata/review_information/{notes,email_address}.txt
  store/iap/products.json                                  in-app purchase display names, descriptions, review notes
  tools/store-shots/frames.mjs                             the screenshot captions

Apple's limits, each from App Store Connect Help as of October 2026:
- name 2 to 30 characters, subtitle 30 (reference/app-information/app-information)
- promotional text 170, description 4000, What's New 4000 characters, keywords 100 bytes with each keyword more
  than two characters, App Review notes 4000 bytes (reference/app-information/platform-version-information)
- in-app purchase display name 2 to 30 characters, description 45, review notes 4000
  (reference/in-app-purchases-and-subscriptions/in-app-purchase-information)
- keywords: no word already in the name, subtitle or category, no plural of a word already there
  (https://developer.apple.com/app-store/search/)

The listing's rules (REDESIGN.md "Store screenshots for the 1.1 submission" and "App Store pack for 1.1"):
- Tom's copy rules everywhere: no em or en dashes, never the word "free", no exclamation marks.
- No brand names, "GLP-1", "jab", "pen" or weight words in any set, caption or in-app purchase text. Weight words
  match as stems from the start of a word ("weigh" finds weight, weighed and weigh-in). The one public exception is
  WEIGHT_LINE, which What's New in every set must carry (REDESIGN.md "Weight tab", Store, privacy and positioning);
  anywhere else, including the rest of What's New, a weight word fails. The App Review notes, which only Apple reads,
  must describe the Weight tab (Guideline 2.3.1(a)), so weight words are allowed there too.
- No set names a medicine or a price. Every medicine in Shared/Catalog.swift counts, with its other names: the
  medicines list and the medicine chips (CHIP_MEDICINES). Prices differ by storefront (Guideline 2.3.1(a) forbids
  promoting a false price) and most countries ban promoting prescription medicines. English (U.S.) is held to the same
  rule because it is also the Japan storefront's English (Apple's App Store localizations table lists Japan with
  Japanese and English (US)), and Japan bans promoting prescription medicines too.
- English (U.S.) uses US spelling; the neutral set avoids every word English spells two ways.
- Captions carry no price, discount, URL or copyright symbol (App Store asset best practices).
Exits 1 with every problem listed; prints each field's count against its limit.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "store" / "metadata"
SETS = ["en-US", "neutral"]
FIELDS = ["name", "subtitle", "promotional_text", "description", "keywords", "release_notes", "support_url",
          "marketing_url", "privacy_url"]
LIMITS = {"name": 30, "subtitle": 30, "promotional_text": 170, "description": 4000, "release_notes": 4000}
KEYWORD_BYTES = 100
NOTES_BYTES = 4000
CATEGORY_WORDS = {"health", "fitness"}

BRANDS = ["ozempic", "wegovy", "mounjaro", "zepbound", "rybelsus", "saxenda", "trulicity", "propecia", "proscar",
          "rogaine", "regaine", "glucophage", "yasmin", "microgynon"]
# "pen" and "jab" as whole words
BANNED_WORDS = [r"glp-?1", r"jabs?", r"pens?"]
# Weight words as stems, each from the start of a word: weigh finds weigh, weighs, weighed, weighing, weight, weights
# and weigh-in. "fat" and "lose" list their endings so fatigue and close never match.
WEIGHT_STEMS = [r"weigh\w*", r"slim\w*", r"fat(?:s|ty|ter|test|ten\w*)?", r"diet\w*", r"calor\w*", r"obes\w*",
                r"los(?:e|es|er|ers|ing|s|t)", r"pounds?", r"lbs?", r"kgs?", r"kilo\w*", r"bmi", r"waist\w*",
                r"bell(?:y|ies)", r"trim\w*", r"burn\w*"]
# The one weight line the store carries (REDESIGN.md "Weight tab", Store, privacy and positioning). What's New must
# list a new feature (Guideline 2.3.12) and is set per localization, so every set's What's New has it, word for word.
WEIGHT_LINE = ("New: an optional Weight tab. Log a weigh-in in a few taps and watch a smoothed trend form. "
               "Turn it on in Profile.")
APPROVED = {("en-US", "release_notes"): WEIGHT_LINE, ("neutral", "release_notes"): WEIGHT_LINE}
# The chips that are medicines, prescription-only in most storefronts (DemoDataTests.prescriptionOnly); every other
# chip is a supplement. Their other names come from Shared/Catalog.swift with the rest.
CHIP_MEDICINES = ["Melatonin", "Finasteride", "Minoxidil", "Birth Control", "Metformin", "Semaglutide", "Tirzepatide"]
UK_SPELLINGS = [r"colour", r"favourite", r"organis", r"personalis", r"customis", r"recognis", r"centre", r"licence",
                r"cancelled", r"cancelling", r"travelled", r"programme", r"\bmum\b", r"analyse", r"realis"]
US_SPELLINGS = [r"\bcolor", r"favorite", r"organiz", r"personaliz", r"customiz", r"recogniz", r"licens",
                r"\bcanceled", r"\bcanceling", r"traveled", r"\bmom\b", r"analyz", r"realiz"]
PRICE = re.compile(r"[$£€¥]\s?\d|\d+[.,]\d\d\s?(usd|gbp|eur)|\bper (month|year)\b.*\d", re.I)

problems = []


def problem(where, text):
    problems.append(f"{where}: {text}")


def read(path):
    if not path.is_file():
        problem(str(path.relative_to(ROOT)), "missing")
        return ""
    text = path.read_text(encoding="utf-8")
    if not text.endswith("\n") or text.endswith("\n\n"):
        problem(str(path.relative_to(ROOT)), "must end with exactly one newline")
    return text.rstrip("\n")


def catalog_medicines():
    """Every medicine Shared/Catalog.swift knows, with its other names (brands, UK names), lower case: the medicines
    list and the chips in CHIP_MEDICINES. Misspellings are left out; they are never shown."""
    source = (ROOT / "Shared" / "Catalog.swift").read_text(encoding="utf-8")

    def entries(name):
        block = re.search(rf"static let {name}: \[CatalogEntry\] = \[(.*?)\n    \]", source, re.S)
        if not block:
            problem("Shared/Catalog.swift", f"no {name} list; the parser no longer matches the file")
            return {}
        found = {}
        for chunk in block.group(1).split("CatalogEntry(")[1:]:
            entry = re.match(r'\s*"([^"]+)"', chunk)
            aliases = re.search(r"aliases:\s*\[([^\]]*)\]", chunk)
            if entry:
                found[entry.group(1)] = re.findall(r'"([^"]+)"', aliases.group(1)) if aliases else []
        return found

    chips = entries("chips")
    medicines = entries("medicines")
    for name in CHIP_MEDICINES:
        if name not in chips:
            problem("Shared/Catalog.swift", f'no chip "{name}" (CHIP_MEDICINES)')
        else:
            medicines[name] = chips[name]
    if len(medicines) < 100:
        problem("Shared/Catalog.swift", f"found only {len(medicines)} medicines; the parser no longer matches the file")
    names = set()
    for name, aliases in medicines.items():
        names.add(name.lower())
        names.update(alias.lower() for alias in aliases)
    return sorted(names)


MEDICINES = catalog_medicines()


def copy_rules(where, text, weight_ok=False):
    if re.search("[–—]", text):
        problem(where, "contains an en or em dash")
    if re.search(r"(?i)\bfree\b", text):
        problem(where, 'contains the word "free"')
    if "!" in text:
        problem(where, "contains an exclamation mark")
    lower = text.lower()
    for brand in BRANDS:
        if brand in lower:
            problem(where, f'names the brand "{brand}"')
    for word in BANNED_WORDS + ([] if weight_ok else WEIGHT_STEMS):
        hit = re.search(rf"(?i)\b{word}\b", text)
        if hit:
            problem(where, f'contains "{hit.group(0)}"')


def medicines(where, text):
    for name in MEDICINES:
        hit = re.search(rf"(?i)(?<![\w-]){re.escape(name)}(?![\w-])", text)
        if hit:
            problem(where, f'names the medicine "{hit.group(0)}"')


def spelling(where, text, banned, kind):
    # Control Center is Apple's own name for it in every English storefront
    text = text.replace("Control Center", "")
    for pattern in banned:
        hit = re.search(rf"(?i){pattern}", text)
        if hit:
            problem(where, f'{kind} spelling "{hit.group(0)}"')


counts = {}
values = {}
for set_name in SETS:
    values[set_name] = {}
    for field in FIELDS:
        path = META / set_name / f"{field}.txt"
        where = f"{set_name}/{field}"
        text = read(path)
        values[set_name][field] = text
        # The approved weight line is taken out before the rules run, so a weight word anywhere else in What's New
        # still fails.
        rest = text
        approved = APPROVED.get((set_name, field))
        if approved and approved in text:
            rest = text.replace(approved, "", 1)
        elif approved:
            problem(where, f'lacks the Weight tab line "{approved}" (Guideline 2.3.12)')
        copy_rules(where, rest)
        if field in LIMITS:
            n = len(text)
            counts[where] = (n, LIMITS[field], "characters")
            if n > LIMITS[field]:
                problem(where, f"{n} characters, limit {LIMITS[field]}")
        if field.endswith("_url"):
            if not re.fullmatch(r"https://\S+", text):
                problem(where, f"not one https URL: {text!r}")
        # Both sets: no medicine and no price (English (U.S.) is the Japan storefront's English too).
        medicines(where, text)
        if PRICE.search(text):
            problem(where, f'shows a price ("{PRICE.search(text).group(0)}"): prices differ by storefront')
        if set_name == "neutral":
            spelling(where, text, UK_SPELLINGS, "UK-only")
            spelling(where, text, US_SPELLINGS, "US-only")
        else:
            spelling(where, text, UK_SPELLINGS, "UK")
    if len(values[set_name]["name"]) < 2:
        problem(f"{set_name}/name", "shorter than 2 characters")

    # Keywords: 100 bytes, comma separated with no spaces around the commas, each more than two characters, none
    # repeating a word (or its plural) from the name, subtitle or category.
    keywords = values[set_name]["keywords"]
    where = f"{set_name}/keywords"
    size = len(keywords.encode("utf-8"))
    counts[where] = (size, KEYWORD_BYTES, "bytes")
    if size > KEYWORD_BYTES:
        problem(where, f"{size} bytes, limit {KEYWORD_BYTES}")
    words = keywords.split(",")
    if any(w != w.strip() or not w for w in words):
        problem(where, "spaces around a comma, or an empty keyword")
    taken_words = set(re.findall(r"[a-z]+", (values[set_name]["name"] + " " + values[set_name]["subtitle"]).lower()))
    taken_words |= CATEGORY_WORDS
    seen = set()
    for w in words:
        w = w.strip().lower()
        if len(w) <= 2:
            problem(where, f'"{w}" is two characters or fewer')
        for part in re.findall(r"[a-z0-9]+", w):
            stem = part[:-1] if part.endswith("s") and len(part) > 3 else part
            if part in taken_words or stem in taken_words or part + "s" in taken_words:
                problem(where, f'"{part}" repeats a word from the name, subtitle or category')
            if stem in seen:
                problem(where, f'"{part}" repeats another keyword')
            seen.add(stem)

# The name, subtitle, keywords and URLs are the same in both sets; only the copy differs.
for field in ["name", "subtitle", "keywords", "support_url", "marketing_url", "privacy_url"]:
    if values["en-US"][field] != values["neutral"][field]:
        problem(field, "differs between en-US and neutral")

# App Review notes: 4000 bytes; the founding member rule, the sandbox paywall, on-device voice to-dos, Shortcuts, the
# trial reminder, the Weight tab (its Profile switch, weights.json and the goal's floor), Guideline 2.5.19 and the one
# contact address must each be in them. Only Apple reads them, so weight words are allowed here.
notes = read(META / "review_information" / "notes.txt")
copy_rules("review notes", notes, weight_ok=True)
size = len(notes.encode("utf-8"))
counts["review_information/notes"] = (size, NOTES_BYTES, "bytes")
if size > NOTES_BYTES:
    problem("review notes", f"{size} bytes, limit {NOTES_BYTES}")
for needle in ["Founding members", "originalAppVersion", "sandbox", "Foundation Models", "on device", "Shortcuts",
               "3 days before the trial ends", "Weight", "Profile", "weights.json", "BMI 18.5", "2.5.19",
               "tjpb2@cantab.ac.uk"]:
    if needle not in notes:
        problem("review notes", f'does not mention "{needle}"')
emails = set(re.findall(r"[\w.+-]+@[\w-]+\.[\w.]+", notes))
if emails != {"tjpb2@cantab.ac.uk"}:
    problem("review notes", f"contact must be tjpb2@cantab.ac.uk only, found {sorted(emails)}")
email = read(META / "review_information" / "email_address.txt")
if email != "tjpb2@cantab.ac.uk":
    problem("review_information/email_address", f"must be tjpb2@cantab.ac.uk, found {email!r}")

# In-app purchases: display name 2 to 30 characters, description 45, review notes 4000; the three fixed product ids.
products_path = ROOT / "store" / "iap" / "products.json"
try:
    iap = json.loads(products_path.read_text(encoding="utf-8"))
except (OSError, ValueError) as error:
    problem("store/iap/products.json", f"unreadable: {error}")
    iap = {"products": [], "subscription_group": {}}
ids = [p.get("product_id") for p in iap["products"]]
want = ["com.tombaxter.taken.pro.yearly", "com.tombaxter.taken.pro.monthly", "com.tombaxter.taken.pro.lifetime"]
if ids != want:
    problem("iap", f"product ids {ids}, want {want} (PRO.md)")
group = iap.get("subscription_group", {}).get("display_name", "")
copy_rules("iap group", group)
if not 2 <= len(group) <= 30:
    problem("iap group", "display name must be 2 to 30 characters")
for p in iap["products"]:
    pid = p.get("product_id", "?")
    for key, low, high in [("display_name", 2, 30), ("description", 1, 45), ("review_notes", 1, 4000)]:
        text = p.get(key, "")
        copy_rules(f"{pid} {key}", text)
        medicines(f"{pid} {key}", text)
        counts[f"{pid.rsplit('.', 1)[-1]} {key}"] = (len(text), high, "characters")
        if not low <= len(text) <= high:
            problem(f"{pid} {key}", f"{len(text)} characters, allowed {low} to {high}")
    shot = ROOT / p.get("review_screenshot", "")
    if not shot.is_file():
        problem(f"{pid} review_screenshot", f"{shot} is missing")

# Captions: every headline and subline of every frame, in both sets.
frames = (ROOT / "tools" / "store-shots" / "frames.mjs").read_text(encoding="utf-8")
captions = re.findall(r'(?:headline|subline):\s*"([^"]*)"', frames)
captions += [line for block in re.findall(r"headLines:\s*\[([^\]]*)\]", frames)
             for line in re.findall(r'"([^"]*)"', block)]
if len(captions) < 12:
    problem("frames.mjs", f"found only {len(captions)} captions; the parser no longer matches the file")
for caption in captions:
    plain = caption.replace("*", "")
    copy_rules(f'caption "{plain}"', plain)
    medicines(f'caption "{plain}"', plain)
    if PRICE.search(plain) or re.search(r"https?://|www\.|\.com\b|©", plain):
        problem(f'caption "{plain}"', "has a price, URL or copyright symbol")

width = max(len(k) for k in counts)
for key, (n, limit, unit) in counts.items():
    print(f"{key:<{width}}  {n:5d} / {limit} {unit}")
print(f"captions checked: {len(captions)}; medicine names from Shared/Catalog.swift: {len(MEDICINES)}")
if problems:
    print("\nProblems:", file=sys.stderr)
    for p in problems:
        print(f"- {p}", file=sys.stderr)
    sys.exit(1)
print("store metadata OK")
