# Tomato — Product Requirements Document

**Status:** Draft v0.1 · **Owner:** @tylerbutler · **Last updated:** 2026-05-24

## 1. Summary

Tomato is a pure-Gleam TOML 1.0.0 library that **parses, edits, and writes TOML
while preserving comments, key order, and formatting choices**. It fills a gap
in the BEAM ecosystem: no existing Erlang, Elixir, or Gleam TOML library
round-trips comments, and only `tomerl` (Erlang) can write TOML at all.

The reference inspirations are Rust's [`toml_edit`](https://docs.rs/toml_edit)
and Python's [`tomlkit`](https://github.com/python-poetry/tomlkit). Tomato is
**not** a fork of `tom`; it is a new library with a different AST shape
designed from the start for lossless round-trip.

## 2. Goals

1. **Lossless round-trip.** `parse(s) |> to_string == s` for any spec-conformant
   TOML input, including comments, whitespace, key order, string style, integer
   base, and inline-vs-table choice.
2. **Programmatic edits preserve surrounding trivia.** Setting a value updates
   only that value's text; comments above and beside it are untouched. New keys
   are appended with sensible default formatting.
3. **TOML 1.0.0 compliance.** Pass the [toml-test](https://github.com/toml-lang/toml-test)
   suite (both `valid/` and `invalid/`).
4. **Pure Gleam, both targets.** No NIFs. Works on Erlang and JavaScript
   targets. No native dependencies.
5. **Friendly typed-access API.** `get_string`, `get_int`, etc., comparable in
   ergonomics to `tom`.

## 3. Non-goals

- TOML 1.1 / unreleased spec features (revisit when ratified).
- Schema validation, codegen, or derive-style decoders.
- Streaming / incremental parsing of huge documents.
- A CLI. (Could ship later as a separate package, e.g. `tomato_cli`.)
- Performance parity with `tom` on hot parse paths. Correctness and
  round-trip fidelity come first; optimization is a later phase.

## 4. Users & use cases

| User | Use case |
|---|---|
| Gleam tool authors | Edit `gleam.toml` programmatically (e.g. bump versions, add deps) without nuking the user's comments. |
| Config-management tooling | Read → mutate → write `pyproject.toml`, `Cargo.toml`, etc., as a build step. |
| Static-site / docs generators on BEAM | Parse TOML front-matter and emit it back unchanged when republishing. |
| Anyone currently using `tom` who also needs to write | Single library for both directions. |

## 5. Design overview

### 5.1 Two-tier API

- **`tomato`** (top-level): the high-level, ergonomic API. `parse`, `to_string`,
  `get_string`, `set`, `insert`, `remove`. Operates on an opaque `Document` and
  hides trivia.
- **`tomato/ast`**: the raw AST with trivia exposed, for advanced callers that
  want to write linters, formatters, or custom emitters.

### 5.2 AST shape (sketch)

```gleam
pub opaque type Document {
  Document(root: Table, trailing_trivia: String)
}

pub type Table {
  Table(
    // Insertion-ordered. Each entry carries its own trivia.
    entries: List(Entry),
    // Header for [section] / [[array.of.tables]] tables. None for root.
    header: Option(Header),
  )
}

pub type Entry {
  KeyValue(leading: Trivia, key: Key, value: Value, trailing: Trivia)
  Comment(text: String)
  BlankLine
}

pub type Value {
  // Each variant retains the *original textual representation* so we can emit
  // it byte-identical on round-trip. Edits regenerate the text.
  Int(value: Int, repr: String)         // "0xFF", "1_000", "42"
  Float(value: Float, repr: String)
  Bool(value: Bool)
  String(value: String, style: StringStyle)  // Basic, Literal, MultiBasic, MultiLiteral
  Date(...), Time(...), DateTime(...)
  Array(items: List(ArrayItem))          // Items carry their own trivia + trailing comma
  InlineTable(entries: List(Entry))
}
```

Key properties:

- **Insertion order is preserved** via `List` rather than `Dict`. Lookup is
  O(n) per segment; acceptable for config files. A future optimization could
  add a parallel index.
- **Every node owns its trivia.** Whitespace and comments belong to a specific
  entry, not to a free-floating "between nodes" slot. This makes edits local.
- **Original textual representation is retained** for numbers and strings.
  `get_int` returns the parsed value; emission uses `repr` unless the value
  was edited.

### 5.3 Round-trip strategy

- Parse → fully-trivia-bearing AST.
- `to_string` walks the AST and concatenates `leading + key + " = " + value_repr + trailing`.
- Edits: when a value is replaced, generate a fresh `repr` for the new value
  using a default style (basic string, decimal int, etc.). Leading/trailing
  trivia on the entry are untouched.
- New entries inserted into a table get a single-newline trailing trivia by
  default and are appended at the end of the table body (above the next
  header).

### 5.4 Comments

Comments are first-class `Entry` nodes inside a table body, plus a
`leading`/`trailing` trivia slot on each `KeyValue` and `ArrayItem`.
Classification:

- **Standalone**: a `Comment` entry on its own line.
- **Leading**: comment lines immediately above a key, captured in `leading`.
- **Trailing**: a comment on the same line as a key/value, captured in `trailing`.

This mirrors `toml_edit`'s decoration model and is sufficient for all observed
TOML editing use cases.

## 6. Public API (initial surface)

```gleam
// Parsing / emission
pub fn parse(input: String) -> Result(Document, ParseError)
pub fn to_string(doc: Document) -> String

// Typed access (consistent with `tom`)
pub fn get_string(doc, key: List(String)) -> Result(String, GetError)
pub fn get_int(doc, key: List(String)) -> Result(Int, GetError)
pub fn get_bool(doc, key: List(String)) -> Result(Bool, GetError)
pub fn get_float(doc, key: List(String)) -> Result(Float, GetError)
pub fn get(doc, key: List(String)) -> Result(Value, GetError)

// Editing
pub fn set_string(doc, key: List(String), value: String) -> Document
pub fn set_int(doc, key: List(String), value: Int) -> Document
pub fn remove(doc, key: List(String)) -> Document
pub fn insert_comment_before(doc, key: List(String), text: String) -> Document
```

All edits return a new `Document` (Gleam is immutable).

## 7. Testing strategy

1. **toml-test corpus.** Vendor or fetch the official `toml-test` JSON cases.
   Pass `valid/` and reject `invalid/`.
2. **Round-trip property.** For every `valid/` input, assert
   `to_string(parse(s)) == s`.
3. **Edit-locality property.** Generate random documents, perform an edit at a
   random path, assert that every byte outside the edited entry is unchanged.
4. **Unit tests** in `test/tomato_test.gleam` for the public API and edge
   cases (CRLF, BOM, mixed string styles, deeply nested arrays of tables).
5. **Both targets.** CI runs `gleam test --target erlang` and
   `gleam test --target javascript`.

## 8. Milestones

| M | Scope | Done = |
|---|---|---|
| **M0** | Scaffold + PRD + AST types declared | This document merged; `gleam build` green. |
| **M1** | Read-only parser passing toml-test `valid/` | All valid cases parse; typed-access API works. |
| **M2** | Emitter + round-trip property | `to_string(parse(s)) == s` for entire corpus. |
| **M3** | Editing API + edit-locality property | `set_*`, `remove`, `insert_comment_before` ship. |
| **M4** | `invalid/` rejection + polished errors | All invalid cases produce typed `ParseError` with position. |
| **M5** | 0.1.0 release on Hex | Docs, README example, CHANGELOG, license. |

## 9. Resolved design decisions

1. **Number representation.** Retain the original textual `repr` on parse.
   Regenerate `repr` only when the value is mutated, using a default style
   (decimal, no underscores). A future `set_int_with_style` API can expose
   non-default emission.

2. **Dotted-key inputs.** Keys are stored as `List(KeySegment)` with the
   original quoting and inter-segment whitespace preserved. Dotted-key
   entries (`a.b.c = 1`) are first-class entries in the AST — they are *not*
   silently rewritten into nested `Table` headers. Typed-access (`get`,
   `get_string`, etc.) transparently traverses both dotted-key chains and
   explicit `[a.b]` headers.

3. **Whitespace style on insert.** Sample the leading whitespace of the
   nearest preceding non-comment, non-blank `KeyValue` sibling in the same
   table body. Fall back to empty leading whitespace if the table is empty.
   No `=` alignment is attempted — that's a formatter's responsibility, not
   an editor's.

4. **Error reporting.** Errors carry a byte `offset: Int`. Line/column is
   computed on demand via `pub fn line_column(input: String, offset: Int) -> #(Int, Int)`.
   Avoids per-token bookkeeping in the hot path and keeps the helper reusable
   for editor integrations.

   ```gleam
   pub type ParseError {
     Unexpected(got: String, expected: String, offset: Int)
     KeyAlreadyInUse(key: List(String), offset: Int)
   }
   ```

5. **CRLF / line endings.** Detect the dominant line ending at parse time
   and store it on `Document`. Emit consistently using the stored ending.
   Mixed line endings within a single file are not preserved — they are
   treated as a defect, not a feature. Byte-identical round-trip is
   guaranteed only for files with a single consistent line ending (the
   overwhelming common case).

## 10. Risks

- **AST design is the hardest part.** Getting the trivia model wrong forces a
  rewrite at M3. Mitigation: prototype M2 round-trip on a small input set
  before committing to the shape.
- **Spec corners.** TOML's date/time grammar and multi-line string escapes
  are subtle. Mitigation: lean on `toml-test` early and often.
- **Solo maintenance.** Mitigation: keep scope narrow (no schema, no codegen),
  accept that 1.1 support waits.

## 11. Out of scope for v0.1, candidates for later

- Sorting / canonicalization mode (`to_string_canonical`).
- "Soft" edits that re-flow trivia.
- A Gleam-friendly decoder API (à la `dynamic.decode`).
- TOML 1.1 once finalized.
