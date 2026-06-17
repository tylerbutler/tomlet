# Design

Visual system for the tomlet landing page. Brand register, omelette-themed.

## Theme

Warm breakfast-kitchen, committed yolk-yellow brand with cast-iron ink. Three
material "worlds" tied to the omelette motif: **eggshell** (the page),
**yolk** (the hero / brand drench), **skillet** (dark code panels). Black-on-yolk
energy — bold, cheerful, high-contrast — and deliberately the opposite of the
navy/purple gradient SaaS landing it must not resemble. Light mode is the
identity; the page reads as printed on warm eggshell stock.

## Color (OKLCH)

```css
--yolk:        oklch(0.80 0.158 78);   /* brand: bright golden yolk        */
--yolk-deep:   oklch(0.70 0.160 64);   /* deeper, hovers / motif depth     */
--paprika:     oklch(0.62 0.190 40);   /* accent: chili-orange             */
--paprika-ink: oklch(0.52 0.185 38);   /* link text on light (AA-safe)     */
--chive:       oklch(0.58 0.100 145);  /* micro herb accent, used sparingly*/

--ink:         oklch(0.22 0.012 60);   /* cast-iron near-black, main text  */
--ink-soft:    oklch(0.40 0.016 60);   /* secondary text                   */
--eggshell:    oklch(0.971 0.010 85);  /* page bg: warm off-white, low C   */
--shell-deep:  oklch(0.940 0.014 85);  /* raised surfaces / borders        */
--skillet:     oklch(0.255 0.012 60);  /* dark code-panel bg (the pan)     */
--skillet-2:   oklch(0.305 0.012 60);  /* code panel inset / borders       */
```

Strategy: **Committed.** Yolk carries the hero and brand marks; eggshell is the
canvas; skillet anchors all code. Paprika is the single hot accent. Chive is a
near-secret flourish (herb flecks, the preserved-comment marker). No navy, no
indigo, no purple, no gradient mesh.

Code-panel syntax (on skillet): strings → yolk, keys/keywords → paprika,
numbers/bools → chive-tinted, comments → eggshell with a chive left-marker so the
*preserved comment* (the library's whole point) is visually the star, not dimmed.

### Contrast (verify in build)
- ink on eggshell, ink on yolk, eggshell on skillet — all AA body or better.
- paprika-ink for inline links on light; paprika for large CTA/headings only.

## Typography

- **Display & text:** Bricolage Grotesque (variable, weights ~300–800, optical
  size axis). One family carries the page — wonky, warm, characterful, not a
  reflex-reject default. Tight but ≥ -0.03em on display; `text-wrap: balance`
  on h1–h3.
- **Code:** JetBrains Mono. The code samples are the hero imagery, so the mono
  must be crisp and readable.
- Scale: fluid `clamp()`, ratio ≥1.25. Display hero ≤ ~5.5rem. Body 65–75ch max.

## Components

- **Code panel** — skillet-dark rounded block, mono, syntax-colored, with an
  optional caption tab. Preserved comments get a chive marker + label.
- **Round-trip demo** — paired input/output panels with a connecting "fold"
  showing a comment surviving an edit. Centerpiece.
- **Buttons** — primary: ink-on-yolk pill; secondary: outline-on-eggshell.
  Generous hit area, visible focus ring (paprika), spring-free ease-out.
- **Ingredient list** (features) — NOT identical cards. A characterful labeled
  list / recipe-card layout with varied weight and the omelette mark as bullet.
- **Omelette logomark** — custom inline SVG: a folded omelette / egg. Used in
  nav, footer, and as decorative motif.

## Layout

- Eggshell page; full-bleed yolk hero block; skillet code panels.
- Fluid `clamp()` spacing, varied rhythm (generous between movements, tight
  within groups). Flex for 1D, grid only where 2D.
- Responsive without breakpoint sprawl; test headline copy at every width.
- Semantic z-index scale, not magic 9999s.

## Motion

- One orchestrated hero load: mark + headline + demo settle in with staggered
  ease-out (expo/quart), no bounce.
- Round-trip demo: a subtle "fold" transition that demonstrates the comment
  being preserved through an edit. Intentional, not decorative.
- Every animation has a `prefers-reduced-motion: reduce` crossfade/instant
  fallback. Default content is visible; reveals enhance, never gate.
