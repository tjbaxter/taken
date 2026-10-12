// Taken's App Store set (iPhone 6.9", 1320 x 2868): six frames, one message each, in Tom's voice. Copy rules: no
// em or en dashes, never the word "free", no exclamation marks, at most one word lit in the signal colour
// (*word*). Every frame names the app's own simulator capture it shows (ci.yml runs the app with
// -demo -screen <state>); the Lock Screen is the one screen the composer draws (SPEC 3.5 and 3.6).

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
  subSize: 58,
  gap: 34,
  headMax: 1220,
  subMax: 1060,
  screenW: 990,
  phoneTop: 700,
  // a dark titanium body: the studio softboxes draw its edges against the black
  finish: "#4a4b4f",
  rough: 0.28,
  envi: 1.25,
  glow: { a: 0.1, r: 0.5, stretch: 1.55 },
  hud: { color: "rgba(161,161,170,0.30)", weight: 3, inset: 56, arm: 46 },
};

// One pose per frame, never one pose for the set (Tom, 2026-09-30: "the phone needs to be in different angles
// ... look at Flair"): turned left, turned right, laid back, rolled, rolled the other way, upright and whole.
const POSE = {
  hero: { ry: 0.24, rx: 0.06, rz: 0.05 },
  right: { ry: -0.42, rx: 0.07, rz: -0.1 },
  laidBack: { ry: -0.12, rx: -0.42, rz: 0.03 },
  rollLeft: { ry: 0.18, rx: 0.05, rz: 0.19 },
  rollRight: { ry: -0.22, rx: 0.06, rz: -0.2 },
  upright: { ry: 0.14, rx: 0.02, rz: 0.0 },
};

const cap = (name) => ({ kind: "capture", name });

// The drawn Lock Screen: the evening nudge, with the widgets agreeing with it (one taken this morning, two pending).
const LOCK = {
  kind: "lock",
  date: "Monday 12 October",
  time: "21:00",
  done: 1,
  due: 3,
  rows: [{ code: "VD3", at: "07:42" }, { code: "FSH" }, { code: "FIN" }],
  title: "Taken",
  body: "2 pending: FSH, FIN",
  notifY: 676,
};

export const FRAMES = [
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
    headline: "Your stack in *four* taps.",
    subline: "Quick-pick chips. No typing, no sign-up.",
    ...POSE.laidBack,
    phoneTop: 700,
    screenW: 1040,
    screen: cap("add"),
  },
  {
    file: "04.png",
    key: "record",
    headline: "Every day, on *record.*",
    subline: "Forgot to log? Fix any day in a tap.",
    ...POSE.rollLeft,
    phoneTop: 660,
    screen: cap("day"),
  },
  {
    file: "05.png",
    key: "nudge",
    headline: "Nudges only when it *matters.*",
    subline: "Already done? Silence.",
    ...POSE.rollRight,
    phoneTop: 660,
    screenW: 840,
    screen: LOCK,
  },
  {
    file: "06.png",
    key: "private",
    headline: "*Nothing* leaves your phone.",
    subline: "No account. No ads. No tracking.",
    ...POSE.upright,
    phoneTop: 680,
    screenW: 900,
    screen: cap("settings"),
  },
];

export function specFor(frame) {
  return { ...LAYOUT, ...frame, glow: { ...LAYOUT.glow, ...(frame.glow || {}) }, hud: frame.hud === false ? null : { ...LAYOUT.hud, ...(frame.hud || {}) } };
}
