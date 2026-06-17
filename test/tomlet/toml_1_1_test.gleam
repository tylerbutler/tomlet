import gleeunit
import tomlet
import tomlet/parser

pub fn main() -> Nil {
  gleeunit.main()
}

// Feature 1 -- multi-line / trailing-comma inline tables
pub fn multiline_inline_table_parses_in_1_1_test() -> Nil {
  let assert Ok(_) =
    parser.parse("t = {\n  a = 1,\n  b = 2,\n}\n", parser.Toml11)
  Nil
}

pub fn multiline_inline_table_rejected_in_1_0_test() -> Nil {
  let assert Error(_) = parser.parse("t = {\n  a = 1,\n}\n", parser.Toml10)
  Nil
}

pub fn trailing_comma_inline_table_parses_in_1_1_test() -> Nil {
  let assert Ok(_) = parser.parse("t = { a = 1, }\n", parser.Toml11)
  Nil
}

pub fn trailing_comma_inline_table_rejected_in_1_0_test() -> Nil {
  let assert Error(_) = parser.parse("t = { a = 1, }\n", parser.Toml10)
  Nil
}

// Feature 2 -- \xHH and \e escapes
pub fn hex_escape_parses_in_1_1_test() -> Nil {
  let assert Ok(_) = parser.parse("s = \"\\x41\"\n", parser.Toml11)
  Nil
}

pub fn escape_char_parses_in_1_1_test() -> Nil {
  let assert Ok(_) = parser.parse("s = \"\\e\"\n", parser.Toml11)
  Nil
}

pub fn hex_escape_rejected_in_1_0_test() -> Nil {
  let assert Error(_) = parser.parse("s = \"\\x41\"\n", parser.Toml10)
  Nil
}

pub fn escape_char_rejected_in_1_0_test() -> Nil {
  let assert Error(_) = parser.parse("s = \"\\e\"\n", parser.Toml10)
  Nil
}

pub fn multiline_hex_escape_parses_in_1_1_test() -> Nil {
  let assert Ok(_) = parser.parse("s = \"\"\"\\x41\\e\"\"\"\n", parser.Toml11)
  Nil
}

pub fn multiline_hex_escape_rejected_in_1_0_test() -> Nil {
  let assert Error(_) = parser.parse("s = \"\"\"\\x41\"\"\"\n", parser.Toml10)
  Nil
}

// Feature 3 -- optional seconds in time/datetime
pub fn optional_seconds_time_parses_in_1_1_test() -> Nil {
  let assert Ok(_) = parser.parse("tm = 13:15\n", parser.Toml11)
  Nil
}

pub fn optional_seconds_datetime_parses_in_1_1_test() -> Nil {
  let assert Ok(_) = parser.parse("dt = 2010-02-03T14:15\n", parser.Toml11)
  Nil
}

pub fn optional_seconds_time_rejected_in_1_0_test() -> Nil {
  let assert Error(_) = parser.parse("tm = 13:15\n", parser.Toml10)
  Nil
}

pub fn optional_seconds_datetime_rejected_in_1_0_test() -> Nil {
  let assert Error(_) = parser.parse("dt = 2010-02-03T14:15\n", parser.Toml10)
  Nil
}

// Round-trip preservation through the public API.
pub fn multiline_inline_table_round_trips_test() -> Nil {
  let input = "t = {\n  a = 1,\n  b = 2,\n}\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
  Nil
}

// Comments may appear on the newlines inside a multi-line inline table, including
// after the closing delimiter of a multi-line string value. The comment-stripping
// pass must preserve string contents and round-trip the source byte-for-byte.
pub fn multiline_inline_table_with_comments_round_trips_test() -> Nil {
  let input =
    "t = {#open\n  a = 1,#trailing\n  #standalone\n  s = \"\"\"\nhi\n\"\"\",#after\n}#close\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
  let assert Ok(1) = tomlet.get_int(doc, ["t", "a"])
  let assert Ok(_) = tomlet.get_string(doc, ["t", "s"])
  Nil
}

pub fn multiline_inline_table_with_comments_rejected_in_1_0_test() -> Nil {
  let assert Error(_) = parser.parse("t = {#c\n  a = 1,\n}\n", parser.Toml10)
  Nil
}

pub fn optional_seconds_round_trips_test() -> Nil {
  let input = "tm = 13:15\ndt = 2010-02-03T14:15\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
  Nil
}

// Escape source text is preserved byte-for-byte through round-trip.
pub fn hex_escape_round_trips_test() -> Nil {
  let input = "s = \"\\x41\\e\"\n"
  let assert Ok(doc) = tomlet.parse(input)
  assert tomlet.to_string(doc) == input
  Nil
}

// The escape decoder produces the correct codepoints. Quoted keys are basic
// strings, and their decoded form is the key used for lookups, so we can observe
// decoding through the public API: "\x41" decodes to "A", "\e" to U+001B.
pub fn hex_escape_decodes_to_codepoint_test() -> Nil {
  let assert Ok(doc) = tomlet.parse("\"\\x41\" = 7\n")
  assert tomlet.get_int(doc, ["A"]) == Ok(7)
  Nil
}

pub fn escape_char_decodes_to_codepoint_test() -> Nil {
  let assert Ok(doc) = tomlet.parse("\"\\e\" = 7\n")
  assert tomlet.get_int(doc, ["\u{001B}"]) == Ok(7)
  Nil
}
