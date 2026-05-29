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
  |> should.equal(
    Error(app_error.SemverError(semver.InvalidVersion("not-semver"))),
  )
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
  let assert Ok(doc) = commands.remove_dependency(parse(sample), "gleam_stdlib")
  tomlet.get(doc, ["dependencies", "gleam_stdlib"])
  |> should.equal(Error(tomlet.KeyNotFound(["dependencies", "gleam_stdlib"])))
}

pub fn remove_missing_dependency_errors_test() {
  commands.remove_dependency(parse(sample), "nope")
  |> should.equal(
    Error(app_error.EditError(tomlet.MissingEditKey(["dependencies", "nope"]))),
  )
}

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
