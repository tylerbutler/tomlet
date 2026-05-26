# tomlet

A round-tripping TOML parser and writer for Gleam.

Tomlet parses TOML 1.0.0 into an opaque document that retains comments, key
order, and surrounding trivia. Unedited documents round-trip to their original
text; edited values are written back while preserving nearby comments and
document structure. Inspired by Rust's
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

Typed accessors include `get_string`, `get_int`, `get_bool`, `get_float`,
`get_date`, `get_time`, and `get_datetime`. Use `get` when you need to inspect
any TOML value through the public `tomlet.Value` type, including dates, times,
arrays, inline tables, standard tables, and arrays of tables.

```gleam
let assert Ok(doc) = tomlet.parse("released = 2026-05-25\n")
let assert Ok(tomlet.DateValue(date)) = tomlet.get(doc, ["released"])
let text = tomlet.date_to_string(date)
// -> "2026-05-25"
```

Inline table values are addressed with the same key path syntax:

```gleam
let assert Ok(doc) = tomlet.parse("pkg = { name = \"tomato\" }\n")
let assert Ok(name) = tomlet.get_string(doc, ["pkg", "name"])
```

Parse errors use stable variants for machine handling. `InvalidSyntax` and
`DuplicateKey` carry byte offsets; use `tomlet.line_column(input, offset)` when
displaying diagnostics to users.

## Checked edits

Edit operations return `Result(Document, EditError)` so applications can tell
successful edits from invalid paths, key conflicts, missing keys, and unsafe
comment text. Comment insertion rejects TOML-forbidden comment control
characters. New keys are emitted as bare TOML keys when possible and quoted when
needed. Current edit helpers include `set_string`, `set_int`, `set_bool`,
`set_float`, `set_date`, `set_time`, `set_datetime`, `set_array`,
`set_inline_table`, `append_array_of_tables`, `remove`, and
`insert_comment_before`. Construct typed date, time, and date-time values with
`date_from_string`, `time_from_string`, and `datetime_from_string`.

The `set_*` helpers can replace existing values inside inline tables, such as
`["pkg", "name"]` in `pkg = { name = "tomato" }`. Missing nested keys inside an
existing inline table are reported as `InlineTableInsertUnsupported`; create
those keys by rewriting the table shape explicitly rather than relying on
implicit insertion.

## Examples

Read typed values:

```gleam
let input =
  "title = \"Tomlet\"\n"
  <> "version = 1\n"
  <> "enabled = true\n"
  <> "ratio = 3.14\n"

let assert Ok(doc) = tomlet.parse(input)
let assert Ok(title) = tomlet.get_string(doc, ["title"])
let assert Ok(version) = tomlet.get_int(doc, ["version"])
let assert Ok(enabled) = tomlet.get_bool(doc, ["enabled"])
let assert Ok(ratio) = tomlet.get_float(doc, ["ratio"])
```

Edit a document and write it back:

```gleam
let input =
  "# package metadata\n"
  <> "name = \"tomlet\"\n"
  <> "version = 0\n"
  <> "draft = true\n"

let assert Ok(doc) = tomlet.parse(input)
let assert Ok(doc) = tomlet.set_int(doc, ["version"], 1)
let assert Ok(doc) = tomlet.remove(doc, ["draft"])
let assert Ok(doc) =
  tomlet.insert_comment_before(doc, ["version"], "first stable release")

tomlet.to_string(doc)
// -> "
// # package metadata
// name = \"tomlet\"
// # first stable release
// version = 1
// "
```

Start from an empty document:

```gleam
let doc = tomlet.new()
let assert Ok(doc) = tomlet.set_string(doc, ["package", "name"], "tomlet")
let assert Ok(doc) = tomlet.set_int(doc, ["package", "version"], 1)

tomlet.to_string(doc)
// -> "
// [package]
// name = \"tomlet\"
// version = 1
// "
```

Report parse errors with line and column information:

```gleam
let input = "name = \n"

case tomlet.parse(input) {
  Ok(_) -> Nil
  Error(tomlet.InvalidSyntax(_, offset)) -> {
    let position = tomlet.line_column(input, offset)
    let line = tomlet.position_line(position)
    let column = tomlet.position_column(position)
    // Show line and column in your application's diagnostic.
  }
  Error(tomlet.DuplicateKey(_, offset)) -> {
    let position = tomlet.line_column(input, offset)
    let line = tomlet.position_line(position)
    let column = tomlet.position_column(position)
    // Show line and column in your application's diagnostic.
  }
  Error(tomlet.InvalidEncoding) -> Nil
}
```

## Public API

The semver-stable public API is the top-level `tomlet` module. Other
`tomlet/*` modules are internal implementation details and may change without
notice.

### API stability policy

- The top-level `tomlet` module is the only supported API surface.
- Modules listed in `gleam.toml` under `internal_modules` are not public API.
- Public variant types are stable and matchable. Adding, removing, or renaming
  variants is treated as a breaking change.
- The project follows Semantic Versioning; breaking API changes are released as
  major versions.

## Contributing

See [`DEV.md`](./DEV.md) for contributor setup, test commands, changelog
guidelines, and release-readiness checks.

## License

Licensed under either of

- Apache License, Version 2.0 ([`LICENSE-APACHE`](./LICENSE-APACHE) or
  <https://www.apache.org/licenses/LICENSE-2.0>)
- MIT license ([`LICENSE-MIT`](./LICENSE-MIT) or
  <https://opensource.org/licenses/MIT>)

at your option.

Unless you explicitly state otherwise, any contribution intentionally submitted
for inclusion in Tomlet by you, as defined in the Apache-2.0 license, shall be
dual licensed as above, without any additional terms or conditions.
