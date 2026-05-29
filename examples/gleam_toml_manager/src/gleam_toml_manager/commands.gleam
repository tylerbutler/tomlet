import gleam/float
import gleam/int
import gleam/result
import gleam/string
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
