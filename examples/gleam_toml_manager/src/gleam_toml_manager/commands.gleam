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
