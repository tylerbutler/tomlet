# gleam_toml_manager Example Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `examples/gleam_toml_manager/`, a glint-based CLI that manages a `gleam.toml` (bump version, add/remove deps, get/set keys) while preserving comments and key order, demonstrating tomlet's public API on both Erlang and JavaScript targets.

**Architecture:** An isolated Gleam sub-project (its own `gleam.toml`) so the dependency-free `tomlet` library stays clean. Thin glint command wiring delegates to a pure `commands` module that operates on a `tomlet.Document`; file IO lives only at the edges. A small `semver` module wraps the `gleamsver` library (adding the bump logic it lacks) and an `app_error` module unifies error rendering.

**Tech Stack:** Gleam, glint (CLI), argv (argument access), simplifile (dual-target file IO), shellout (cross-target exit codes), gleamsver (SemVer 2.0.0 parsing), gleeunit (tests), tomlet (the library under demonstration).

---

## Context for the implementer

- **You are working in the `tomlet` repo.** The library lives at the repo root (`src/tomlet.gleam`, etc.). Everything you create goes under `examples/gleam_toml_manager/`.
- **Run all `gleam` commands from inside `examples/gleam_toml_manager/`.** That directory is its own Gleam project with its own `gleam.toml` and `manifest.toml`.
- **tomlet public API you will use** (all from the top-level `tomlet` module):
  - `tomlet.parse(String) -> Result(Document, ParseError)`
  - `tomlet.to_string(Document) -> String`
  - `tomlet.get(doc, List(String)) -> Result(Value, GetError)`
  - `tomlet.get_string(doc, List(String)) -> Result(String, GetError)`
  - `tomlet.set_string(doc, List(String), String) -> Result(Document, EditError)`
  - `tomlet.remove(doc, List(String)) -> Result(Document, EditError)`
  - `tomlet.insert_comment_before(doc, List(String), String) -> Result(Document, EditError)`
  - `tomlet.line_column`, `tomlet.position_line`, `tomlet.position_column`
  - `tomlet.date_to_string`, `tomlet.time_to_string`, `tomlet.datetime_to_string`
- **Exact tomlet error/value variant names** (do not guess — these are real):
  - `GetError`: `KeyNotFound(key)`, `WrongType(key, expected)`
  - `EditError`: `EmptyKeyPath`, `InvalidKeySegment(segment)`, `InvalidCommentText`, `MissingEditKey(key)`, `KeyConflict(key)`, `InlineTableInsertUnsupported(key)`, `InvalidValue`
  - `ParseError`: `InvalidEncoding`, `InvalidSyntax(kind, offset)`, `DuplicateKey(key, offset)`
  - `ExpectedType`: `ExpectedString`, `ExpectedInt`, `ExpectedBool`, `ExpectedFloat`, `ExpectedDate`, `ExpectedTime`, `ExpectedDateTime`
  - `Value`: `StringValue(String)`, `IntValue(Int)`, `FloatValue(Float)`, `SpecialFloatValue(SpecialFloat)`, `BoolValue(Bool)`, `DateValue(Date)`, `TimeValue(Time)`, `DateTimeValue(DateTime)`, `ArrayValue(List(Value))`, `InlineTableValue(...)`, `StandardTableValue(...)`, `ArrayOfTablesValue(...)`

---

## File structure

