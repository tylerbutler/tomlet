import gleeunit
import tomlet

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_empty_document_test() {
  let assert Ok(doc) = tomlet.parse("")

  assert tomlet.to_string(doc) == ""
}

pub fn parse_basic_string_and_get_it_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\n")

  assert tomlet.get_string(doc, ["name"]) == Ok("tomato")
}

pub fn parse_basic_int_and_get_it_test() {
  let assert Ok(doc) = tomlet.parse("answer = 42\n")

  assert tomlet.get_int(doc, ["answer"]) == Ok(42)
  assert tomlet.get_string(doc, ["answer"])
    == Error(tomlet.WrongType(["answer"], tomlet.ExpectedString))
}

pub fn get_returns_public_scalar_values_test() {
  let input =
    "name = \"tomato\"\n"
    <> "answer = 42\n"
    <> "enabled = true\n"
    <> "ratio = 3.14\n"
    <> "positive = inf\n"
    <> "negative = -inf\n"
    <> "nan_value = nan\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.get(doc, ["name"]) == Ok(tomlet.StringValue("tomato"))
  assert tomlet.get(doc, ["answer"]) == Ok(tomlet.IntValue(42))
  assert tomlet.get(doc, ["enabled"]) == Ok(tomlet.BoolValue(True))
  assert tomlet.get(doc, ["ratio"]) == Ok(tomlet.FloatValue(3.14))
  assert tomlet.get(doc, ["positive"])
    == Ok(tomlet.SpecialFloatValue(tomlet.PositiveInfinity))
  assert tomlet.get(doc, ["negative"])
    == Ok(tomlet.SpecialFloatValue(tomlet.NegativeInfinity))
  assert tomlet.get(doc, ["nan_value"])
    == Ok(tomlet.SpecialFloatValue(tomlet.NotANumber))
}

pub fn get_returns_key_not_found_for_missing_value_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\n")

  assert tomlet.get(doc, ["missing"]) == Error(tomlet.KeyNotFound(["missing"]))
}

pub fn get_returns_public_date_time_and_array_values_test() {
  let input =
    "local_date = 1979-05-27\n"
    <> "local_time = 07:32:00\n"
    <> "timestamp = 1979-05-27T07:32:00Z\n"
    <> "ports = [8000, 8001, 8002]\n"
    <> "matrix = [[1, 2], [3, 4]]\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(tomlet.DateValue(date)) = tomlet.get(doc, ["local_date"])
  assert tomlet.date_to_string(date) == "1979-05-27"
  let assert Ok(tomlet.TimeValue(time)) = tomlet.get(doc, ["local_time"])
  assert tomlet.time_to_string(time) == "07:32:00"
  let assert Ok(tomlet.DateTimeValue(datetime)) = tomlet.get(doc, ["timestamp"])
  assert tomlet.datetime_to_string(datetime) == "1979-05-27T07:32:00Z"
  assert tomlet.get(doc, ["ports"])
    == Ok(
      tomlet.ArrayValue([
        tomlet.IntValue(8000),
        tomlet.IntValue(8001),
        tomlet.IntValue(8002),
      ]),
    )
  assert tomlet.get(doc, ["matrix"])
    == Ok(
      tomlet.ArrayValue([
        tomlet.ArrayValue([tomlet.IntValue(1), tomlet.IntValue(2)]),
        tomlet.ArrayValue([tomlet.IntValue(3), tomlet.IntValue(4)]),
      ]),
    )
}

pub fn get_returns_public_inline_table_values_test() {
  let input =
    "package = { name = \"tomato\", metadata = { downloads = 42 }, tags = [\"config\"] }\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.get(doc, ["package"])
    == Ok(
      tomlet.InlineTableValue([
        #(["name"], tomlet.StringValue("tomato")),
        #(
          ["metadata"],
          tomlet.InlineTableValue([
            #(["downloads"], tomlet.IntValue(42)),
          ]),
        ),
        #(["tags"], tomlet.ArrayValue([tomlet.StringValue("config")])),
      ]),
    )
  assert tomlet.get(doc, ["package", "metadata", "downloads"])
    == Ok(tomlet.IntValue(42))
}

