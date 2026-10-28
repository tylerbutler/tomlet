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

## Deploy

Deploy the static site to Cloudflare Workers with
[`wrangler.jsonc`](./wrangler.jsonc). Run these commands from `website/`:

```sh
pnpm exec wrangler login
pnpm run deploy              # build and deploy
pnpm run deploy --dry-run    # build and validate without deploying
```

Wrangler serves `dist/` as static assets without Worker code or an Astro
adapter. `public/_headers` sets a one-year cache lifetime for fingerprinted
Astro assets.

For automatic deployments, connect this repository in Cloudflare Workers
Builds with these settings:

| Setting | Value |
| --- | --- |
| Worker name | `tomlet` |
| Production branch | `main` |
| Root directory | `website` |
| Build command | `pnpm build` |
| Deploy command | `pnpm exec wrangler deploy` |
| Node.js version (`NODE_VERSION`) | `22` |

Cloudflare reads the pnpm version from `packageManager` in `package.json`.

The configured custom domain is `tomlet.tylerbutler.com`. The Cloudflare
account must have an active zone for `tylerbutler.com`. At cutover, remove
any existing Netlify CNAME record for this hostname before you deploy;
Wrangler creates the custom domain and its DNS record. Verify the site on
Cloudflare before you disable Netlify deployments.
