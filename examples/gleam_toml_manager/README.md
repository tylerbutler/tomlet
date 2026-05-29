# gleam_toml_manager

An example CLI that demonstrates the [`tomlet`](../../) API by managing a
`gleam.toml` — bumping the version, adding/removing dependencies, and
reading/writing arbitrary keys — **without disturbing comments or key order**.

It runs on both the Erlang and JavaScript (Node) targets, demonstrating that
tomlet's API is dual-target. This project depends on `tomlet` via a local path
(`{ path = "../.." }`); it is an example and is not published.

## Run

From this directory:

```sh
gleam run -- <command> <args> [--file=PATH] [--dry-run]
```

`--file` defaults to `gleam.toml`. Use `--dry-run` to print the result instead
of writing the file. Select a target with `--target erlang` (default) or
`--target javascript`. Flags use glint's `--name=value` syntax.

## Commands

| Command | What it does | tomlet API |
|---|---|---|
| `bump <major\|minor\|patch>` | Bump `version` and add a `# bumped to …` comment | `get_string`, `set_string`, `insert_comment_before` |
| `add-dep <name> <version>` | Add/update a dependency | `set_string` |
| `remove-dep <name>` | Remove a dependency | `remove` |
| `get <a.b.c>` | Print the value at a dotted path | `get` |
| `set <a.b.c> <value>` | Set a string value at a dotted path | `set_string` |

## Example

Given the bundled `sample.gleam.toml`:

```sh
gleam run -- bump minor --file=sample.gleam.toml --dry-run
```

prints (note the preserved comments and the new annotation):

```toml
# Project metadata for the demo
name = "demo_app"
# bumped to 1.3.0 by gleam_toml_manager
version = "1.3.0"  # keep this in sync with the changelog

# Dependencies are listed below
[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"  # standard library
gleam_json = ">= 2.0.0 and < 3.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

Run the same thing on the JavaScript target:

```sh
gleam run --target javascript -- bump minor --file=sample.gleam.toml --dry-run
```

## Exit codes

The CLI exits `0` on success and `1` on any error (missing file, parse error,
missing key, bad version, …), printing the reason to stderr. Exit codes work on
both targets via `shellout.exit`, so the tool is safe to use in scripts and CI:

```sh
gleam run -- bump minor --file=gleam.toml || echo "bump failed"
```

## Test

```sh
gleam test                       # Erlang target
gleam test --target javascript   # JavaScript target
```