pub fn get_returns_public_array_of_tables_values_test() {
  let input =
    "[[packages]]\nname = \"tomato\"\n\n[[packages]]\nname = \"carrot\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.get(doc, ["packages"])
    == Ok(
      tomlet.ArrayOfTablesValue([
        [#(["name"], tomlet.StringValue("tomato"))],
        [#(["name"], tomlet.StringValue("carrot"))],
      ]),
    )
}

pub fn get_returns_public_standard_table_values_test() {
  let input = "[package]\nname = \"tomato\"\nversion = \"0.1.0\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.get(doc, ["package"])
    == Ok(
      tomlet.StandardTableValue([
        #(["name"], tomlet.StringValue("tomato")),
        #(["version"], tomlet.StringValue("0.1.0")),
      ]),
    )
}

pub fn parse_error_offsets_use_original_bytes_after_crlf_test() {
  assert tomlet.parse("ok = 1\r\nbad = ???\r\n")
    == Error(tomlet.InvalidSyntax(tomlet.ExpectedValue, 14))
}

pub fn duplicate_key_offsets_use_original_bytes_after_crlf_test() {
  assert tomlet.parse("name = \"one\"\r\nname = \"two\"\r\n")
    == Error(tomlet.DuplicateKey(["name"], 14))
}

pub fn parse_error_offsets_count_utf8_bytes_test() {
  assert tomlet.parse("name = \"é\"\nbad = ???\n")
    == Error(tomlet.InvalidSyntax(tomlet.ExpectedValue, 18))
}

pub fn parse_bytes_accepts_valid_utf8_with_bom_test() {
  let assert Ok(doc) =
    tomlet.parse_bytes(<<
      239,
      187,
      191,
      110,
      97,
      109,
      101,
      32,
      61,
      32,
      34,
      116,
      111,
      109,
      97,
      116,
      111,
      34,
      10,
    >>)

  assert tomlet.get_string(doc, ["name"]) == Ok("tomato")
}

pub fn parse_bytes_rejects_invalid_utf8_test() {
  assert tomlet.parse_bytes(<<110, 97, 109, 101, 32, 61, 32, 255, 10>>)
    == Error(tomlet.InvalidEncoding)
}

pub fn parse_bytes_rejects_utf16_input_test() {
  assert tomlet.parse_bytes(<<254, 255, 0, 110, 0, 97, 0, 109, 0, 101>>)
    == Error(tomlet.InvalidEncoding)
}

pub fn parse_bytes_rejects_bom_not_at_start_test() {
  assert tomlet.parse_bytes(<<
      10,
      239,
      187,
      191,
      110,
      97,
      109,
      101,
      32,
      61,
      32,
      34,
      116,
      111,
      109,
      97,
      116,
      111,
      34,
      10,
    >>)
    == Error(tomlet.InvalidEncoding)
}

pub fn parse_bytes_rejects_bom_at_end_test() {
  assert tomlet.parse_bytes(<<
      110,
      97,
      109,
      101,
      32,
      61,
      32,
      34,
      116,
      111,
      109,
      97,
      116,
      111,
      34,
      10,
      239,
      187,
      191,
    >>)
    == Error(tomlet.InvalidEncoding)
}

pub fn round_trip_basic_scalars_test() {
  let input = "name = \"tomato\"\nanswer = 42\nenabled = true\nratio = 3.14\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.to_string(doc) == input
}

pub fn round_trip_no_space_assignment_test() {
  let input = "answer=42\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.to_string(doc) == input
}

pub fn round_trip_whitespace_only_document_test() {
  let input = " \n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.to_string(doc) == input
}

pub fn round_trip_no_final_newline_test() {
  let input = "answer = 42"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.to_string(doc) == input
}

pub fn round_trip_table_header_test() {
  let input = "[package]\nname = \"tomato\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.to_string(doc) == input
}

pub fn round_trip_comments_and_blank_lines_test() {
  let input = "# package metadata\n\nname = \"tomato\" # inline\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.to_string(doc) == input
}

pub fn round_trip_crlf_line_endings_test() {
  let input = "name = \"tomato\"\r\nanswer = 42\r\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.to_string(doc) == input
}

pub fn missing_key_returns_key_not_found_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\n")

  assert tomlet.get_string(doc, ["missing"])
    == Error(tomlet.KeyNotFound(["missing"]))
}

pub fn insert_comment_before_root_key_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\nversion = \"0.1.0\"\n")

  let assert Ok(updated) =
    tomlet.insert_comment_before(doc, ["version"], "released")

  assert tomlet.to_string(updated)
    == "name = \"tomato\"\n# released\nversion = \"0.1.0\"\n"
}

