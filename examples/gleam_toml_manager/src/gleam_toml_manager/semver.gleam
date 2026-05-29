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
