// Generates the social preview card at public/og.png (1200x630, rendered @2x).
//
// The card embodies the project's "the demo is the pitch" principle: it shows a
// comment surviving an edit, in the eggshell / yolk / skillet brand system.
//
// Run with: node scripts/generate-og.mjs
// Fonts are embedded from the installed @fontsource-variable packages so the
// render never races a network fetch.

import { readFileSync, writeFileSync, existsSync, unlinkSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve, join } from "node:path";
import { globSync } from "node:fs";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..");

function findFont(pkg, file) {
  const direct = join(root, "node_modules", pkg, "files", file);
  if (existsSync(direct)) return direct;
  const hits = globSync(
    join(root, "node_modules/.pnpm", `*/node_modules/${pkg}/files/${file}`),
  );
  if (hits.length) return hits[0];
  throw new Error(`Font not found: ${pkg}/${file}`);
}

function b64(path) {
  return readFileSync(path).toString("base64");
}

const bricolage = b64(
  findFont(
    "@fontsource-variable/bricolage-grotesque",
    "bricolage-grotesque-latin-wght-normal.woff2",
  ),
);
const mono = b64(
  findFont(
    "@fontsource-variable/jetbrains-mono",
    "jetbrains-mono-latin-wght-normal.woff2",
  ),
);

// Brand colors (committed hex, matching favicon.svg / DESIGN.md).
const c = {
  eggshell: "#f7eede",
  shell2: "#f1e4cd",
  shellLine: "#e6d6b8",
  ink: "#2c2620",
  inkSoft: "#5b5347",
  yolk: "#f6c83b",
  yolkDeep: "#c87d28",
  paprika: "#d4541f",
  paprikaInk: "#bb471a",
  chive: "#5a8a3c",
  skillet: "#2a2420",
  skillet2: "#352e29",
  skilletLine: "#463e37",
  onSkillet: "#efe7d8",
  onSkilletSoft: "#b8ad9b",
};