pub fn insert_comment_before_table_key_test() {
  let input = "[package]\nname = \"tomato\"\n\n[owner]\nname = \"Tyler\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) =
    tomlet.insert_comment_before(doc, ["owner", "name"], "# maintainer")

  assert tomlet.to_string(updated)
    == "[package]\nname = \"tomato\"\n\n[owner]\n# maintainer\nname = \"Tyler\"\n"
}

pub fn insert_comment_before_missing_key_returns_error_test() {
  let input = "# package metadata\n\nname = \"tomato\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.insert_comment_before(doc, ["missing"], "ignored")
    == Error(tomlet.MissingEditKey(["missing"]))
}

pub fn insert_comment_before_preserves_crlf_line_endings_test() {
  let assert Ok(doc) =
    tomlet.parse("name = \"tomato\"\r\nversion = \"0.1.0\"\r\n")

  let assert Ok(updated) =
    tomlet.insert_comment_before(doc, ["version"], "released")

  assert tomlet.to_string(updated)
    == "name = \"tomato\"\r\n# released\r\nversion = \"0.1.0\"\r\n"
}

pub fn set_string_updates_existing_key_preserving_trivia_test() {
  let input = "name = 'old' # inline\nanswer = 42\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_string(doc, ["name"], "tomato")

  assert tomlet.get_string(updated, ["name"]) == Ok("tomato")
  assert tomlet.to_string(updated)
    == "name = \"tomato\" # inline\nanswer = 42\n"
}

pub fn set_int_updates_existing_key_preserving_crlf_test() {
  let input = "name = \"tomato\"\r\nanswer = 41 # inline\r\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_int(doc, ["answer"], 42)

  assert tomlet.get_int(updated, ["answer"]) == Ok(42)
  assert tomlet.to_string(updated)
    == "name = \"tomato\"\r\nanswer = 42 # inline\r\n"
}

pub fn set_bool_updates_existing_key_preserving_trivia_test() {
  let input = "enabled = false # inline\nname = \"tomato\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_bool(doc, ["enabled"], True)

  assert tomlet.get_bool(updated, ["enabled"]) == Ok(True)
  assert tomlet.to_string(updated)
    == "enabled = true # inline\nname = \"tomato\"\n"
}

pub fn set_float_appends_new_key_to_existing_table_test() {
  let input = "[package]\nname = \"tomato\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_float(doc, ["package", "ratio"], 2.5)

  assert tomlet.get_float(updated, ["package", "ratio"]) == Ok(2.5)
  assert tomlet.to_string(updated)
    == "[package]\nname = \"tomato\"\nratio = 2.5\n"
}

pub fn set_bool_updates_existing_inline_table_key_test() {
  let input = "package = { enabled = false, name = \"tomato\" }\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_bool(doc, ["package", "enabled"], True)

  assert tomlet.get_bool(updated, ["package", "enabled"]) == Ok(True)
  assert tomlet.to_string(updated)
    == "package = { enabled = true, name = \"tomato\" }\n"
}