| File | Responsibility |
|---|---|
| `examples/gleam_toml_manager/gleam.toml` | Project manifest + deps (incl. `tomlet` as a path dep). |
| `examples/gleam_toml_manager/.gitignore` | Ignore `build/`. |
| `examples/gleam_toml_manager/sample.gleam.toml` | Commented fixture to demo against. |
| `examples/gleam_toml_manager/README.md` | What it shows + how to run on both targets. |
| `src/gleam_toml_manager/semver.gleam` | Wraps `gleamsver` for parse/render; adds `Part` + `bump`. |
| `test/gleam_toml_manager_test.gleam` | gleeunit entry point (`gleam test` runs this module's `main`). |
| `src/gleam_toml_manager/app_error.gleam` | Unified `AppError` + `to_message`. |
| `src/gleam_toml_manager/commands.gleam` | Pure domain fns over `Document` (the tomlet showcase) + `value_to_display`. |
| `src/gleam_toml_manager.gleam` | glint wiring, IO helpers, exit codes (`shellout.exit`), `main`. |
| `test/semver_test.gleam` | semver unit tests. |
| `test/app_error_test.gleam` | Error message rendering tests. |
| `test/commands_test.gleam` | Round-trip + comment-preservation tests. |

All `src/` and `test/` paths above are relative to `examples/gleam_toml_manager/`.

---

## Task 1: Scaffold the project skeleton

**Files:**
- Create: `examples/gleam_toml_manager/gleam.toml`
- Create: `examples/gleam_toml_manager/.gitignore`
- Create: `examples/gleam_toml_manager/sample.gleam.toml`
- Create: `examples/gleam_toml_manager/src/gleam_toml_manager.gleam` (placeholder)

- [ ] **Step 1: Create the initial `gleam.toml`**

Create `examples/gleam_toml_manager/gleam.toml`:

```toml
name = "gleam_toml_manager"
version = "1.0.0"
description = "Example CLI demonstrating the tomlet API by managing a gleam.toml"

[dependencies]
gleam_stdlib = ">= 1.0.0 and < 2.0.0"
tomlet = { path = "../.." }

[dev_dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

(Matches tomlet's own `gleam_stdlib` constraint and `[dev_dependencies]` spelling so resolution is clean. No `target =` line: the default target is Erlang; the JavaScript target is selected per-command with `--target javascript`.)

- [ ] **Step 2: Create `.gitignore`**

Create `examples/gleam_toml_manager/.gitignore`:

```
*.beam
*.ez
/build
erl_crash.dump
```

- [ ] **Step 3: Create the demo fixture**

Create `examples/gleam_toml_manager/sample.gleam.toml`:

```toml
# Project metadata for the demo
name = "demo_app"
version = "1.2.3"  # keep this in sync with the changelog

# Dependencies are listed below
[dependencies]
gleam_stdlib = ">= 0.44.0 and < 2.0.0"  # standard library
gleam_json = ">= 2.0.0 and < 3.0.0"

[dev-dependencies]
gleeunit = ">= 1.0.0 and < 2.0.0"
```

- [ ] **Step 4: Create a placeholder entrypoint so the project builds**

Create `examples/gleam_toml_manager/src/gleam_toml_manager.gleam`:

```gleam
import gleam/io

pub fn main() {
  io.println("gleam_toml_manager")
}
```

- [ ] **Step 5: Add the third-party dependencies**

Run (from inside the example dir):

```bash
cd examples/gleam_toml_manager && gleam add glint argv simplifile shellout gleamsver
```

Expected: glint, argv, simplifile, shellout, and gleamsver are appended to `[dependencies]` in `gleam.toml` and resolved in `manifest.toml`.

- [ ] **Step 6: Verify the project builds on both targets**

Run:

```bash
cd examples/gleam_toml_manager && gleam build --target erlang && gleam build --target javascript
```

Expected: both builds succeed with no errors.

- [ ] **Step 7: Commit**

```bash
git add examples/gleam_toml_manager/gleam.toml examples/gleam_toml_manager/manifest.toml examples/gleam_toml_manager/.gitignore examples/gleam_toml_manager/sample.gleam.toml examples/gleam_toml_manager/src/gleam_toml_manager.gleam
git commit -m "chore: scaffold gleam_toml_manager example project"
```

---

## Task 2: semver module (wrapping gleamsver)

Version parsing/formatting is delegated to the `gleamsver` library (strict
SemVer 2.0.0, pure Gleam so it stays dual-target). This module adds only what
gleamsver lacks: a `Part` type and a `bump` function. Versions are represented
by `gleamsver.SemVer` directly.

**Files:**
- Create: `examples/gleam_toml_manager/test/gleam_toml_manager_test.gleam`
- Create: `examples/gleam_toml_manager/src/gleam_toml_manager/semver.gleam`
- Test: `examples/gleam_toml_manager/test/semver_test.gleam`

- [ ] **Step 1: Create the gleeunit entry module**

`gleam test` runs the `main` of the module named after the project. Create
`examples/gleam_toml_manager/test/gleam_toml_manager_test.gleam`:

```gleam
import gleeunit

pub fn main() {
  gleeunit.main()
}
```

`gleeunit.main()` then discovers and runs every `*_test` function in all
`*_test` modules — so the per-feature test files below do not need their own
`main`.

- [ ] **Step 2: Write the failing tests**

Create `examples/gleam_toml_manager/test/semver_test.gleam`:

```gleam
import gleam_toml_manager/semver
import gleamsver.{SemVer}
import gleeunit/should

pub fn parse_valid_test() {
  semver.parse("1.2.3")
  |> should.equal(Ok(SemVer(1, 2, 3, "", "")))
}

pub fn parse_too_few_components_test() {
  semver.parse("1.2")
  |> should.equal(Error(semver.InvalidVersion("1.2")))
}

pub fn parse_non_numeric_test() {
  semver.parse("1.x.0")
  |> should.equal(Error(semver.InvalidVersion("1.x.0")))
}

pub fn bump_major_resets_lower_test() {
  semver.bump(SemVer(0, 9, 9, "", ""), semver.Major)
  |> should.equal(SemVer(1, 0, 0, "", ""))
}

pub fn bump_minor_resets_patch_test() {
  semver.bump(SemVer(1, 2, 3, "", ""), semver.Minor)
  |> should.equal(SemVer(1, 3, 0, "", ""))
}

pub fn bump_patch_test() {
  semver.bump(SemVer(1, 2, 3, "", ""), semver.Patch)
  |> should.equal(SemVer(1, 2, 4, "", ""))
}

pub fn bump_clears_prerelease_test() {
  semver.bump(SemVer(1, 2, 3, "rc0", "build1"), semver.Minor)
  |> should.equal(SemVer(1, 3, 0, "", ""))
}

pub fn to_string_test() {
  semver.to_string(SemVer(1, 0, 0, "", ""))
  |> should.equal("1.0.0")
}

pub fn part_from_string_valid_test() {
  semver.part_from_string("minor")
  |> should.equal(Ok(semver.Minor))
}

pub fn part_from_string_invalid_test() {
  semver.part_from_string("huge")
  |> should.equal(Error(semver.InvalidPart("huge")))
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: FAIL — `semver` module does not exist / unknown module.

- [ ] **Step 4: Write the implementation**

Create `examples/gleam_toml_manager/src/gleam_toml_manager/semver.gleam`:

```gleam
import gleam/result
import gleamsver.{type SemVer, SemVer}

/// The component of a version to increment.
pub type Part {
  Major
  Minor
  Patch
}

pub type SemverError {
  InvalidVersion(text: String)
  InvalidPart(text: String)
}

/// Parse a SemVer 2.0.0 string. Delegates to the `gleamsver` library and
/// collapses its detailed parse errors into a single stable variant.
pub fn parse(text: String) -> Result(SemVer, SemverError) {
  gleamsver.parse(text)
  |> result.replace_error(InvalidVersion(text))
}

/// Increment one component, resetting the components below it and clearing any
/// pre-release / build metadata.
pub fn bump(version: SemVer, part: Part) -> SemVer {
  case part {
    Major -> SemVer(version.major + 1, 0, 0, "", "")
    Minor -> SemVer(version.major, version.minor + 1, 0, "", "")
    Patch -> SemVer(version.major, version.minor, version.patch + 1, "", "")
  }
}

pub fn to_string(version: SemVer) -> String {
  gleamsver.to_string(version)
}

pub fn part_from_string(text: String) -> Result(Part, SemverError) {
  case text {
    "major" -> Ok(Major)
    "minor" -> Ok(Minor)
    "patch" -> Ok(Patch)
    _ -> Error(InvalidPart(text))
  }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: PASS — all semver tests green. (`gleamsver.to_string` emits `"1.0.0"`
for `SemVer(1, 0, 0, "", "")`.)

- [ ] **Step 6: Commit**

```bash
git add examples/gleam_toml_manager/test/gleam_toml_manager_test.gleam examples/gleam_toml_manager/src/gleam_toml_manager/semver.gleam examples/gleam_toml_manager/test/semver_test.gleam
git commit -m "feat: add semver module wrapping gleamsver to gleam_toml_manager example"
```

---

## Task 3: app_error module

**Files:**
- Create: `examples/gleam_toml_manager/src/gleam_toml_manager/app_error.gleam`
- Test: `examples/gleam_toml_manager/test/app_error_test.gleam`

- [ ] **Step 1: Write the failing tests**

Create `examples/gleam_toml_manager/test/app_error_test.gleam`:

```gleam
import gleam/string
import gleam_toml_manager/app_error
import gleam_toml_manager/semver
import gleeunit/should
import tomlet

pub fn get_error_message_test() {
  app_error.to_message(app_error.GetError(tomlet.KeyNotFound(["version"])))
  |> should.equal("read error: key not found: version")
}

pub fn wrong_type_message_test() {
  app_error.to_message(
    app_error.GetError(tomlet.WrongType(["version"], tomlet.ExpectedString)),
  )
  |> should.equal("read error: key version is not a string")
}

pub fn edit_error_message_test() {
  app_error.to_message(
    app_error.EditError(tomlet.MissingEditKey(["dependencies", "nope"])),
  )
  |> should.equal("edit error: key not found: dependencies.nope")
}

pub fn semver_error_message_test() {
  app_error.to_message(app_error.SemverError(semver.InvalidPart("huge")))
  |> should.equal(
    "version error: unknown bump part (expected major|minor|patch): huge",
  )
}

pub fn parse_error_message_includes_position_test() {
  let source = "name =\n"
  let message =
    app_error.to_message(app_error.ParseError(
      tomlet.InvalidSyntax(tomlet.ExpectedValue, 6),
      source,
    ))
  should.be_true(string.contains(message, "parse error"))
  should.be_true(string.contains(message, "line "))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: FAIL — `app_error` module does not exist.

- [ ] **Step 3: Write the implementation**

Create `examples/gleam_toml_manager/src/gleam_toml_manager/app_error.gleam`:

```gleam
import gleam/int
import gleam/string
import gleam_toml_manager/semver
import simplifile
import tomlet

pub type AppError {
  FileError(error: simplifile.FileError)
  ParseError(error: tomlet.ParseError, source: String)
  GetError(error: tomlet.GetError)
  EditError(error: tomlet.EditError)
  SemverError(error: semver.SemverError)
}

pub fn to_message(error: AppError) -> String {
  case error {
    FileError(e) -> "file error: " <> simplifile.describe_error(e)
    ParseError(e, source) -> "parse error: " <> describe_parse_error(e, source)
    GetError(e) -> "read error: " <> describe_get_error(e)
    EditError(e) -> "edit error: " <> describe_edit_error(e)
    SemverError(e) -> "version error: " <> describe_semver_error(e)
  }
}

fn path_to_string(key: List(String)) -> String {
  string.join(key, ".")
}

fn position(source: String, offset: Int) -> String {
  let pos = tomlet.line_column(source, offset)
  "line "
  <> int.to_string(tomlet.position_line(pos))
  <> ", column "
  <> int.to_string(tomlet.position_column(pos))
}

fn describe_parse_error(error: tomlet.ParseError, source: String) -> String {
  case error {
    tomlet.InvalidEncoding -> "input is not valid UTF-8"
    tomlet.InvalidSyntax(_, offset) ->
      "invalid syntax at " <> position(source, offset)
    tomlet.DuplicateKey(key, offset) ->
      "duplicate key " <> path_to_string(key) <> " at " <> position(source, offset)
  }
}

fn describe_get_error(error: tomlet.GetError) -> String {
  case error {
    tomlet.KeyNotFound(key) -> "key not found: " <> path_to_string(key)
    tomlet.WrongType(key, expected) ->
      "key " <> path_to_string(key) <> " is not " <> expected_to_string(expected)
  }
}

fn expected_to_string(expected: tomlet.ExpectedType) -> String {
  case expected {
    tomlet.ExpectedString -> "a string"
    tomlet.ExpectedInt -> "an integer"
    tomlet.ExpectedBool -> "a boolean"
    tomlet.ExpectedFloat -> "a float"
    tomlet.ExpectedDate -> "a date"
    tomlet.ExpectedTime -> "a time"
    tomlet.ExpectedDateTime -> "a date-time"
  }
}

fn describe_edit_error(error: tomlet.EditError) -> String {
  case error {
    tomlet.EmptyKeyPath -> "empty key path"
    tomlet.InvalidKeySegment(segment) -> "invalid key segment: " <> segment
    tomlet.InvalidCommentText -> "comment contains forbidden characters"
    tomlet.MissingEditKey(key) -> "key not found: " <> path_to_string(key)
    tomlet.KeyConflict(key) -> "key conflict at: " <> path_to_string(key)
    tomlet.InlineTableInsertUnsupported(key) ->
      "cannot insert into inline table at: " <> path_to_string(key)
    tomlet.InvalidValue -> "value cannot be represented in this context"
  }
}

fn describe_semver_error(error: semver.SemverError) -> String {
  case error {
    semver.InvalidVersion(text) ->
      "not a valid semver (expected N.N.N): " <> text
    semver.InvalidPart(text) ->
      "unknown bump part (expected major|minor|patch): " <> text
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: PASS — all app_error tests green (semver tests still green too).

- [ ] **Step 5: Commit**

```bash
git add examples/gleam_toml_manager/src/gleam_toml_manager/app_error.gleam examples/gleam_toml_manager/test/app_error_test.gleam
git commit -m "feat: add unified AppError rendering to gleam_toml_manager example"
```

---

## Task 4: commands — bump

**Files:**
- Create: `examples/gleam_toml_manager/src/gleam_toml_manager/commands.gleam`
- Test: `examples/gleam_toml_manager/test/commands_test.gleam`

- [ ] **Step 1: Write the failing tests**

Create `examples/gleam_toml_manager/test/commands_test.gleam`:

```gleam
import gleam/string
import gleam_toml_manager/app_error
import gleam_toml_manager/commands
import gleam_toml_manager/semver
import gleeunit/should
import tomlet

const sample = "# Project metadata\nname = \"demo_app\"\nversion = \"1.2.3\"  # current\n\n[dependencies]\ngleam_stdlib = \">= 0.44.0\"\n"

fn parse(input: String) -> tomlet.Document {
  let assert Ok(doc) = tomlet.parse(input)
  doc
}

pub fn bump_minor_updates_version_test() {
  let assert Ok(doc) = commands.bump(parse(sample), "minor")
  tomlet.get_string(doc, ["version"])
  |> should.equal(Ok("1.3.0"))
}

pub fn bump_preserves_existing_comments_test() {
  let assert Ok(doc) = commands.bump(parse(sample), "patch")
  let output = tomlet.to_string(doc)
  should.be_true(string.contains(output, "# Project metadata"))
  should.be_true(string.contains(output, "# current"))
}

pub fn bump_adds_annotation_comment_test() {
  let assert Ok(doc) = commands.bump(parse(sample), "major")
  let output = tomlet.to_string(doc)
  should.be_true(string.contains(
    output,
    "bumped to 2.0.0 by gleam_toml_manager",
  ))
}

pub fn bump_non_semver_version_errors_test() {
  let doc = parse("version = \"not-semver\"\n")
  commands.bump(doc, "minor")
  |> should.equal(Error(app_error.SemverError(semver.InvalidVersion("not-semver"))))
}

pub fn bump_unknown_part_errors_test() {
  commands.bump(parse(sample), "huge")
  |> should.equal(Error(app_error.SemverError(semver.InvalidPart("huge"))))
}

pub fn bump_missing_version_errors_test() {
  let doc = parse("name = \"x\"\n")
  commands.bump(doc, "minor")
  |> should.equal(Error(app_error.GetError(tomlet.KeyNotFound(["version"]))))
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: FAIL — `commands` module does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `examples/gleam_toml_manager/src/gleam_toml_manager/commands.gleam`:

```gleam
import gleam/result
import gleam_toml_manager/app_error.{type AppError}
import gleam_toml_manager/semver
import tomlet

/// Bump the `version` key (`major`|`minor`|`patch`) and annotate the change
/// with a leading comment, preserving all surrounding trivia.
pub fn bump(
  doc: tomlet.Document,
  part_text: String,
) -> Result(tomlet.Document, AppError) {
  use part <- result.try(
    semver.part_from_string(part_text)
    |> result.map_error(app_error.SemverError),
  )
  use current <- result.try(
    tomlet.get_string(doc, ["version"])
    |> result.map_error(app_error.GetError),
  )
  use version <- result.try(
    semver.parse(current)
    |> result.map_error(app_error.SemverError),
  )
  let next = semver.to_string(semver.bump(version, part))
  use doc <- result.try(
    tomlet.set_string(doc, ["version"], next)
    |> result.map_error(app_error.EditError),
  )
  tomlet.insert_comment_before(
    doc,
    ["version"],
    "bumped to " <> next <> " by gleam_toml_manager",
  )
  |> result.map_error(app_error.EditError)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: PASS — all bump tests green.

- [ ] **Step 5: Commit**

```bash
git add examples/gleam_toml_manager/src/gleam_toml_manager/commands.gleam examples/gleam_toml_manager/test/commands_test.gleam
git commit -m "feat: add bump command logic to gleam_toml_manager example"
```

---

## Task 5: commands — add-dep and remove-dep

**Files:**
- Modify: `examples/gleam_toml_manager/src/gleam_toml_manager/commands.gleam`
- Modify: `examples/gleam_toml_manager/test/commands_test.gleam`

- [ ] **Step 1: Add the failing tests**

Append these tests to `examples/gleam_toml_manager/test/commands_test.gleam` (the `sample`, `parse`, and imports already exist from Task 4):

```gleam
pub fn add_dependency_inserts_new_key_test() {
  let assert Ok(doc) = commands.add_dependency(parse(sample), "wisp", ">= 1.0.0")
  tomlet.get_string(doc, ["dependencies", "wisp"])
  |> should.equal(Ok(">= 1.0.0"))
}

pub fn add_dependency_preserves_existing_test() {
  let assert Ok(doc) = commands.add_dependency(parse(sample), "wisp", ">= 1.0.0")
  tomlet.get_string(doc, ["dependencies", "gleam_stdlib"])
  |> should.equal(Ok(">= 0.44.0"))
}

pub fn remove_dependency_deletes_key_test() {
  let assert Ok(doc) =
    commands.remove_dependency(parse(sample), "gleam_stdlib")
  tomlet.get(doc, ["dependencies", "gleam_stdlib"])
  |> should.equal(Error(tomlet.KeyNotFound(["dependencies", "gleam_stdlib"])))
}

pub fn remove_missing_dependency_errors_test() {
  commands.remove_dependency(parse(sample), "nope")
  |> should.equal(
    Error(app_error.EditError(tomlet.MissingEditKey(["dependencies", "nope"]))),
  )
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: FAIL — `commands.add_dependency` / `commands.remove_dependency` not defined.

- [ ] **Step 3: Add the implementation**

Append to `examples/gleam_toml_manager/src/gleam_toml_manager/commands.gleam`:

```gleam
/// Add or replace a dependency under `[dependencies]`, creating that table if
/// it does not yet exist.
pub fn add_dependency(
  doc: tomlet.Document,
  name: String,
  version: String,
) -> Result(tomlet.Document, AppError) {
  tomlet.set_string(doc, ["dependencies", name], version)
  |> result.map_error(app_error.EditError)
}

/// Remove a dependency under `[dependencies]`.
pub fn remove_dependency(
  doc: tomlet.Document,
  name: String,
) -> Result(tomlet.Document, AppError) {
  tomlet.remove(doc, ["dependencies", name])
  |> result.map_error(app_error.EditError)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: PASS — add/remove dependency tests green.

- [ ] **Step 5: Commit**

```bash
git add examples/gleam_toml_manager/src/gleam_toml_manager/commands.gleam examples/gleam_toml_manager/test/commands_test.gleam
git commit -m "feat: add dependency add/remove logic to gleam_toml_manager example"
```

---

## Task 6: commands — get/set path and value display

**Files:**
- Modify: `examples/gleam_toml_manager/src/gleam_toml_manager/commands.gleam`
- Modify: `examples/gleam_toml_manager/test/commands_test.gleam`

- [ ] **Step 1: Add the failing tests**

Append to `examples/gleam_toml_manager/test/commands_test.gleam`:

```gleam
pub fn get_path_reads_value_test() {
  commands.get_path(parse(sample), "name")
  |> should.equal(Ok(tomlet.StringValue("demo_app")))
}

pub fn get_path_nested_test() {
  commands.get_path(parse(sample), "dependencies.gleam_stdlib")
  |> should.equal(Ok(tomlet.StringValue(">= 0.44.0")))
}

pub fn get_path_missing_errors_test() {
  commands.get_path(parse(sample), "nope")
  |> should.equal(Error(app_error.GetError(tomlet.KeyNotFound(["nope"]))))
}

pub fn set_path_writes_value_test() {
  let assert Ok(doc) = commands.set_path(parse(sample), "name", "renamed")
  tomlet.get_string(doc, ["name"])
  |> should.equal(Ok("renamed"))
}

pub fn value_to_display_string_test() {
  commands.value_to_display(tomlet.StringValue("hello"))
  |> should.equal("hello")
}

pub fn value_to_display_int_test() {
  commands.value_to_display(tomlet.IntValue(42))
  |> should.equal("42")
}

pub fn value_to_display_bool_test() {
  commands.value_to_display(tomlet.BoolValue(True))
  |> should.equal("true")
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: FAIL — `commands.get_path` / `commands.set_path` / `commands.value_to_display` not defined.

- [ ] **Step 3: Add the implementation**

Add `import gleam/float`, `import gleam/int`, and `import gleam/string` to the top of `commands.gleam` (keep the existing imports), then append:

```gleam
/// Split a dotted path string into a tomlet key path.
pub fn split_path(path: String) -> List(String) {
  string.split(path, ".")
}

/// Read the value at a dotted path (read-only).
pub fn get_path(
  doc: tomlet.Document,
  path: String,
) -> Result(tomlet.Value, AppError) {
  tomlet.get(doc, split_path(path))
  |> result.map_error(app_error.GetError)
}

/// Set a string value at a dotted path.
pub fn set_path(
  doc: tomlet.Document,
  path: String,
  value: String,
) -> Result(tomlet.Document, AppError) {
  tomlet.set_string(doc, split_path(path), value)
  |> result.map_error(app_error.EditError)
}

/// Render a value for terminal display. Scalars print their value; structural
/// values print a typed placeholder.
pub fn value_to_display(value: tomlet.Value) -> String {
  case value {
    tomlet.StringValue(s) -> s
    tomlet.IntValue(i) -> int.to_string(i)
    tomlet.FloatValue(f) -> float.to_string(f)
    tomlet.BoolValue(True) -> "true"
    tomlet.BoolValue(False) -> "false"
    tomlet.DateValue(d) -> tomlet.date_to_string(d)
    tomlet.TimeValue(t) -> tomlet.time_to_string(t)
    tomlet.DateTimeValue(dt) -> tomlet.datetime_to_string(dt)
    tomlet.SpecialFloatValue(_) -> "<special float>"
    tomlet.ArrayValue(_) -> "<array>"
    tomlet.InlineTableValue(_) -> "<inline table>"
    tomlet.StandardTableValue(_) -> "<table>"
    tomlet.ArrayOfTablesValue(_) -> "<array of tables>"
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
cd examples/gleam_toml_manager && gleam test
```

Expected: PASS — get/set/display tests green.

- [ ] **Step 5: Commit**

```bash
git add examples/gleam_toml_manager/src/gleam_toml_manager/commands.gleam examples/gleam_toml_manager/test/commands_test.gleam
git commit -m "feat: add generic get/set path and value display to gleam_toml_manager example"
```

---

## Task 7: glint wiring, IO, and main

**Files:**
- Modify: `examples/gleam_toml_manager/src/gleam_toml_manager.gleam` (replace the placeholder)

This task wires the pure commands to a glint CLI. It is verified by running the CLI, not by unit tests (the command logic is already covered in Tasks 4–6).

- [ ] **Step 1: Replace the entrypoint with the full CLI**

Replace the entire contents of `examples/gleam_toml_manager/src/gleam_toml_manager.gleam` with:

```gleam
import argv
import gleam/io
import gleam/result
import gleam_toml_manager/app_error.{type AppError}
import gleam_toml_manager/commands
import glint
import shellout
import simplifile
import tomlet

pub fn main() {
  glint.new()
  |> glint.with_name("gleam_toml_manager")
  |> glint.pretty_help(glint.default_pretty_help())
  |> glint.global_help(
    "Manage a gleam.toml while preserving comments and key order",
  )
  |> glint.add(at: ["bump"], do: bump_command())
  |> glint.add(at: ["add-dep"], do: add_dep_command())
  |> glint.add(at: ["remove-dep"], do: remove_dep_command())
  |> glint.add(at: ["get"], do: get_command())
  |> glint.add(at: ["set"], do: set_command())
  |> glint.run(argv.load().arguments)
}

// --- shared flags -----------------------------------------------------------

fn file_flag() -> glint.Flag(String) {
  glint.string_flag("file")
  |> glint.flag_default("gleam.toml")
  |> glint.flag_help("Path to the TOML file (default: gleam.toml)")
}

fn dry_run_flag() -> glint.Flag(Bool) {
  glint.bool_flag("dry-run")
  |> glint.flag_default(False)
  |> glint.flag_help("Print the result to stdout instead of writing the file")
}

// --- commands ---------------------------------------------------------------

fn bump_command() -> glint.Command(Nil) {
  use <- glint.command_help("Bump the version: bump <major|minor|patch>")
  use file <- glint.flag(file_flag())
  use dry_run <- glint.flag(dry_run_flag())
  use part <- glint.named_arg("part")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let assert Ok(dry) = dry_run(flags)
  let part_text = part(named)
  run_edit(path, dry, fn(doc) { commands.bump(doc, part_text) })
}

fn add_dep_command() -> glint.Command(Nil) {
  use <- glint.command_help("Add or update a dependency: add-dep <name> <version>")
  use file <- glint.flag(file_flag())
  use dry_run <- glint.flag(dry_run_flag())
  use name <- glint.named_arg("name")
  use version <- glint.named_arg("version")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let assert Ok(dry) = dry_run(flags)
  let dep_name = name(named)
  let dep_version = version(named)
  run_edit(path, dry, fn(doc) {
    commands.add_dependency(doc, dep_name, dep_version)
  })
}

fn remove_dep_command() -> glint.Command(Nil) {
  use <- glint.command_help("Remove a dependency: remove-dep <name>")
  use file <- glint.flag(file_flag())
  use dry_run <- glint.flag(dry_run_flag())
  use name <- glint.named_arg("name")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let assert Ok(dry) = dry_run(flags)
  let dep_name = name(named)
  run_edit(path, dry, fn(doc) { commands.remove_dependency(doc, dep_name) })
}

fn get_command() -> glint.Command(Nil) {
  use <- glint.command_help("Read a value at a dotted path: get <a.b.c>")
  use file <- glint.flag(file_flag())
  use path_arg <- glint.named_arg("path")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let dotted = path_arg(named)
  let outcome = {
    use source <- result.try(read_file(path))
    use doc <- result.try(parse_doc(source))
    commands.get_path(doc, dotted)
  }
  case outcome {
    Ok(value) -> io.println(commands.value_to_display(value))
    Error(error) -> fail(error)
  }
}

fn set_command() -> glint.Command(Nil) {
  use <- glint.command_help("Set a string value at a dotted path: set <a.b.c> <value>")
  use file <- glint.flag(file_flag())
  use dry_run <- glint.flag(dry_run_flag())
  use path_arg <- glint.named_arg("path")
  use value_arg <- glint.named_arg("value")
  use named, _args, flags <- glint.command()
  let assert Ok(path) = file(flags)
  let assert Ok(dry) = dry_run(flags)
  let dotted = path_arg(named)
  let new_value = value_arg(named)
  run_edit(path, dry, fn(doc) { commands.set_path(doc, dotted, new_value) })
}

// --- IO + edit pipeline -----------------------------------------------------

fn run_edit(
  path: String,
  dry_run: Bool,
  edit: fn(tomlet.Document) -> Result(tomlet.Document, AppError),
) -> Nil {
  let outcome = {
    use source <- result.try(read_file(path))
    use doc <- result.try(parse_doc(source))
    use edited <- result.try(edit(doc))
    Ok(tomlet.to_string(edited))
  }
  case outcome {
    Error(error) -> fail(error)
    Ok(text) ->
      case dry_run {
        True -> io.println(text)
        False ->
          case write_file(path, text) {
            Ok(Nil) -> io.println("updated " <> path)
            Error(error) -> fail(error)
          }
      }
  }
}

fn read_file(path: String) -> Result(String, AppError) {
  simplifile.read(from: path)
  |> result.map_error(app_error.FileError)
}

fn write_file(path: String, contents: String) -> Result(Nil, AppError) {
  simplifile.write(to: path, contents: contents)
  |> result.map_error(app_error.FileError)
}

fn parse_doc(source: String) -> Result(tomlet.Document, AppError) {
  tomlet.parse(source)
  |> result.map_error(fn(error) { app_error.ParseError(error, source) })
}

/// Print the error to stderr and terminate with a non-zero status. `shellout.exit`
/// sets the process exit code on both the Erlang and JavaScript targets, so the
/// CLI is usable in pipelines and CI. Successful command paths return `Nil` and
/// let the runtime exit `0` normally.
fn fail(error: AppError) -> Nil {
  io.println_error(app_error.to_message(error))
  shellout.exit(1)
}
```

- [ ] **Step 2: Build on both targets**

Run:

```bash
cd examples/gleam_toml_manager && gleam build --target erlang && gleam build --target javascript
```

Expected: both builds succeed.

> If glint reports an arity/name mismatch on any `glint.*` call, run `gleam deps list | grep glint` to confirm the installed major version, then check that version's docs at https://hexdocs.pm/glint for the exact builder names. The names used here (`new`, `with_name`, `pretty_help`, `default_pretty_help`, `global_help`, `add`, `run`, `command`, `command_help`, `flag`, `named_arg`, `string_flag`, `bool_flag`, `flag_default`, `flag_help`) target glint 1.x.

- [ ] **Step 3: Smoke-test on the Erlang target (dry run, no file mutation)**

Run:

```bash
cd examples/gleam_toml_manager && gleam run --target erlang -- bump minor --file=sample.gleam.toml --dry-run
```

Expected: the printed TOML shows `version = "1.3.0"`, a new `# bumped to 1.3.0 by gleam_toml_manager` line above it, and the original `# Project metadata` / `# keep this in sync...` comments intact.

- [ ] **Step 4: Smoke-test get on the JavaScript target**

Run:

```bash
cd examples/gleam_toml_manager && gleam run --target javascript -- get dependencies.gleam_stdlib --file=sample.gleam.toml
```

Expected: prints `>= 0.44.0 and < 2.0.0`.

- [ ] **Step 5: Smoke-test an error path and its exit code**

Run:

```bash
cd examples/gleam_toml_manager && gleam run -- remove-dep nope --file=sample.gleam.toml --dry-run; echo "exit=$?"
```

Expected: stderr shows `edit error: key not found: dependencies.nope`, `sample.gleam.toml` is unchanged, and the final line is `exit=1`.

> Note: `gleam run` itself returns the script's exit code, so `shellout.exit(1)` propagates through to the shell. If you instead see `exit=0`, confirm `fail` calls `shellout.exit(1)` and that shellout resolved for the current target.

- [ ] **Step 6: Confirm a successful command exits 0**

Run:

```bash
cd examples/gleam_toml_manager && gleam run -- get name --file=sample.gleam.toml; echo "exit=$?"
```

Expected: prints `demo_app` then `exit=0`.

- [ ] **Step 7: Commit**

```bash
git add examples/gleam_toml_manager/src/gleam_toml_manager.gleam
git commit -m "feat: wire glint CLI for gleam_toml_manager example"
```

---

## Task 8: README and final dual-target verification

**Files:**
- Create: `examples/gleam_toml_manager/README.md`

- [ ] **Step 1: Write the README**

Create `examples/gleam_toml_manager/README.md`:

```markdown
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
```

- [ ] **Step 2: Run the full test suite on both targets**

Run:

```bash
cd examples/gleam_toml_manager && gleam test --target erlang && gleam test --target javascript
```

Expected: PASS on both targets.

- [ ] **Step 3: Verify the README example matches real output**

Run:

```bash
cd examples/gleam_toml_manager && gleam run -- bump minor --file=sample.gleam.toml --dry-run
```

Expected: output matches the README's example block. If the trailing comment differs, update the README block to match.

- [ ] **Step 4: Commit**

```bash
git add examples/gleam_toml_manager/README.md
git commit -m "docs: add README for gleam_toml_manager example"
```

---

## Final verification checklist

- [ ] `gleam build --target erlang` and `gleam build --target javascript` both succeed.
- [ ] `gleam test --target erlang` and `gleam test --target javascript` both pass.
- [ ] `bump`, `add-dep`, `remove-dep`, `get`, `set` each work via `gleam run --`.
- [ ] `--dry-run` prints without modifying the file; without it the file is updated.
- [ ] A failing command exits `1` (e.g. `remove-dep nope`); a succeeding command exits `0` — on both targets.
- [ ] Comments and key order survive every edit (verified by `bump --dry-run` output).
- [ ] The `tomlet` library's own `gleam.toml` and dependency graph are unchanged.
```
