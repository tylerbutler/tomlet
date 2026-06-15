# CLI TOML Editing Tool Design

## Summary

Build a separate `tomlet_cli` package that depends on `tomlet` and ships a
`tomlet` executable. The CLI edits any TOML file while preserving comments, key
order, formatting trivia, and line endings through tomlet's public API.

The first release is a small, script-first config editor. It supports
`get`, `set`, `unset`, `keys`, `check`, and `comment-before`. It does not try to
be a jq-style expression language or a formatter.

## Research background

Existing tools show a clear gap:

- Taplo is strong at `check`, `format`, `lint`, and `get`, but it does not offer
  in-place `set` or `unset` commands.
- `toml-cli` has useful `get` and `set` shapes, including dotted paths and
  `[N]` array indexes, but its `set` path is limited and does not provide a full
  in-place editing story.
- `tq`, `tomlq`, and `stoml` are useful for raw scalar reads in shell scripts,
  but they are read-only or minimal.
- `git config`, `npm pkg`, `cargo-edit`, and `uv version` point toward a
  durable config-editing contract: explicit verbs, in-place writes for named
  files, `--dry-run` for previews, `--check` for CI, quiet success, and stable
  exit codes.
- `yq` and `dasel` show the power of expression languages, but that power adds
  complexity that does not fit the first tomlet CLI release.

Tomlet's distinctive advantage is safe, surgical TOML mutation with comments and
layout preserved. The CLI should make that advantage available to scripts.

## Goals

1. Edit arbitrary TOML files from shell scripts and CI jobs.
2. Preserve existing comments, key order, trivia, and line-ending style.
3. Use tomlet's stable public API; do not depend on internal modules.
4. Keep default output plain, predictable, and machine-safe.
5. Report failures with stable exit codes.
6. Use existing Gleam libraries for CLI plumbing and terminal output.

## Non-goals

- A TOML formatter.
- Schema validation.
- A jq/yq-style expression language.
- Wildcard path queries.
- JSON output in the first release.
- Project-specific helpers for `gleam.toml`, `Cargo.toml`, or `pyproject.toml`.

## Package and dependencies

The CLI should live in a separate package, tentatively named `tomlet_cli`, and
depend on `tomlet`. The executable can be named `tomlet`.

Use existing libraries instead of hand-written plumbing:

- `glint` for commands, flags, help text, and argument routing.
- `argv` for process arguments.
- `simplifile` for file I/O.
- `shellout` or an equivalent for explicit process exits.
- `spruce` for human-facing output formatting.

Spruce must not decorate machine-readable command output by default. Use it for
diagnostics, help-adjacent text, and future diff/check messages. Plain output
remains the default for `get`, `keys`, and TOML previews.

## Command set

### `check`

Validate input as TOML.

```sh
tomlet check -f config.toml
tomlet check -f -
```

Success prints nothing and exits `0`. Parse or encoding errors print diagnostics
to stderr and exit `2`.

### `get`

Read a value at a path.

```sh
tomlet get -f config.toml package.name
tomlet get -f config.toml package --output toml
tomlet get -f config.toml .
```

Raw scalar output is the default. Strings print without quotes, numbers and
booleans print as TOML text, and dates/times print their lexical forms. A
trailing newline is added unless the caller passes a future
`--strip-newline` flag.

Structured values require `--output toml`; asking for a structured value in raw
mode exits `4`. JSON output is deferred.

### `set`

Set a TOML value at a path.

```sh
tomlet set -f config.toml package.version 1.2.3 --type string
tomlet set -f config.toml retry_count 3
tomlet set -f config.toml package.private true
tomlet set -f config.toml package.name tomlet --type string
tomlet set -f config.toml ports '[8000, 8001]'
tomlet set -f config.toml package '{ name = "tomlet" }'
```

`VALUE` is a TOML value literal by default. `--type string` treats `VALUE` as raw
shell text and emits it as a TOML string.

When `--file` names a real file, `set` writes in-place by default. With
`--file -`, it reads stdin and writes the edited document to stdout.

### `unset`

Remove an existing value.

```sh
tomlet unset -f config.toml dependencies.old_dep
```

Missing keys fail by default. A future `--missing-ok` flag can make absent keys a
successful no-op.

### `keys`

List immediate child keys at a table or inline table path.

```sh
tomlet keys -f config.toml
tomlet keys -f config.toml dependencies
```

Output one key per line in source order. This maps directly to
`tomlet.table_keys`.

### `comment-before`

Insert a standalone comment before an existing key.

```sh
tomlet comment-before -f config.toml package.version "set by release automation"
```

This command uses `tomlet.insert_comment_before`. It accepts text with or without
a leading `#`. It rejects invalid TOML comment text and missing target keys.

## File behavior

Use `-f` / `--file` for file selection. `-` means stdin.

Mutating commands follow this contract:

| Input mode | Default mutation behavior |
| --- | --- |
| `--file path.toml` | Write in-place. |
| `--file -` | Read stdin and write edited TOML to stdout. |
| `--dry-run` | Print the would-be TOML to stdout and do not write. |
| `--check` | Exit `0` if the command would make no change; exit `5` if it would change the file. |