pub fn set_float_updates_existing_key_preserving_crlf_test() {
  let input = "ratio = 1.5 # inline\r\nname = \"tomato\"\r\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_float(doc, ["ratio"], 2.5)

  assert tomlet.get_float(updated, ["ratio"]) == Ok(2.5)
  assert tomlet.to_string(updated)
    == "ratio = 2.5 # inline\r\nname = \"tomato\"\r\n"
}

pub fn set_string_updates_existing_inline_table_key_test() {
  let input = "package = { name = \"tomato\", version = \"0.1.0\" }\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_string(doc, ["package", "name"], "carrot")

  assert tomlet.get_string(updated, ["package", "name"]) == Ok("carrot")
  assert tomlet.get_string(updated, ["package", "version"]) == Ok("0.1.0")
  assert tomlet.to_string(updated)
    == "package = { name = \"carrot\", version = \"0.1.0\" }\n"
}

pub fn set_int_updates_existing_nested_inline_table_key_test() {
  let input = "package = { metadata = { downloads = 41 }, name = \"tomato\" }\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) =
    tomlet.set_int(doc, ["package", "metadata", "downloads"], 42)

  assert tomlet.get_int(updated, ["package", "metadata", "downloads"]) == Ok(42)
  assert tomlet.get_string(updated, ["package", "name"]) == Ok("tomato")
  assert tomlet.to_string(updated)
    == "package = { metadata = { downloads = 42 }, name = \"tomato\" }\n"
}

pub fn set_string_updates_deeply_nested_inline_table_key_test() {
  let input =
    "package = { metadata = { release = { owner = { name = \"tomato\" } } } }\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) =
    tomlet.set_string(
      doc,
      ["package", "metadata", "release", "owner", "name"],
      "carrot",
    )

  assert tomlet.get_string(updated, [
      "package",
      "metadata",
      "release",
      "owner",
      "name",
    ])
    == Ok("carrot")
  assert tomlet.to_string(updated)
    == "package = { metadata = { release = { owner = { name = \"carrot\" } } } }\n"
}

pub fn set_string_updates_inline_table_inside_standard_table_test() {
  let input = "[package]\nmetadata = { release = { name = \"tomato\" } }\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) =
    tomlet.set_string(doc, ["package", "metadata", "release", "name"], "carrot")

  assert tomlet.get_string(updated, ["package", "metadata", "release", "name"])
    == Ok("carrot")
  assert tomlet.to_string(updated)
    == "[package]\nmetadata = { release = { name = \"carrot\" } }\n"
}

pub fn set_string_updates_dotted_key_inside_inline_table_test() {
  let input = "package = { metadata.name = \"tomato\" }\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) =
    tomlet.set_string(doc, ["package", "metadata", "name"], "carrot")

  assert tomlet.get_string(updated, ["package", "metadata", "name"])
    == Ok("carrot")
  assert tomlet.to_string(updated)
    == "package = { metadata.name = \"carrot\" }\n"
}

pub fn set_string_missing_inline_table_key_returns_unsupported_test() {
  let input = "package = { name = \"tomato\" }\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.set_string(doc, ["package", "version"], "0.1.0")
    == Error(tomlet.InlineTableInsertUnsupported(["package", "version"]))
}

pub fn set_string_appends_new_root_key_before_tables_test() {
  let input = "[package]\nname = \"tomato\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_string(doc, ["version"], "1.0.0")

  assert tomlet.get_string(updated, ["version"]) == Ok("1.0.0")
  assert tomlet.to_string(updated)
    == "version = \"1.0.0\"\n[package]\nname = \"tomato\"\n"
}

pub fn set_int_appends_new_key_to_existing_table_test() {
  let input = "[package]\nname = \"tomato\"\n[other]\nenabled = true\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.set_int(doc, ["package", "downloads"], 123)

  assert tomlet.get_int(updated, ["package", "downloads"]) == Ok(123)
  assert tomlet.to_string(updated)
    == "[package]\nname = \"tomato\"\ndownloads = 123\n[other]\nenabled = true\n"
}

