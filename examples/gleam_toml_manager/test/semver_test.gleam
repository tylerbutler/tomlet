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
