# Product

## Register

brand

## Users

Gleam and BEAM developers who write tooling: package authors editing `gleam.toml`,
config-management and build-step tooling that reads → mutates → writes
`pyproject.toml` / `Cargo.toml`, and static-site/docs generators handling TOML
front-matter. They arrive from Hex, the Gleam ecosystem, or a search for "Gleam
TOML writer." Their context is a code editor and a terminal; they are evaluating
whether to add a dependency and want to know, fast, that it is correct,
spec-compliant, and won't mangle their files. The landing page is the pitch: it
must earn `gleam add tomlet` in one scroll.

## Product Purpose

tomlet is a round-tripping TOML 1.0.0 parser and writer for Gleam. Unlike every
other parser in the BEAM ecosystem, it preserves comments, key order, and
formatting on the way out — `parse(s) |> to_string == s` — and edits values
while leaving the surrounding comments and structure untouched. It fills a real
gap: no other Erlang/Elixir/Gleam TOML library round-trips comments. Success for
the landing page is a developer understanding the round-trip guarantee from a
single before/after code demo and trusting the library enough to install it.

## Brand Personality

Playful, characterful, warm — with the competence to back it up. The name is a
pun (TOML + omelette: a little omelette of TOML), and the voice leans into that
breakfast-kitchen warmth without ever undercutting the fact that this is a
correct, spec-compliant, semver-stable library. Think a confident cook who jokes
while plating a technically flawless dish. Three words: **folded, golden,
exacting.** Emotional goal: delight and reassurance — "this is fun *and* I can
trust it with my config files."

## Anti-references

- **Generic dev-tool SaaS landing.** No gradient-mesh hero, no endless identical
  feature-card grid, no navy/indigo/purple palette, no "hero metric" template.
  This is the primary thing to avoid.
- Editorial-magazine cosplay (display-serif italic + mono kicker + ruled
  columns) on a brief that isn't a magazine.
- Cutesy to the point of unserious. The omelette motif is seasoning, not the
  whole meal; the library's correctness must always read through.
- Monospace-everywhere "look how technical we are" costume.

## Design Principles

1. **The demo is the pitch.** Round-trip and comment-preservation are shown in
   real code, not described in adjectives. Lead with the before/after.
2. **Earn the pun.** Personality is welcome wherever it doesn't cost clarity;
   the moment a joke obscures what the library does, the clarity wins.
3. **Correctness is the luxury good.** Spec compliance, both targets, and stable
   API are the real flex — present them as confidence, not as a checklist.
4. **One scroll to `gleam add`.** Every section moves a skeptical developer
   closer to installing; no filler folds.
5. **Distinctive over safe.** A memorable omelette-yellow page beats another
   forgettable navy SaaS clone. Commit to the voice.

## Accessibility & Inclusion

Target WCAG 2.1 AA. Body text ≥4.5:1, large text ≥3:1 — verified, not assumed
(black-on-yolk and ink-on-eggshell are the workhorse pairings). Full keyboard
operability and visible focus states. Every animation has a
`prefers-reduced-motion: reduce` alternative. Code examples remain legible and
selectable; color is never the only signal (highlighted/preserved comments also
carry a label or marker).