pub fn set_string_escapes_basic_string_control_characters_test() {
  let assert Ok(updated) =
    tomlet.set_string(
      tomlet.new(),
      ["text"],
      "a\u{0008}b\u{000c}c\u{0001}d\u{007f}e",
    )

  assert tomlet.to_string(updated) == "text = \"a\\bb\\fc\\u0001d\\u007Fe\"\n"
}

pub fn set_string_returns_conflict_for_array_table_parent_test() {
  let input = "[[packages]]\nname = \"first\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.set_string(doc, ["packages", "version"], "1.0.0")
    == Error(tomlet.KeyConflict(["packages", "version"]))
}

pub fn set_string_conflicting_array_table_reports_error_test() {
  let input = "[[packages]]\nname=\"first\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.set_string(doc, ["packages", "version"], "1.0.0")
    == Error(tomlet.KeyConflict(["packages", "version"]))
}

pub fn set_string_returns_conflict_for_scalar_parent_test() {
  let input = "package.name = \"tomato\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.set_string(doc, ["package", "name", "version"], "1.0.0")
    == Error(tomlet.KeyConflict(["package", "name", "version"]))
}

pub fn remove_root_key_preserves_unrelated_trivia_test() {
  let input = "# before\nname = \"tomato\" # inline\n\nanswer = 42\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.remove(doc, ["name"])

  assert tomlet.to_string(updated) == "# before\n\nanswer = 42\n"
  assert tomlet.get_string(updated, ["name"])
    == Error(tomlet.KeyNotFound(["name"]))
}

pub fn remove_table_key_preserves_header_and_order_test() {
  let input =
    "name = \"root\"\n\n[package]\n# package name\nname = \"tomato\"\nversion = \"1.0.0\"\n\n[owner]\nname = \"Tyler\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  let assert Ok(updated) = tomlet.remove(doc, ["package", "name"])

  assert tomlet.to_string(updated)
    == "name = \"root\"\n\n[package]\n# package name\nversion = \"1.0.0\"\n\n[owner]\nname = \"Tyler\"\n"
  assert tomlet.get_string(updated, ["name"]) == Ok("root")
  assert tomlet.get_string(updated, ["owner", "name"]) == Ok("Tyler")
  assert tomlet.get_string(updated, ["package", "name"])
    == Error(tomlet.KeyNotFound(["package", "name"]))
}

pub fn remove_missing_key_returns_error_test() {
  let input = "name = \"tomato\"\n[package]\nversion = \"1.0.0\"\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.remove(doc, ["package", "missing"])
    == Error(tomlet.MissingEditKey(["package", "missing"]))
}

pub fn remove_missing_key_reports_error_test() {
  let input = "answer=42\n"
  let assert Ok(doc) = tomlet.parse(input)

  assert tomlet.remove(doc, ["missing"])
    == Error(tomlet.MissingEditKey(["missing"]))
}

pub fn remove_preserves_crlf_line_endings_test() {
  let input = "name = \"tomato\"\r\nanswer = 42\r\n"
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(updated) = tomlet.remove(doc, ["name"])
  assert tomlet.to_string(updated) == "answer = 42\r\n"
}

pub fn edit_apis_reject_empty_key_path_test() {
  assert tomlet.set_string(tomlet.new(), [], "tomato")
    == Error(tomlet.EmptyKeyPath)
  assert tomlet.set_bool(tomlet.new(), [], True) == Error(tomlet.EmptyKeyPath)
  assert tomlet.set_float(tomlet.new(), [], 1.5) == Error(tomlet.EmptyKeyPath)
  assert tomlet.remove(tomlet.new(), []) == Error(tomlet.EmptyKeyPath)
}

pub fn set_string_rejects_newline_key_segment_test() {
  assert tomlet.set_string(tomlet.new(), ["bad\nkey"], "tomato")
    == Error(tomlet.InvalidKeySegment("bad\nkey"))
}

