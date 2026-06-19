//// Tests that pin every marketing claim made on the tomlet website
//// (`website/src/pages/index.astro`) to verifiable behaviour.
////
//// Each test below quotes the exact claim it guards and cites the section of
//// the landing page it comes from. If a claim on the site changes, the
//// corresponding test should change with it (and vice versa). This module is
//// deliberately redundant with the broader suites in `tomlet_test`,
//// `options_test`, and `toml_1_1_test`; its job is to make the
//// claim-to-coverage mapping explicit and auditable.
////
//// Two site claims are validated by the harness rather than a unit test:
////
////   * "Same Gleam on Erlang & JS" / "identical on Erlang and JavaScript"
////     (hero proof + Ingredients) is covered by running this suite on both
////     targets: `gleam test` and `gleam test --target javascript`.
////   * "validated against the official toml-test corpora" (Ingredients) is
////     covered by `scripts/run_corpus_tests.py`.

import gleeunit
import tomlet

pub fn main() -> Nil {
  gleeunit.main()
}

// ---------------------------------------------------------------------------
// Promise band: `parse(s) |> to_string == s`
//   "An unedited document writes back byte for byte. Comments, key order,
//    string style, integer base, CRLF vs LF: all of it survives the round
//    trip."
// ---------------------------------------------------------------------------

/// Claim: an unedited document writes back byte for byte (the headline
/// `parse(s) |> to_string == s` identity).
pub fn claim_round_trip_is_byte_for_byte_test() {
  let input =
    "# package metadata\n"
    <> "name = \"tomlet\"\n"
    <> "version = 0\n"
    <> "\n"
    <> "[deps]\n"
    <> "gleam_stdlib = \">= 0.34.0\"\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
}

/// Claim: "Comments ... survive the round trip."
pub fn claim_comments_survive_round_trip_test() {
  let input =
    "# leading comment\n"
    <> "version = 1  # trailing comment\n"
    <> "# dangling comment at end\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
}

/// Claim: "key order ... survives the round trip" (no alphabetical
/// re-sorting).
pub fn claim_key_order_survives_round_trip_test() {
  let input = "zebra = 1\napple = 2\nmango = 3\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
}

/// Claim: "string style ... survives the round trip" (basic, literal,
/// multi-line styles are not normalised).
pub fn claim_string_style_survives_round_trip_test() {
  let input =
    "basic = \"a\\tb\"\n"
    <> "literal = 'a\\tb'\n"
    <> "multiline = \"\"\"line one\nline two\"\"\"\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
}

/// Claim: "integer base ... survives the round trip" (hex/octal/binary and
/// underscores are preserved lexically).
pub fn claim_integer_base_survives_round_trip_test() {
  let input =
    "hex = 0xDEAD_BEEF\n"
    <> "octal = 0o755\n"
    <> "binary = 0b1010_0101\n"
    <> "grouped = 1_000_000\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
}

/// Claim: "CRLF vs LF ... survives the round trip."
pub fn claim_crlf_survives_round_trip_test() {
  let input = "# windows file\r\nname = \"tomlet\"\r\nversion = 1\r\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
}

/// Claim (hero lede): tomlet "remembers ... every bit of whitespace" — odd
/// spacing around `=` and blank lines are preserved.
pub fn claim_whitespace_survives_round_trip_test() {
  let input = "spaced    =     1\n\n\ntight=2\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
}

// ---------------------------------------------------------------------------
// Hero proof + Ingredients: "TOML 1.1 by default, strict 1.0 on request"
// ---------------------------------------------------------------------------

/// Claim: "TOML 1.1 by default" — a 1.1-only feature parses without opting in.
pub fn claim_toml_1_1_parses_by_default_test() {
  // Trailing comma in an inline table is a 1.1 feature.
  let assert Ok(_) = tomlet.parse("t = { a = 1, }\n")
  Nil
}

/// Claim: "strict 1.0 on request" — `parse_with(_, Toml10)` rejects 1.1-only
/// syntax.
pub fn claim_strict_1_0_on_request_test() {
  let assert Error(_) = tomlet.parse_with("t = { a = 1, }\n", tomlet.Toml10)
  Nil
}

// ---------------------------------------------------------------------------
// Round-trip demo: set_string only changes the value
//   "Only the value changed. Both comments stayed put."
// ---------------------------------------------------------------------------

/// Claim (round-trip demo): editing a value with `set_string` leaves both the
/// leading and trailing comments exactly where the human left them.
pub fn claim_set_string_keeps_both_comments_test() {
  let input =
    "# published to Hex on each tag\n"
    <> "version = \"1.2.0\"  # keep in sync with the changelog\n"
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(doc) = tomlet.set_string(doc, ["version"], "1.3.0")

  let expected =
    "# published to Hex on each tag\n"
    <> "version = \"1.3.0\"  # keep in sync with the changelog\n"
  assert tomlet.to_string(doc) == expected
}

