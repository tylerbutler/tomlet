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

const logo = `<img class="logo" alt="tomlet" src="data:image/png;base64,${b64(join(root, "public", "tomlet-logo.png"))}" />`;

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
.brand .logo {
  height: 104px;
  width: auto;
  display: block;
  flex: none;
}
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
.edit { color: ${c.onSkilletSoft}; display: flex; align-items: center; gap: 12px; font-size: 17px; }
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
      <div class="kicker">TOML + omelette · round-trips TOML 1.1</div>
      <h1 class="headline">TOML that keeps<br/>your <span class="hl">comments.</span></h1>
      <div class="install"><span class="p">$</span> gleam add tomlet</div>
    </div>

    <div class="card">
      <div class="card__bar">
        <div class="dots"><i style="background:#e5694a"></i><i style="background:#f6c83b"></i><i style="background:#7faa55"></i></div>
        <span class="card__name">gleam.toml</span>
        <span class="card__chip"><b></b>comments preserved</span>
      </div>
      <div class="code"><span class="row kept com"># published to Hex on each tag</span>
<span class="row"><span class="key">version</span> <span class="eq">=</span> <span class="str">"1.2.0"</span></span>
<div class="sep"></div><div class="edit"><span class="arrow">→</span><span><span class="fn">tomlet.set_string</span>(doc, ["version"], …)</span></div>
<div class="sep"></div><span class="row kept com"># published to Hex on each tag</span>
<span class="row"><span class="key">version</span> <span class="eq">=</span> <span class="str">"1.3.0"</span></span></div>
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