pub fn insert_comment_before_rejects_multiline_comment_text_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\n")

  assert tomlet.insert_comment_before(doc, ["name"], "safe\ninjected = true")
    == Error(tomlet.InvalidCommentText)
}

pub fn insert_comment_before_rejects_forbidden_control_characters_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\n")

  assert tomlet.insert_comment_before(doc, ["name"], "\u{0000}danger")
    == Error(tomlet.InvalidCommentText)
  assert tomlet.insert_comment_before(doc, ["name"], "\u{001f}danger")
    == Error(tomlet.InvalidCommentText)
  assert tomlet.insert_comment_before(doc, ["name"], "\u{007f}danger")
    == Error(tomlet.InvalidCommentText)
}

pub fn insert_comment_before_allows_tab_in_comment_text_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\n")

  let assert Ok(updated) =
    tomlet.insert_comment_before(doc, ["name"], "safe\tcomment")

  assert tomlet.to_string(updated) == "# safe\tcomment\nname = \"tomato\"\n"
}

pub fn insert_comment_before_allows_printable_unicode_comment_text_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\n")

  let assert Ok(updated) =
    tomlet.insert_comment_before(doc, ["name"], "safe tomato 🍅")

  assert tomlet.to_string(updated) == "# safe tomato 🍅\nname = \"tomato\"\n"
}

pub fn set_string_quotes_non_bare_key_segments_test() {
  let assert Ok(updated) =
    tomlet.set_string(tomlet.new(), ["package name"], "tomato")

  assert tomlet.to_string(updated) == "\"package name\" = \"tomato\"\n"
}

pub fn set_string_escapes_quoted_key_segments_test() {
  let assert Ok(updated) =
    tomlet.set_string(tomlet.new(), ["quoted \" package"], "tomato")

  assert tomlet.to_string(updated) == "\"quoted \\\" package\" = \"tomato\"\n"
}

// --- Issue #13: typed date/time/datetime getters ---

pub fn get_date_reads_date_value_test() {
  let assert Ok(doc) = tomlet.parse("released = 1979-05-27\n")
  let assert Ok(date) = tomlet.get_date(doc, ["released"])
  assert tomlet.date_to_string(date) == "1979-05-27"
}

pub fn get_date_wrong_type_test() {
  let assert Ok(doc) = tomlet.parse("released = \"1979-05-27\"\n")
  assert tomlet.get_date(doc, ["released"])
    == Error(tomlet.WrongType(["released"], tomlet.ExpectedDate))
}

pub fn get_date_missing_test() {
  let assert Ok(doc) = tomlet.parse("")
  assert tomlet.get_date(doc, ["missing"])
    == Error(tomlet.KeyNotFound(["missing"]))
}

pub fn get_time_reads_time_value_test() {
  let assert Ok(doc) = tomlet.parse("alarm = 07:32:00\n")
  let assert Ok(time) = tomlet.get_time(doc, ["alarm"])
  assert tomlet.time_to_string(time) == "07:32:00"
}

pub fn get_time_wrong_type_test() {
  let assert Ok(doc) = tomlet.parse("alarm = 1\n")
  assert tomlet.get_time(doc, ["alarm"])
    == Error(tomlet.WrongType(["alarm"], tomlet.ExpectedTime))
}

pub fn get_datetime_reads_datetime_value_test() {
  let assert Ok(doc) = tomlet.parse("timestamp = 1979-05-27T07:32:00Z\n")
  let assert Ok(dt) = tomlet.get_datetime(doc, ["timestamp"])
  assert tomlet.datetime_to_string(dt) == "1979-05-27T07:32:00Z"
}

pub fn get_datetime_wrong_type_test() {
  let assert Ok(doc) = tomlet.parse("timestamp = 1979-05-27\n")
  assert tomlet.get_datetime(doc, ["timestamp"])
    == Error(tomlet.WrongType(["timestamp"], tomlet.ExpectedDateTime))
}

