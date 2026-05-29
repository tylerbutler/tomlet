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
      "duplicate key "
      <> path_to_string(key)
      <> " at "
      <> position(source, offset)
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
