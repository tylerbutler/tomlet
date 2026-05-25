# tomato

A round-tripping TOML parser and writer for Gleam.

**Status:** 🌱 pre-alpha — scaffolded, see [PRD.md](./PRD.md).

Tomato parses TOML 1.0.0 into an AST that retains comments, key order, and
formatting, lets you edit it programmatically, and writes it back out with all
surrounding trivia intact. Inspired by Rust's
[`toml_edit`](https://docs.rs/toml_edit) and Python's
[`tomlkit`](https://github.com/python-poetry/tomlkit).

```sh
gleam add tomato
```

```gleam
import tomato

pub fn main() {
  let assert Ok(doc) = tomato.parse("
# the user's favorite snack
snack = \"tomato\"  # raw, with salt
")

  let updated = tomato.set_string(doc, ["snack"], "tomato sandwich")
  tomato.to_string(updated)
  // -> "
  // # the user's favorite snack
  // snack = \"tomato sandwich\"  # raw, with salt
  // "
}
```

## Development

```sh
gleam test
gleam test --target javascript
```

See [PRD.md](./PRD.md) for goals, design, and milestones.