// ---------------------------------------------------------------------------
// Edit demo: "Edit a value. Leave the file alone."
//   Three checked edits: set_int, remove, insert_comment_before.
//   "The package metadata header never moved, name is untouched, the new
//    comment landed right where you asked, and draft is simply gone."
// ---------------------------------------------------------------------------

/// Claim (edit demo): the three-edit sequence from the homepage produces
/// exactly the "after" file shown on the site.
pub fn claim_edit_demo_matches_after_panel_test() {
  let before =
    "# package metadata\n"
    <> "name = \"tomlet\"\n"
    <> "version = 0\n"
    <> "draft = true\n"
  let assert Ok(doc) = tomlet.parse(before)
  let assert Ok(doc) = tomlet.set_int(doc, ["version"], 1)
  let assert Ok(doc) = tomlet.remove(doc, ["draft"])
  let assert Ok(doc) =
    tomlet.insert_comment_before(doc, ["version"], "first stable release")

  let after =
    "# package metadata\n"
    <> "name = \"tomlet\"\n"
    <> "# first stable release\n"
    <> "version = 1\n"
  assert tomlet.to_string(doc) == after
}

/// Claim (edit demo): `insert_comment_before` lands the comment "right where
/// you asked".
pub fn claim_insert_comment_before_lands_where_asked_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomlet\"\nversion = 1\n")
  let assert Ok(doc) =
    tomlet.insert_comment_before(doc, ["version"], "release line")
  assert tomlet.to_string(doc)
    == "name = \"tomlet\"\n# release line\nversion = 1\n"
}

/// Claim (edit demo): a removed key is "simply gone" while siblings stay.
pub fn claim_remove_deletes_key_keeps_siblings_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomlet\"\ndraft = true\n")
  let assert Ok(doc) = tomlet.remove(doc, ["draft"])
  assert tomlet.to_string(doc) == "name = \"tomlet\"\n"
}

// ---------------------------------------------------------------------------
// Ingredients + Taste: "Typed accessors read by key path" and
//   "every edit returns a Result, so bad paths and type conflicts come back as
//    matchable errors, never panics."
// ---------------------------------------------------------------------------

/// Claim (taste panel): typed accessors take a key path and hand back exactly
/// the type you asked for.
pub fn claim_typed_accessors_read_by_path_test() {
  let input = "title = \"hi\"\nversion = 3\nenabled = true\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.get_string(doc, ["title"]) == Ok("hi")
  assert tomlet.get_int(doc, ["version"]) == Ok(3)
  assert tomlet.get_bool(doc, ["enabled"]) == Ok(True)
}

/// Claim (taste panel): "nested keys use the same path syntax" — a multi-
/// segment list descends into nested tables.
pub fn claim_nested_keys_use_same_path_syntax_test() {
  let assert Ok(doc) = tomlet.parse("[pkg]\nname = \"tomlet\"\n")
  assert tomlet.get_string(doc, ["pkg", "name"]) == Ok("tomlet")
}

/// Claim (Editing you can trust): "type conflicts come back as matchable
/// errors, never panics."
pub fn claim_type_mismatch_is_matchable_error_test() {
  let assert Ok(doc) = tomlet.parse("version = 3\n")
  assert tomlet.get_string(doc, ["version"])
    == Error(tomlet.WrongType(["version"], tomlet.ExpectedString))
}

/// Claim (Editing you can trust): "bad paths ... come back as matchable
/// errors, never panics."
pub fn claim_bad_path_is_matchable_error_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomlet\"\n")
  assert tomlet.get_string(doc, ["missing"])
    == Error(tomlet.KeyNotFound(["missing"]))
}

/// Claim (Editing you can trust): "every edit returns a Result" — both the
/// success and failure paths are `Result` values, not panics.
pub fn claim_every_edit_returns_a_result_test() {
  let assert Ok(doc) = tomlet.parse("version = 1\n")
  let assert Ok(_) = tomlet.set_int(doc, ["version"], 2)
  let assert Error(_) = tomlet.remove(doc, ["missing"])
  Nil
}

// ---------------------------------------------------------------------------
// Taste copy: "dates and times as opaque values with lexical *_to_string
//   helpers."
// ---------------------------------------------------------------------------

/// Claim (taste copy): dates, times, and datetimes are returned as opaque
/// values whose original lexical form is read back through `*_to_string`
/// helpers and round-trips unchanged.
pub fn claim_dates_are_opaque_with_lexical_helpers_test() {
  let input =
    "released = 1979-05-27\n"
    <> "alarm = 07:32:00\n"
    <> "stamp = 1979-05-27T07:32:00Z\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(date) = tomlet.get_date(doc, ["released"])
  let assert Ok(time) = tomlet.get_time(doc, ["alarm"])
  let assert Ok(dt) = tomlet.get_datetime(doc, ["stamp"])

  assert tomlet.date_to_string(date) == "1979-05-27"
  assert tomlet.time_to_string(time) == "07:32:00"
  assert tomlet.datetime_to_string(dt) == "1979-05-27T07:32:00Z"

  // Opaque values still round-trip byte for byte in the document.
  assert tomlet.to_string(doc) == input
}
