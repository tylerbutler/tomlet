# Design: `gleam_toml_manager` — a tomlet showcase CLI

**Date:** 2026-05-28 · **Status:** Approved (pending spec review) · **Owner:** @tylerbutler

## Purpose

A realistic, runnable example that demonstrates tomlet's public API through a
believable workflow: managing a `gleam.toml` (bump the version, add/remove
dependencies, read/write arbitrary keys) **without nuking the user's comments
or key order**. This is tomlet's headline use case, so the example doubles as
living documentation.

The example is a CLI built with [glint](https://hexdocs.pm/glint), exercising a
broad slice of the tomlet surface: `parse`, `to_string`, `get`, `get_string`,
`set_string`, `remove`, and `insert_comment_before`, plus the typed error
variants (`GetError`, `EditError`).

## Constraints

- **The tomlet library must stay dependency-free** (PRD goal #4). The example
  pulls in glint and friends, so it lives in its own isolated sub-project with
  its own `gleam.toml`. It is never published to Hex and never affects the
  library's dependency graph.
- **Dual target (Erlang + JavaScript).** The example runs on both targets to
  demonstrate that tomlet's API is dual-target (PRD goal #4). All chosen
  dependencies support both: `simplifile` (file IO) and `shellout` (exit codes)
  ship Erlang and JavaScript/Node FFI, while `glint`, `argv`, and `gleam_stdlib`
  are target-agnostic. The JavaScript build targets Node.

## Layout

```
examples/gleam_toml_manager/
  gleam.toml            # deps: tomlet (path="../.."), glint, argv, simplifile, shellout, gleam_stdlib
  README.md             # what it shows + how to run each command
  sample.gleam.toml     # commented fixture to demo against
  src/
    gleam_toml_manager.gleam           # glint wiring + main (thin)
    gleam_toml_manager/commands.gleam  # pure domain fns over Document (the tomlet showcase)
    gleam_toml_manager/semver.gleam    # tiny pure semver parse/bump
    gleam_toml_manager/app_error.gleam # unified error type -> friendly message
  test/
    commands_test.gleam   # round-trip + comment-preservation assertions
    semver_test.gleam     # semver parse/bump edge cases
```

### Why this shape

Glint wiring is kept thin: each command builder reads its args/flags and
immediately delegates to a pure function in `commands`. File IO happens only at
the edges (`main` / a small load/save helper). This concentrates the tomlet API
usage in one readable, filesystem-free, unit-testable module — keeping the API
the star of the show rather than burying it in plumbing.

## Subcommands → tomlet API mapping

Every command takes a shared `--file` flag (default `gleam.toml`) and a
`--dry-run` flag (print the resulting document to stdout instead of writing it
back). (glint's flag model uses `--name`; no short aliases.)

| Command | tomlet API exercised |
|---|---|
| `bump <major\|minor\|patch>` | `get_string(["version"])` → parse semver → `set_string(["version"], new)` → `insert_comment_before(["version"], "bumped to <new> by gleam_toml_manager")`. The headline "edit without nuking comments" demo. Surfaces `KeyNotFound`/`WrongType` when `version` is absent or non-string. |
| `add-dep <name> <version>` | `set_string(["dependencies", name], version)` — nested-path edit that creates the `[dependencies]` standard table when absent and emits a new bare/quoted key. |
| `remove-dep <name>` | `remove(["dependencies", name])` — checked delete with a friendly `MissingEditKey` message. |
| `get <dotted.path>` | `get(path)` (path split on `.`) → render the returned `tomlet.Value` for display. Read-only; never writes. Surfaces `WrongType`/`KeyNotFound`. |
| `set <dotted.path> <value>` | `set_string(path, value)` over an arbitrary dotted path. String-typed by default (documented limitation of the demo). |

### bump annotation detail

`bump` is the one command that also calls `insert_comment_before`, adding a
leading comment such as `# bumped to 1.3.0 by gleam_toml_manager` above the
`version` key. This showcases comment insertion alongside value editing and
makes the "comments are preserved and can be added" story concrete.

## Data flow (per command)

```
load file (simplifile.read)
  → tomlet.parse
  → pure domain fn : Document -> Result(Document, AppError)
  → tomlet.to_string
  → write back (simplifile.write)  [or print to stdout if --dry-run]
```

`get` short-circuits after the read step: it parses, reads the value, prints it,
and never serializes or writes.

## Error handling

A single `AppError` type wraps every failure source:

- `simplifile` IO errors (file not found, permission denied, …)
- tomlet `ParseError` (with `line_column` rendering for syntax/duplicate-key
  errors)
- tomlet `GetError` (`KeyNotFound`, `WrongType` with its `ExpectedType`)
- tomlet `EditError` (invalid path, key conflict, missing key, unsafe comment)
- semver parse failures (e.g. a `version` that isn't `N.N.N`)

`app_error.to_message` renders each variant to a clear one-line message printed
to **stderr** via `io.println_error`. No silent fallbacks: e.g. running `bump`
against a missing or non-string `version` reports exactly that rather than
guessing. On any error the CLI exits with status `1` via `shellout.exit` (which
provides cross-target Erlang/JavaScript exit codes); a successful run exits `0`.
This makes the tool composable in shell pipelines and CI.

## Testing strategy

The pure `commands` and `semver` modules are tested with no filesystem:

- Feed a commented TOML string, run the domain function, assert on
  `tomlet.to_string` output — proving both the *edit* and the
  *comment/key-order preservation* that is tomlet's entire reason to exist.
- `bump`: assert version changes, lower components reset (`0.9.9 → 1.0.0` for a
  major bump), and the annotation comment appears, while unrelated comments and
  keys are byte-for-byte unchanged.
- `add-dep` / `remove-dep`: assert the dependency table mutates correctly and
  surrounding entries are untouched; assert `MissingEditKey` on removing an absent
  dep.
- `semver`: parse/bump edge cases and rejection of malformed input.

Because the pure modules avoid the filesystem, `gleam test` runs identically on
both targets: CI runs `gleam test --target erlang` and
`gleam test --target javascript`, mirroring the library's own dual-target CI and
proving the tomlet API behaves the same on both.

## README & fixture

`sample.gleam.toml` carries real comments and a `[dependencies]` block so a
reader can run e.g. `gleam run -- bump minor` and *see* the comments survive in
the output. The README walks each command with before/after snippets and the
exact `gleam run --` invocation, and shows running on both targets
(`gleam run --target erlang -- …` and `gleam run --target javascript -- …`).

## Out of scope

- Typed `set` (int/bool/float/date) — `set` is string-only for the demo.
- Publishing to Hex (this is an example, not a package).
- A standalone `tomlet_cli` repo (the PRD floats this as a separate future
  effort; this example is intentionally lighter-weight).
