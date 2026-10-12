// Taken App Store screenshots, step 1 of 2: drives store-frame.html once per frame (frames.mjs) in Playwright's
// Chromium and saves each frame at 2x (2640 x 5736). finish.py (step 2) downsamples them with Lanczos to the
// store size, 1320 x 2868 RGB. .github/workflows/store-shots.yml runs both on a GitHub runner, never on a Mac.
//
//   RAW=<raw screens dir> OUT=<2x dir> PLAYWRIGHT=<.../playwright/index.mjs> node tools/store-shots/generate.mjs
//   optional: ONLY=03 (frames whose file starts with it), SCREEN_MAP='{"day":"Day sheet.png"}'
//
// RAW holds the app's own simulator captures: the "screenshots" artifact of ci.yml, or store/placeholder until
// that exists. A frame names a state (today, today-done, add, day, settings) and takes the file whose name is
// that state, optionally behind a prefix ("03-add.png", "iPhone 17 Pro Max - add.png"); SCREEN_MAP overrides.

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
const RAWS = pngs(RAW);
const norm = (f) => basename(f, extname(f)).toLowerCase().trim().replace(/[\s_]+/g, "-");
const bare = (s) => s.replace(/[^a-z0-9]/g, "");
function resolveScreen(name) {
  if (MAP[name]) {
    const hit = RAWS.find((f) => basename(f) === MAP[name] || relative(RAW, f) === MAP[name]);
    if (!hit) throw new Error(`SCREEN_MAP names ${MAP[name]} for "${name}", not in ${RAW}`);
    return hit;
  }
  const tiers = [
    (f) => norm(f) === name,
    (f) => norm(f).endsWith(`-${name}`),
    (f) => bare(norm(f)) === bare(name),
    (f) => bare(norm(f)).endsWith(bare(name)),
  ];
  for (const t of tiers) {
    const hits = RAWS.filter(t);
    if (hits.length === 1) return hits[0];
    if (hits.length > 1) throw new Error(`"${name}" matches ${hits.map((f) => basename(f)).join(", ")}: set SCREEN_MAP`);
  }
  throw new Error(`no raw screen for "${name}" in ${RAW} (have: ${RAWS.map((f) => basename(f)).join(", ") || "nothing"})`);
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
    if (spec.screen.kind === "capture") {
      const file = resolveScreen(spec.screen.name);
      const url = `/raw/${encodeURIComponent(spec.screen.name)}.png`;
      served.set(url, file);
      spec.screen = { ...spec.screen, src: url, file: relative(RAW, file) };
    } else if (spec.screen.kind === "lock") spec.screen = { ...spec.screen, icon: "/icon.png" };
    const ctx = await browser.newContext({ viewport: { width: spec.w, height: spec.h }, deviceScaleFactor: 2 });
    const page = await ctx.newPage();
    page.on("console", (m) => m.type() === "error" && console.error(`page ${f.file}:`, m.text()));
    page.on("pageerror", (e) => console.error(`pageerror ${f.file}:`, e.message));
    await page.goto(`${base}/frame.html`, { waitUntil: "networkidle" });
    await page.waitForFunction(() => window.READY === true, null, { timeout: 60000 });
    const info = await page.evaluate((sp) => window.FRAME.draw(sp), spec);
    if (!info.fontOk) { console.error(`${f.file}: Geist, Geist Mono or Inter did not load`); failed = true; }
    if (info.clearance < 40) { console.error(`${f.file}: the phone comes within ${info.clearance}px of the caption`); failed = true; }
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