const logo = `
<svg width="116" height="116" viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <path d="M5.5 31.5C5.5 17.8 16.4 8.5 24 8.5C31.6 8.5 42.5 17.8 42.5 31.5C42.5 34 40.4 35.6 37.2 35.6H10.8C7.6 35.6 5.5 34 5.5 31.5Z" fill="${c.yolk}" stroke="${c.ink}" stroke-width="2.4" stroke-linejoin="round"/>
  <path d="M11 27.5C16 23.5 20 25.5 24 25.5C28 25.5 32 23.5 37 27.5" stroke="${c.yolkDeep}" stroke-width="2.2" stroke-linecap="round"/>
  <circle cx="24" cy="19.5" r="4.1" fill="${c.paprika}" stroke="${c.ink}" stroke-width="2"/>
  <rect x="14.5" y="30.4" width="3.4" height="1.7" rx="0.85" fill="${c.chive}" transform="rotate(-18 14.5 30.4)"/>
  <rect x="29.5" y="31" width="3.4" height="1.7" rx="0.85" fill="${c.chive}" transform="rotate(22 29.5 31)"/>
</svg>`;

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<style>
@font-face {
  font-family: "Bricolage";
  src: url(data:font/woff2;base64,${bricolage}) format("woff2");
  font-weight: 200 800;
  font-display: block;
}
@font-face {
  font-family: "JBMono";
  src: url(data:font/woff2;base64,${mono}) format("woff2");
  font-weight: 100 800;
  font-display: block;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { width: 1200px; height: 630px; }
body {
  font-family: "Bricolage", system-ui, sans-serif;
  background: ${c.eggshell};
  color: ${c.ink};
  -webkit-font-smoothing: antialiased;
  position: relative;
  overflow: hidden;
}
/* warm yolk wash anchored top-left, fading into eggshell */
.wash {
  position: absolute; inset: 0;
  background:
    radial-gradient(120% 130% at -8% -20%, ${c.yolk} 0%, ${c.yolk} 16%, rgba(246,200,59,0) 52%);
  opacity: 0.5;
}
.frame {
  position: absolute; inset: 0;
  border: 14px solid ${c.ink};
}
.grid {
  position: absolute; inset: 0;
  display: grid;
  grid-template-columns: 1fr 1fr;
  align-items: center;
  gap: 56px;
  padding: 70px 72px;
}
/* ---- left: brand + headline + install ---- */
.left { display: flex; flex-direction: column; gap: 26px; }
.brand { display: flex; align-items: center; gap: 20px; }
.brand .word {
  font-weight: 800;
  font-size: 76px;
  letter-spacing: -0.03em;
  line-height: 1;
}
.kicker {
  font-family: "JBMono", monospace;
  font-weight: 600;
  font-size: 20px;
  letter-spacing: 0.01em;
  color: ${c.paprikaInk};
  text-transform: none;
}
.headline {
  font-weight: 800;
  font-size: 62px;
  line-height: 1.02;
  letter-spacing: -0.035em;
  margin-top: 4px;
}
.headline .hl {
  color: ${c.paprika};
  position: relative;
  white-space: nowrap;
}
.headline .hl::after {
  content: "";
  position: absolute;
  left: 0; right: 0; bottom: 0.04em;
  height: 0.14em;
  background: ${c.yolk};
  z-index: -1;
  border-radius: 2px;
}
.install {
  align-self: flex-start;
  display: inline-flex;
  align-items: center;
  gap: 14px;
  background: ${c.skillet};
  color: ${c.onSkillet};
  font-family: "JBMono", monospace;
  font-weight: 600;
  font-size: 26px;
  padding: 16px 26px;
  border-radius: 999px;
  margin-top: 8px;
}
.install .p { color: ${c.yolk}; }
/* ---- right: skillet code card (the demo) ---- */
.card {
  background: ${c.skillet};
  border-radius: 22px;
  border: 1px solid ${c.skilletLine};
  box-shadow: 0 26px 60px rgba(44,38,32,0.30);
  overflow: hidden;
  font-family: "JBMono", monospace;
}
.card__bar {
  display: flex; align-items: center; gap: 16px;
  padding: 18px 24px;
  background: ${c.skillet2};
  border-bottom: 1px solid ${c.skilletLine};
}
.dots { display: flex; gap: 9px; }
.dots i { width: 13px; height: 13px; border-radius: 50%; display: block; }
.card__name {
  margin-left: 4px;
  color: ${c.onSkilletSoft};
  font-size: 19px;
  font-weight: 500;
}
.card__chip {
  margin-left: auto;
  display: inline-flex; align-items: center; gap: 9px;
  font-size: 16px; font-weight: 600;
  color: ${c.eggshell};
  background: rgba(90,138,60,0.22);
  border: 1px solid ${c.chive};
  padding: 7px 14px; border-radius: 999px;
}
.card__chip b { width: 9px; height: 9px; border-radius: 2px; background: ${c.chive}; display: block; }
.code {
  padding: 30px 30px 32px;
  font-size: 21px;
  line-height: 1.6;
  white-space: pre;
}
.code .row { display: block; position: relative; }
.kept { padding-left: 16px; }
.kept::before {
  content: "";
  position: absolute; left: 0; top: 0.26em; bottom: 0.26em;
  width: 4px; border-radius: 2px;
  background: ${c.chive};
}
.com { color: #cfc6b4; }
.key { color: ${c.paprika}; filter: brightness(1.3) saturate(0.95); }
.eq  { color: ${c.onSkilletSoft}; }
.str { color: ${c.yolk}; }
.edit { color: ${c.onSkilletSoft}; display: flex; align-items: center; gap: 12px; }
.edit .fn { color: #f0a23a; }
.edit .str2 { color: ${c.yolk}; }
.edit .arrow { color: ${c.chive}; font-weight: 700; }
.sep {
  height: 1px; background: ${c.skilletLine};
  margin: 16px 0;
}
</style>
</head>
<body>
  <div class="wash"></div>
  <div class="grid">
    <div class="left">
      <div class="brand">${logo}<span class="word">tomlet</span></div>
      <div class="kicker">round-tripping TOML 1.0 · for Gleam</div>
      <h1 class="headline">TOML that keeps<br/>your <span class="hl">comments.</span></h1>
      <div class="install"><span class="p">$</span> gleam add tomlet</div>
    </div>

    <div class="card">
      <div class="card__bar">
        <div class="dots"><i style="background:#e5694a"></i><i style="background:#f6c83b"></i><i style="background:#7faa55"></i></div>
        <span class="card__name">config.toml</span>
        <span class="card__chip"><b></b>comments preserved</span>
      </div>
      <div class="code"><span class="row kept com"># the user's favorite snack</span>
<span class="row"><span class="key">snack</span> <span class="eq">=</span> <span class="str">"tomato"</span></span>
<div class="sep"></div><div class="edit"><span class="arrow">→</span><span><span class="fn">tomlet.set_string</span>(doc, …)</span></div>
<div class="sep"></div><span class="row kept com"># the user's favorite snack</span>
<span class="row"><span class="key">snack</span> <span class="eq">=</span> <span class="str">"tomato sandwich"</span></span></div>
    </div>
  </div>
  <div class="frame"></div>
</body>
</html>`;

const tmpHtml = join(root, "public", "_og-card.html");
writeFileSync(tmpHtml, html);

const chrome = globSync(
  join(
    process.env.HOME,
    ".cache/puppeteer/chrome-headless-shell/*/chrome-headless-shell-*/chrome-headless-shell",
  ),
).sort();
if (!chrome.length) {
  throw new Error("chrome-headless-shell not found in ~/.cache/puppeteer");
}
const bin = chrome[chrome.length - 1];

const out = join(root, "public", "og.png");
execFileSync(
  bin,
  [
    "--headless",
    "--disable-gpu",
    "--hide-scrollbars",
    "--no-sandbox",
    "--force-device-scale-factor=2",
    "--window-size=1200,630",
    `--screenshot=${out}`,
    `file://${tmpHtml}`,
  ],
  { stdio: "inherit" },
);

unlinkSync(tmpHtml);
console.log(`Wrote ${out}`);