In-place writes should avoid touching the file when the emitted TOML is identical
to the original bytes. This keeps no-op `set` commands idempotent and avoids
unnecessary mtime changes.

## Path syntax

Use a small path grammar:

```text
path      ::= "." | segment selector*
selector  ::= "." segment | "[" index "]"
segment   ::= bare-segment | quoted-segment
index     ::= non-negative decimal integer
```

Examples:

```text
package.name
"key.with.dots"
dependencies.gleam_stdlib
servers[0].host
.
```

`[]` append syntax, negative indexes, wildcards, glob segments, and jq-style
filters are out of scope for v1.

Tomlet's current edit helpers accept key paths, not arbitrary array-element edit
selectors. V1 should support array indexes only for `get` by combining
document-level lookup with `tomlet.value_get`. Mutating array elements should be
deferred unless a public tomlet API supports them cleanly.

## Value parsing

The CLI needs a public way to parse a standalone TOML value literal. Add a
library helper before implementing typed `set`:

```gleam
pub fn parse_value(input: String) -> Result(Value, ParseError)
```

The helper should parse one TOML value and reject trailing syntax. It should
return public `tomlet.Value` variants, not internal AST values.

The CLI can then route public values to existing setters:

| Parsed value | CLI operation |
| --- | --- |
| `StringValue` | `set_string` |
| `IntValue` | `set_int` |
| `BoolValue` | `set_bool` |
| `FloatValue` | `set_float` |
| `DateValue` | `set_date` |
| `TimeValue` | `set_time` |
| `DateTimeValue` | `set_datetime` |
| `ArrayValue` | `set_array` |
| `InlineTableValue` | `set_inline_table` |

`StandardTableValue` and `ArrayOfTablesValue` are not valid standalone `set`
values in v1. Array-of-tables append support can be a later command because it
needs a command shape for table entries.

## Output and diagnostics

Default stdout is for command data only:

- `get` prints the requested value.
- `keys` prints keys.
- `--dry-run` prints TOML.
- Successful mutations print nothing.

Diagnostics go to stderr. They should include a short problem label and, for
parse errors, a line and column derived from `tomlet.line_column`.

Spruce may add color and emphasis for terminal diagnostics. It must not affect
plain data output. Respect `NO_COLOR` and provide `--no-color` if Spruce does not
already do so.

## Exit codes

Use stable exit codes:

| Code | Meaning |
| ---: | --- |
| 0 | Success. |
| 1 | Key or path not found. |
| 2 | TOML parse or encoding error. |
| 3 | File I/O error. |
| 4 | Invalid path, invalid value, type mismatch, or unsupported edit. |
| 5 | `--check` would change the file. |

Missing keys should produce a concise stderr message by default. A future
`--quiet` flag can suppress expected lookup failures for conditional scripts.

## Architecture

Keep the CLI split into small modules:

| Unit | Responsibility |
| --- | --- |
| Command router | Define `glint` commands, flags, help, and handler dispatch. |
| Path parser | Convert CLI path text into key segments and read selectors. |
| Value parser | Apply `--type` and standalone TOML value parsing. |
| Document I/O | Read bytes, call `parse_bytes`, and write changed files. |
| Command handlers | Implement the six v1 commands through tomlet's public API. |
| Output renderer | Render raw scalars, TOML output, diagnostics, and exit codes. |

The command data flow is always:

```text
read bytes -> parse with tomlet -> run one checked operation -> render, write, or fail
```

No command should rewrite raw text directly.

## Testing strategy

Test command handlers as pure functions first. Use integration tests only for
argv parsing, file I/O, stdin/stdout behavior, and exit codes.

Required cases:

- `check` accepts valid TOML and rejects invalid TOML with exit code `2`.
- `get` prints raw strings, ints, floats, booleans, dates, times, and datetimes.
- `get --output toml` emits valid TOML for structured values.
- `set` parses TOML literals and preserves unrelated comments and formatting.
- `set --type string` emits raw shell text as a TOML string.
- `set` no-ops do not rewrite the file.
- `unset` removes existing keys and fails on missing keys.
- `keys` lists immediate child keys in source order.
- `comment-before` preserves nearby trivia and rejects invalid comment text.
- stdin mutation writes edited TOML to stdout.
- `--dry-run` never writes.
- `--check` exits `0` for no change and `5` for would-change.

## Release notes

The CLI package should document that it is script-first and format-preserving.
If the `parse_value` helper lands in `tomlet`, that library change needs a
Changie fragment under `.changes/unreleased/`.

## References

- Taplo CLI: <https://taplo.tamasfe.dev/cli/>
- `toml-cli`: <https://github.com/gnprice/toml-cli>
- `tomlq`: <https://github.com/cryptaliagy/tomlq>
- `stoml`: <https://github.com/freshautomations/stoml>
- `cargo-edit`: <https://github.com/killercup/cargo-edit>
- `npm pkg`: <https://docs.npmjs.com/cli/v10/commands/npm-pkg>
- `git config`: <https://git-scm.com/docs/git-config>
- `uv version`: <https://docs.astral.sh/uv/reference/cli/#uv-version>
- `yq`: <https://github.com/mikefarah/yq>
- `dasel`: <https://github.com/TomWright/dasel>