// --- Issue #12: typed date/time/datetime setters ---

pub fn date_from_string_valid_test() {
  let assert Ok(date) = tomlet.date_from_string("1979-05-27")
  assert tomlet.date_to_string(date) == "1979-05-27"
}

pub fn date_from_string_invalid_test() {
  assert tomlet.date_from_string("not-a-date")
    == Error(tomlet.InvalidDate("not-a-date"))
}

pub fn time_from_string_valid_test() {
  let assert Ok(time) = tomlet.time_from_string("07:32:00")
  assert tomlet.time_to_string(time) == "07:32:00"
}

pub fn time_from_string_invalid_test() {
  assert tomlet.time_from_string("25:00:00")
    == Error(tomlet.InvalidTime("25:00:00"))
}

pub fn datetime_from_string_valid_test() {
  let assert Ok(dt) = tomlet.datetime_from_string("1979-05-27T07:32:00Z")
  assert tomlet.datetime_to_string(dt) == "1979-05-27T07:32:00Z"
}

pub fn datetime_from_string_invalid_test() {
  assert tomlet.datetime_from_string("bogus")
    == Error(tomlet.InvalidDateTime("bogus"))
}

pub fn set_date_inserts_new_key_test() {
  let assert Ok(date) = tomlet.date_from_string("1979-05-27")
  let assert Ok(updated) = tomlet.set_date(tomlet.new(), ["released"], date)

  assert tomlet.to_string(updated) == "released = 1979-05-27\n"
  let assert Ok(read) = tomlet.get_date(updated, ["released"])
  assert tomlet.date_to_string(read) == "1979-05-27"
}

pub fn set_time_replaces_existing_value_test() {
  let assert Ok(doc) = tomlet.parse("alarm = 06:00:00\n")
  let assert Ok(time) = tomlet.time_from_string("07:32:00")
  let assert Ok(updated) = tomlet.set_time(doc, ["alarm"], time)

  assert tomlet.to_string(updated) == "alarm = 07:32:00\n"
}

pub fn set_datetime_replaces_existing_value_test() {
  let assert Ok(doc) = tomlet.parse("timestamp = 1970-01-01T00:00:00Z\n")
  let assert Ok(dt) = tomlet.datetime_from_string("1979-05-27T07:32:00Z")
  let assert Ok(updated) = tomlet.set_datetime(doc, ["timestamp"], dt)

  assert tomlet.to_string(updated) == "timestamp = 1979-05-27T07:32:00Z\n"
}

// --- Issue #12: set_array, set_inline_table, append_array_of_tables ---

pub fn set_array_inserts_new_homogeneous_array_test() {
  let assert Ok(updated) =
    tomlet.set_array(tomlet.new(), ["ports"], [
      tomlet.IntValue(8000),
      tomlet.IntValue(8001),
    ])

  assert tomlet.to_string(updated) == "ports = [8000, 8001]\n"
  assert tomlet.get(updated, ["ports"])
    == Ok(tomlet.ArrayValue([tomlet.IntValue(8000), tomlet.IntValue(8001)]))
}

pub fn set_array_replaces_existing_array_test() {
  let assert Ok(doc) = tomlet.parse("ports = [1, 2, 3]\n")
  let assert Ok(updated) =
    tomlet.set_array(doc, ["ports"], [tomlet.StringValue("a")])

  assert tomlet.to_string(updated) == "ports = [\"a\"]\n"
}

pub fn set_array_supports_nested_arrays_test() {
  let assert Ok(updated) =
    tomlet.set_array(tomlet.new(), ["matrix"], [
      tomlet.ArrayValue([tomlet.IntValue(1), tomlet.IntValue(2)]),
      tomlet.ArrayValue([tomlet.IntValue(3), tomlet.IntValue(4)]),
    ])

  assert tomlet.to_string(updated) == "matrix = [[1, 2], [3, 4]]\n"
}

