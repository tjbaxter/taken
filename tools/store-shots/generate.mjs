// Taken App Store screenshots, step 1 of 2: drives store-frame.html once per frame (frames.mjs) in Playwright's
// Chromium and saves each frame at 2x (2640 x 5736). finish.py (step 2) downsamples them with Lanczos to the
// store size, 1320 x 2868 RGB. .github/workflows/store-shots.yml runs both on a GitHub runner, never on a Mac.
//
//   RAW=<raw screens dir> OUT=<2x dir> PLAYWRIGHT=<.../playwright/index.mjs> node tools/store-shots/generate.mjs
//   optional: ONLY=03 (frames whose file starts with it), SCREEN_MAP='{"day":"Day sheet.png"}'
//
// RAW holds the app's own simulator captures: the "screenshots" artifact of ci.yml, or store/placeholder until
// that exists. A frame names a state (today, today-done, add, day, log, settings) and takes the file whose name
// is that state, optionally behind a prefix ("03-add.png", "iPhone 17 Pro Max - add.png"); SCREEN_MAP overrides.
// RAW may hold one folder per ci.yml run, named "<order>-<run id>": a state takes the first run's capture, and
// falls back to the next run's when that capture is missing or blank (a screen that failed to draw).

import fs from "node:fs";
import { mkdir, readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { basename, dirname, extname, join, relative } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, "../..");
const RAW = process.env.RAW;
const OUT = process.env.OUT;
if (!RAW || !OUT) throw new Error("set RAW (raw screens dir) and OUT (2x output dir)");
const ONLY = process.env.ONLY || "";
const MAP = JSON.parse(process.env.SCREEN_MAP || "{}");
// DEMO_DATE=YYYY-MM-DD, the day ci.yml took the captures: the drawn Lock Screen shows it, as the app's top bar does
const DEMO_DATE = /^\d{4}-\d{2}-\d{2}$/.test(process.env.DEMO_DATE || "") ? process.env.DEMO_DATE : "";
const longDate = (iso) =>
  new Date(`${iso}T12:00:00Z`).toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", timeZone: "UTC" }).replace(/,/g, "");
const pw = process.env.PLAYWRIGHT ? pathToFileURL(process.env.PLAYWRIGHT).href : "playwright";
const { chromium } = await import(pw);
const { FRAMES, specFor } = await import(pathToFileURL(join(HERE, "frames.mjs")).href);

function pngs(dir) {
  const out = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...pngs(p));
    else if (/\.png$/i.test(e.name)) out.push(p);
  }
  return out.sort();
}
// one group of captures per run folder ("1-<id>", "2-<id>" ...), in order; loose files make one group
const RUNS = fs.readdirSync(RAW, { withFileTypes: true }).filter((e) => e.isDirectory() && /^\d+-/.test(e.name))
  .map((e) => e.name).sort((a, b) => parseInt(a, 10) - parseInt(b, 10));
const GROUPS = RUNS.length ? RUNS.map((d) => pngs(join(RAW, d))) : [pngs(RAW)];
const norm = (f) => basename(f, extname(f)).toLowerCase().trim().replace(/[\s_]+/g, "-");
const bare = (s) => s.replace(/[^a-z0-9]/g, "");
function matchIn(files, name) {
  if (MAP[name]) return files.filter((f) => basename(f) === MAP[name] || relative(RAW, f) === MAP[name]).slice(0, 1);
  const tiers = [
    (f) => norm(f) === name,
    (f) => norm(f).endsWith(`-${name}`),
    (f) => bare(norm(f)) === bare(name),
    (f) => bare(norm(f)).endsWith(bare(name)),
  ];
  for (const t of tiers) {
    const hits = files.filter(t);
    if (hits.length === 1) return hits;
    if (hits.length > 1) throw new Error(`"${name}" matches ${hits.map((f) => basename(f)).join(", ")}: set SCREEN_MAP`);
  }
  return [];
}
// every run's capture of a state, first run first
function candidates(name) {
  const out = GROUPS.flatMap((files) => matchIn(files, name));
  if (!out.length) {
    const have = GROUPS.flat().map((f) => relative(RAW, f)).join(", ") || "nothing";
    throw new Error(`no raw screen for "${name}" in ${RAW} (have: ${have})`);
  }
  return out;
}

