# tomlet

A round-tripping TOML parser and writer for Gleam.

Tomlet parses TOML 1.0.0 into an AST that retains comments, key order, and
formatting, lets you edit it programmatically with checked operations, and
writes it back out with surrounding trivia intact. Inspired by Rust's
[`toml_edit`](https://docs.rs/toml_edit) and Python's
[`tomlkit`](https://github.com/python-poetry/tomlkit).

```sh
gleam add tomlet
```

```gleam
import tomlet

pub fn main() {
  let assert Ok(doc) = tomlet.parse("
# the user's favorite snack
snack = \"tomato\"  # raw, with salt
")

  let assert Ok(updated) =
    tomlet.set_string(doc, ["snack"], "tomato sandwich")

  tomlet.to_string(updated)
  // -> "
  // # the user's favorite snack
  // snack = \"tomato sandwich\"  # raw, with salt
  // "
}
```

## Parsing and typed access

Use `tomlet.parse` for `String` input, or `tomlet.parse_bytes` when raw bytes
need TOML-compliant UTF-8 and BOM validation before parsing.

```gleam
let assert Ok(doc) = tomlet.parse_bytes(<<"answer = 42\n":utf8>>)
let assert Ok(answer) = tomlet.get_int(doc, ["answer"])
```

Typed accessors include `get_string`, `get_int`, `get_bool`, and `get_float`.
Use `get` when you need the underlying AST value, including TOML special
floating-point values (`inf`, `-inf`, and `nan`) that are represented as
`ast.SpecialFloat` for cross-target portability.

## Checked edits

Edit operations return `Result(Document, EditError)` so applications can tell
successful edits from invalid paths, key conflicts, missing keys, and unsafe
comment text. Comment insertion rejects text containing CR or LF. New keys are
emitted as bare TOML keys when possible and quoted when needed.

## Public API

The supported public API is `tomlet` plus the advanced `tomlet/ast` module.
Other `tomlet/*` modules are internal implementation details and may change
before 1.0.

## Development

```sh
just
just ci
just test
gleam test --target javascript
./scripts/run_corpus_tests.py valid
./scripts/run_corpus_tests.py invalid
./scripts/run_corpus_tests.py
```

See [PRD.md](./PRD.md) for goals, design, and milestones.
