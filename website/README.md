# tomlet website

The landing page for [tomlet](https://github.com/tylerbutler/tomlet), a
round-tripping TOML parser and writer for Gleam. Built with [Astro](https://astro.build).

## Develop

```sh
pnpm install
pnpm dev      # http://localhost:4321
```

## Build

```sh
pnpm build    # static output -> dist/
pnpm preview  # serve the built site locally
```

## Design

The visual system (omelette theme: yolk-yellow, cast-iron ink, eggshell) is
documented in the repo-root [`DESIGN.md`](../DESIGN.md), and the strategic brief
in [`PRODUCT.md`](../PRODUCT.md).

- Tokens and base styles: `src/styles/global.css`
- Page: `src/pages/index.astro`
- Components: `src/components/` (`Logo.astro`, `CodePanel.astro`)
- Fonts: Bricolage Grotesque + JetBrains Mono, self-hosted via Fontsource

### Social preview card

The Open Graph / Twitter card image at `public/og.png` (1200×630, rendered @2x)
is generated from the brand system — it shows a comment surviving an edit. The
meta tags live in `src/layouts/Layout.astro`. To regenerate after a brand or copy
change:

```sh
node scripts/generate-og.mjs
```

The script embeds the Fontsource fonts and rasterizes with the headless Chrome
that Puppeteer caches locally (`~/.cache/puppeteer`).

The output in `dist/` is fully static. Deployment is configured for **Netlify**
via [`netlify.toml`](../netlify.toml) at the repo root: it sets the build `base`
to `website/`, runs `pnpm build`, and publishes `dist/`. Point a Netlify site at
this repo and it deploys with no further setup.