const ICON = [join(ROOT, "Taken/Assets.xcassets/AppIcon.appiconset/AppIcon.png"), join(ROOT, "brand/icon-1024.png")].find((p) => fs.existsSync(p));
const TYPES = { ".html": "text/html; charset=utf-8", ".png": "image/png" };
const served = new Map(); // url path -> file
const server = createServer(async (req, res) => {
  const url = decodeURIComponent(new URL(req.url, "http://x").pathname);
  const path = url === "/" || url === "/frame.html" ? join(HERE, "store-frame.html") : url === "/icon.png" ? ICON : served.get(url);
  if (!path) { res.writeHead(404).end(); return; }
  try {
    res.writeHead(200, { "content-type": TYPES[extname(path).toLowerCase()] || "application/octet-stream", "cache-control": "no-store" }).end(await readFile(path));
  } catch {
    res.writeHead(404).end();
  }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const base = `http://127.0.0.1:${server.address().port}`;
await mkdir(OUT, { recursive: true });

// software WebGL on a runner with no GPU
const browser = await chromium.launch({ headless: true, args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"] });
const report = [];
let failed = false;
try {
  for (const f of FRAMES) {
    if (ONLY && !f.file.startsWith(ONLY)) continue;
    const spec = specFor(f);
    const ctx = await browser.newContext({ viewport: { width: spec.w, height: spec.h }, deviceScaleFactor: 2 });
    const page = await ctx.newPage();
    page.on("console", (m) => m.type() === "error" && console.error(`page ${f.file}:`, m.text()));
    page.on("pageerror", (e) => console.error(`pageerror ${f.file}:`, e.message));
    await page.goto(`${base}/frame.html`, { waitUntil: "networkidle" });
    await page.waitForFunction(() => window.READY === true, null, { timeout: 60000 });
    if (spec.screen.kind === "capture") {
      let file = null;
      for (const c of candidates(spec.screen.name)) {
        const url = `/raw/${encodeURIComponent(relative(RAW, c))}`;
        served.set(decodeURIComponent(url), c); // the server looks paths up decoded
        if (!(await page.evaluate((u) => window.FRAME.isBlank(u), url))) { file = { c, url }; break; }
        console.error(`${f.file}: ${relative(RAW, c)} is blank, trying the next run`);
      }
      if (!file) { console.error(`${f.file}: every capture of "${spec.screen.name}" is blank`); failed = true; await ctx.close(); continue; }
      spec.screen = { ...spec.screen, src: file.url, file: relative(RAW, file.c) };
    } else if (spec.screen.kind === "lock") {
      spec.screen = { ...spec.screen, icon: "/icon.png" };
      if (DEMO_DATE) spec.screen.date = longDate(DEMO_DATE);
    }
    const info = await page.evaluate((sp) => window.FRAME.draw(sp), spec);
    if (!info.fontOk) { console.error(`${f.file}: Geist, Geist Mono or Inter did not load`); failed = true; }
    if (info.clearance < 40) { console.error(`${f.file}: the phone comes within ${info.clearance}px of the caption`); failed = true; }
    if (info.phone.x0 < 0 || info.phone.x1 > spec.w) { console.error(`${f.file}: the phone runs off the side (${info.phone.x0} to ${info.phone.x1})`); failed = true; }
    await page.screenshot({ path: join(OUT, f.file), clip: { x: 0, y: 0, width: spec.w, height: spec.h }, type: "png" });
    report.push({ file: f.file, key: f.key, screen: spec.screen.kind === "capture" ? spec.screen.file : spec.screen.kind, ...info });
    await ctx.close();
  }
} finally {
  await browser.close();
  server.close();
}
for (const r of report) console.log(JSON.stringify(r));
fs.writeFileSync(join(OUT, "report.json"), JSON.stringify(report, null, 2));
if (failed) process.exit(1);
