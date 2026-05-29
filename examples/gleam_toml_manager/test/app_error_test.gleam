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