pub fn set_array_rejects_standard_table_value_test() {
  assert tomlet.set_array(tomlet.new(), ["items"], [
      tomlet.StandardTableValue([#(["name"], tomlet.StringValue("tomato"))]),
    ])
    == Error(tomlet.InvalidValue)
}

pub fn set_array_rejects_array_of_tables_value_test() {
  assert tomlet.set_array(tomlet.new(), ["items"], [
      tomlet.ArrayOfTablesValue([[#(["name"], tomlet.StringValue("tomato"))]]),
    ])
    == Error(tomlet.InvalidValue)
}

pub fn set_array_empty_test() {
  let assert Ok(updated) = tomlet.set_array(tomlet.new(), ["xs"], [])
  assert tomlet.to_string(updated) == "xs = []\n"
}

pub fn set_inline_table_inserts_new_entry_test() {
  let assert Ok(updated) =
    tomlet.set_inline_table(tomlet.new(), ["package"], [
      #(["name"], tomlet.StringValue("tomato")),
      #(["version"], tomlet.StringValue("0.1.0")),
    ])

  assert tomlet.to_string(updated)
    == "package = { name = \"tomato\", version = \"0.1.0\" }\n"
}

pub fn set_inline_table_supports_dotted_keys_test() {
  let assert Ok(updated) =
    tomlet.set_inline_table(tomlet.new(), ["pkg"], [
      #(["meta", "downloads"], tomlet.IntValue(42)),
    ])

  assert tomlet.to_string(updated) == "pkg = { meta.downloads = 42 }\n"
}

pub fn set_inline_table_rejects_duplicate_entry_paths_test() {
  assert tomlet.set_inline_table(tomlet.new(), ["pkg"], [
      #(["name"], tomlet.StringValue("tomato")),
      #(["name"], tomlet.StringValue("carrot")),
    ])
    == Error(tomlet.KeyConflict(["name"]))
}

pub fn set_inline_table_rejects_parent_child_entry_conflicts_test() {
  assert tomlet.set_inline_table(tomlet.new(), ["pkg"], [
      #(["metadata"], tomlet.StringValue("tomato")),
      #(["metadata", "downloads"], tomlet.IntValue(42)),
    ])
    == Error(tomlet.KeyConflict(["metadata", "downloads"]))
}

pub fn set_inline_table_empty_test() {
  let assert Ok(updated) = tomlet.set_inline_table(tomlet.new(), ["p"], [])
  assert tomlet.to_string(updated) == "p = {}\n"
}

pub fn append_array_of_tables_creates_first_table_test() {
  let assert Ok(updated) =
    tomlet.append_array_of_tables(tomlet.new(), ["packages"], [
      #(["name"], tomlet.StringValue("tomato")),
    ])

  assert tomlet.to_string(updated) == "[[packages]]\nname = \"tomato\"\n"
}

pub fn append_array_of_tables_appends_to_existing_test() {
  let input = "[[packages]]\nname = \"tomato\"\n"
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(updated) =
    tomlet.append_array_of_tables(doc, ["packages"], [
      #(["name"], tomlet.StringValue("carrot")),
    ])

  assert tomlet.to_string(updated)
    == "[[packages]]\nname = \"tomato\"\n[[packages]]\nname = \"carrot\"\n"
  assert tomlet.get(updated, ["packages"])
    == Ok(
      tomlet.ArrayOfTablesValue([
        [#(["name"], tomlet.StringValue("tomato"))],
        [#(["name"], tomlet.StringValue("carrot"))],
      ]),
    )
}

pub fn append_array_of_tables_rejects_duplicate_entry_paths_test() {
  assert tomlet.append_array_of_tables(tomlet.new(), ["packages"], [
      #(["name"], tomlet.StringValue("tomato")),
      #(["name"], tomlet.StringValue("carrot")),
    ])
    == Error(tomlet.KeyConflict(["name"]))
}
