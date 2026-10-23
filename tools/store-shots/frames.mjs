// Taken's App Store sets (iPhone 6.9", 1320 x 2868; finish.py also writes each at 6.3", 1206 x 2622): six frames, one
// message each, in Tom's voice, rendered once per set (REDESIGN.md "App Store pack for 1.1"):
// - en-US, for the English (U.S.) localization: the app run with -demo-stack us (generic medicine names, a
//   "Semaglutide · Weekly · Thu" row) and the Add sheet's chip grid on frame 03.
// - neutral, for every other localization and the primary language: -demo-stack neutral (a "Weekly shot" row and no
//   prescription-only medicine) and the type-ahead on frame 03 in place of the chip grid, which names medicines.
// Copy rules: no em or en dashes, never the word "free", no exclamation marks, at most one word lit in the signal
// colour (*word*). App Review Guidelines 2.3.7 and 2.3.14 and Apple's asset best practices: no prices, no discounts,
// no website URLs, no unverifiable claims, no awards; 2.3.8: suitable for 4+. No brand names, no "GLP-1", "jab",
// "pen" or weight words, in any set. Every frame names the app's own simulator capture it shows (ci.yml,
// scripts/screenshots.sh writes each set to store/<us|neutral>/); the Lock Screen is the one screen the composer draws
// (SPEC 3.5 and 3.6).

const LAYOUT = {
  w: 1320,
  h: 2868,
  bg: "#08090A",
  headColor: "#F4F4F5",
  subColor: "#A1A1AA",
  acc: "#FFB000",
  top: 168,
  headSize: 150,
  headTrack: -0.045,
  subSize: 60,
  gap: 34,
  headMax: 1220,
  subMax: 1180,
  screenW: 990,
  phoneTop: 700,
  // a dark titanium body: the studio softboxes draw its edges against the black
  finish: "#38393d",
  rough: 0.28,
  envi: 1.25,
  glow: { a: 0.15, r: 0.92, stretch: 1.25 },
  // No viewfinder brackets in the corners: 1.1's calmer look took the HUD decals out of the app (REDESIGN.md,
  // "Simpler visual language"), so the frames lose them too. A frame may still ask for them with `hud`.
};

// One pose per frame, never one pose for the set (Tom, 2026-09-30: "the phone needs to be in different angles
// ... look at Flair"): turned left, turned right, laid back, rolled, rolled the other way, upright and whole.
const POSE = {
  hero: { ry: 0.24, rx: 0.06, rz: 0.05 },
  right: { ry: -0.42, rx: 0.07, rz: -0.1 },
  laidBack: { ry: -0.08, rx: -0.42, rz: 0.03 },
  rollLeft: { ry: 0.16, rx: 0.05, rz: 0.13 },
  rollRight: { ry: -0.22, rx: 0.06, rz: -0.17 },
  upright: { ry: 0.14, rx: 0.02, rz: 0.0 },
};

const cap = (name) => ({ kind: "capture", name });

// Each set: the -demo-stack it is captured with (its folder in the ci.yml artifact, screenshots/store/<stack>), and how
// iOS writes the date and the time on its Lock Screen for that storefront's people (12-hour in the U.S., 24-hour in
// most of the world).
export const SETS = {
  "en-US": { stack: "us", dateLocale: "en-US", clock12: true },
  neutral: { stack: "neutral", dateLocale: "en-GB", clock12: false },
};

// The drawn Lock Screen: the evening nudge over the app's own Lock Screen widgets, on the demo day ci.yml captures
// (Shared/DemoData.swift, a Thursday: Vitamin D3, the weekly row, Fish Oil twice, Creatine and Magnesium due, and
// Finasteride in the U.S. set; everything but Fish Oil's second dose and Magnesium in by morning, so FSH and MAG are
// pending). The widgets are TakenWidgets' own accessory families as iOS draws them on a Lock Screen: monochrome.
// generate.mjs puts in the day the set's captures show (its demo-date.txt), written the way iOS writes it there.
// 20:00 is 1.1's default nudge time (waking at 07:00, plus 13 hours).
function lockFor(set) {
  const us = set === "en-US";
  return {
    kind: "lock",
    date: us ? "Thursday, October 15" : "Thursday 15 October",
    time: us ? "8:00" : "20:00",
    gauge: us ? { done: 5, due: 7 } : { done: 4, due: 6 },
    // the rectangular widget lists what is still to take first (Shared/WidgetViews.swift), three rows
    rows: [
      { code: "FSH", value: "1/2", done: false },
      { code: "MAG", value: "--:--", done: false },
      { code: "VD3", value: "07:42", done: true },
    ],
    title: "Taken",
    body: "2 pending: FSH, MAG",
    notifY: 616,
  };
}

// Frame 03: the U.S. set shows the chip grid (Semaglutide, Tirzepatide and the other medicine chips among them); the
// neutral set shows the type-ahead with "mag" typed, four Magnesium names and supplement chips only.
function stackFrame(set) {
  if (set === "en-US") {
    return { headline: "Your stack in *four* taps.", subline: "Quick-pick chips. No typing, no sign-up.", screen: cap("add") };
  }
  return { headline: "Your stack in *seconds.*", subline: "Type three letters. Taken spells the rest.", screen: cap("add-search") };
}

export function framesFor(set) {
  if (!SETS[set]) throw new Error(`unknown set "${set}" (have: ${Object.keys(SETS).join(", ")})`);
  return [
    {
      file: "01.png",
      key: "know",
      headLines: ["Did I take it?", "Know for *sure.*"],
      subline: "Every dose, logged to the minute.",
      ...POSE.hero,
      phoneTop: 820,
      screenW: 1010,
      screen: cap("today"),
    },
    {
      file: "02.png",
      key: "done",
      headline: "One tap. *Done.*",
      subline: "Log the whole stack at once.",
      ...POSE.right,
      phoneTop: 640,
      screen: cap("today-done"),
    },
    {
      file: "03.png",
      key: "stack",
      ...stackFrame(set),
      ...POSE.laidBack,
      phoneTop: 690,
      screenW: 1090,
    },
    {
      file: "04.png",
      key: "record",
      headline: "Every day, on *record.*",
      subline: "Forgot to log? Fix any day in a tap.",
      ...POSE.rollLeft,
      phoneTop: 680,
      screenW: 1000,
      screen: cap("day"),
    },
    {
      file: "05.png",
      key: "nudge",
      headline: "Nudges only when it *matters.*",
      subline: "Already done? Silence.",
      ...POSE.rollRight,
      phoneTop: 660,
      screenW: 920,
      screen: lockFor(set),
    },
    {
      // the log: five weeks lit, the streak, and the app's own footer: the log stays on this iPhone, no account, no
      // ads, no tracking
      file: "06.png",
      key: "private",
      headline: "*Nothing* leaves your phone.",
      subline: "No account. No ads. No tracking.",
      ...POSE.upright,
      phoneTop: 680,
      screenW: 900,
      screen: cap("log"),
    },
  ];
}

export function specFor(frame) {
  return { ...LAYOUT, ...frame, glow: { ...LAYOUT.glow, ...(frame.glow || {}) }, hud: frame.hud || null };
}
