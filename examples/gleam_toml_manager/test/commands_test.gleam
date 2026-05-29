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
