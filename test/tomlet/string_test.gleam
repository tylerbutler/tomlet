import gleam/dynamic/decode
import gleam/list
import gleam/result
import gleam/string
import tomlet

pub fn issue_66_description_test() -> Nil {
  assert_string("\"Caf\\u00e9 \\\"x\\\"\"", "Caf\u{00E9} \"x\"")
}

pub fn basic_string_escapes_test() -> Nil {
  let cases = [
    #("\\b", "\u{0008}"),
    #("\\t", "\t"),
    #("\\n", "\n"),
    #("\\f", "\u{000C}"),
    #("\\r", "\r"),
    #("\\\"", "\""),
    #("\\\\", "\\"),
    #("\\u00E9", "\u{00E9}"),
    #("\\U0001F600", "\u{1F600}"),
    #("\\u0000", "\u{0000}"),
    #("\\uD7FF", "\u{D7FF}"),
    #("\\uE000", "\u{E000}"),
    #("\\U0010FFFF", "\u{10FFFF}"),
    #("\\\\n", "\\n"),
    #("\\\\u0041", "\\u0041"),
    #("\\u005Cn", "\\n"),
  ]
  list.each(cases, fn(pair) {
    let #(source, expected) = pair
    list.each(["\"", "\"\"\""], fn(delimiter) {
      assert_string(delimiter <> source <> delimiter, expected)
    })
  })
}

pub fn toml_1_1_string_escapes_test() -> Nil {
  list.each(
    [#("\\e", "\u{001B}"), #("\\x41", "A"), #("\\xE9", "\u{00E9}")],
    fn(pair) {
      let #(source, expected) = pair
      list.each(["\"", "\"\"\""], fn(delimiter) {
        let literal = delimiter <> source <> delimiter
        assert_string_with(literal, expected, tomlet.Toml11)
        let input = "value = " <> literal <> "\n"
        let assert Error(_) = tomlet.parse_with(input, tomlet.Toml10)
        let assert Error(_) = tomlet.parse_dynamic_with(input, tomlet.Toml10)
        let assert Error(tomlet.DecodeParseError(_)) =
          tomlet.decode_with(
            input,
            tomlet.Toml10,
            decode.at(["value"], decode.string),
          )
      })
    },
  )
}

pub fn invalid_string_escapes_test() -> Nil {
  list.each(
    [
      "\\q", "\\uD800", "\\uDFFF", "\\U0000D800", "\\U00110000", "\\UFFFFFFFF",
      "\\u123", "\\U1234567", "\\u00GG", "\\U0000000G", "\\x", "\\x4", "\\xGG",
    ],
    fn(source) {
      list.each(["\"", "\"\"\""], fn(delimiter) {
        let input = "value = " <> delimiter <> source <> delimiter <> "\n"
        list.each([tomlet.Toml10, tomlet.Toml11], fn(version) {
          assert tomlet.parse_with(input, version)
            == Error(tomlet.InvalidSyntax(tomlet.ExpectedValue, 8))
        })
      })
    },
  )
}

pub fn literal_strings_keep_backslashes_test() -> Nil {
  assert_string("'\\n\\u0041\\e\\x41'", "\\n\\u0041\\e\\x41")
  assert_string(
    "'''\n\\n\\u0041\\e\\x41\\\n  next'''",
    "\\n\\u0041\\e\\x41\\\n  next",
  )
}

pub fn multiline_initial_newline_test() -> Nil {
  list.each(["\"\"\"", "'''"], fn(delimiter) {
    list.each(
      [
        #("", ""),
        #("\n", ""),
        #("\n\ntext\n", "\ntext\n"),
        #("text\n", "text\n"),
        #(" \ntext", " \ntext"),
        #("\n  text\n  next", "  text\n  next"),
      ],
      fn(pair) {
        let #(source, expected) = pair
        assert_string(delimiter <> source <> delimiter, expected)
      },
    )
  })
}

pub fn empty_strings_and_multiline_quotes_test() -> Nil {
  assert_string("\"\"", "")
  assert_string("''", "")
  assert_string("\"\"\"text\"\"\"\"", "text\"")
  assert_string("\"\"\"text\"\"\"\"\"", "text\"\"")
  assert_string("'''text''''", "text'")
  assert_string("'''text'''''", "text''")
}

pub fn multiline_basic_continuations_test() -> Nil {
  list.each(
    [
      #("one\\\n  two", "onetwo"),
      #("one\\ \t\n \t\n\n  two", "onetwo"),
      #("one \\\n  two", "one two"),
      #("one\\\n  ", "one"),
      #("\\\n  text", "text"),
      #("one\n  two", "one\n  two"),
      #("one\\\\\n  two", "one\\\n  two"),
      #("one\\\n  \\n two", "one\n two"),
      #("one\\\n  \u{00A0}two", "one\u{00A0}two"),
    ],
    fn(pair) {
      let #(source, expected) = pair
      assert_string("\"\"\"" <> source <> "\"\"\"", expected)
    },
  )
}

pub fn nested_strings_decode_test() -> Nil {
  let input =
    "values = [\"\\u0041\", '''\n\\u0041''', { text = \"\"\"\nCaf\\u00E9\\\n  !\"\"\" }]\n"
  let expected = ["A", "\\u0041", "Caf\u{00E9}!"]
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(values) = tomlet.get(doc, ["values"])
  list.each(
    [#(["0"], "A"), #(["1"], "\\u0041"), #(["2", "text"], "Caf\u{00E9}!")],
    fn(pair) {
      let #(path, value) = pair
      assert tomlet.value_get(values, path) |> result.try(tomlet.as_string)
        == Ok(value)
      assert tomlet.get(doc, ["values", ..path]) |> result.try(tomlet.as_string)
        == Ok(value)
    },
  )
  let decoder =
    decode.at(
      ["values"],
      decode.list(
        decode.one_of(decode.string, [
          decode.at(["text"], decode.string),
        ]),
      ),
    )
  assert tomlet.decode(input, decoder) == Ok(expected)
}

pub fn string_source_survives_unrelated_edits_test() -> Nil {
  let source =
    "# strings\nbasic = \"Caf\\u00E9 \\\"x\\\"\" # keep\nmulti = \"\"\"\nfirst\\ \t\n  second\"\"\"\nliteral = '''\n\\u0041'''\nother = 1\n"
  list.each(["\n", "\r\n"], fn(line_ending) {
    let input = string.replace(source, each: "\n", with: line_ending)
    let assert Ok(doc) = tomlet.parse(input)
    assert tomlet.to_string(doc) == input
    let assert Ok(edited) = tomlet.set_int(doc, ["other"], 2)
    let output = tomlet.to_string(edited)
    assert output == string.replace(input, each: "other = 1", with: "other = 2")
    let assert Ok(reparsed) = tomlet.parse(output)
    assert tomlet.get_string(reparsed, ["basic"]) == Ok("Caf\u{00E9} \"x\"")
    assert tomlet.get_string(reparsed, ["multi"]) == Ok("firstsecond")
    assert tomlet.get_string(reparsed, ["literal"]) == Ok("\\u0041")
  })
}

pub fn decoded_quoted_keys_still_resolve_test() -> Nil {
  let assert Ok(doc) =
    tomlet.parse("\"\\u0041\" = \"\\u0042\"\nt = { \"\\x43\" = \"\\e\" }\n")
  assert tomlet.get_string(doc, ["A"]) == Ok("B")
  assert tomlet.get_string(doc, ["t", "C"]) == Ok("\u{001B}")
  assert tomlet.parse("\"A\" = 1\n\"\\u0041\" = 2\n")
    == Error(tomlet.DuplicateKey(["A"], 8))
}

fn assert_string(literal: String, expected: String) -> Nil {
  list.each([tomlet.Toml10, tomlet.Toml11], fn(version) {
    assert_string_with(literal, expected, version)
  })
}

fn assert_string_with(
  literal: String,
  expected: String,
  version: tomlet.TomlVersion,
) -> Nil {
  let input = "value = " <> literal <> "\n"
  let assert Ok(doc) = tomlet.parse_with(input, version)
  assert tomlet.get_string(doc, ["value"]) == Ok(expected)
  assert tomlet.get(doc, ["value"]) == Ok(tomlet.StringValue(expected))
  assert tomlet.get(doc, ["value"]) |> result.try(tomlet.as_string)
    == Ok(expected)
  assert tomlet.parse_value(literal) == Ok(tomlet.StringValue(expected))
  let decoder = decode.at(["value"], decode.string)
  assert decode.run(tomlet.to_dynamic(doc), decoder) == Ok(expected)
  let assert Ok(data) = tomlet.parse_dynamic(input)
  assert decode.run(data, decoder) == Ok(expected)
  let assert Ok(data) = tomlet.parse_dynamic_with(input, version)
  assert decode.run(data, decoder) == Ok(expected)
  assert tomlet.decode(input, decoder) == Ok(expected)
  assert tomlet.decode_with(input, version, decoder) == Ok(expected)
  let assert Ok(bytes_doc) = tomlet.parse_bytes(<<input:utf8>>)
  assert tomlet.get_string(bytes_doc, ["value"]) == Ok(expected)
  let assert Ok(bytes_doc) = tomlet.parse_bytes_with(<<input:utf8>>, version)
  assert tomlet.get_string(bytes_doc, ["value"]) == Ok(expected)
  assert tomlet.to_string(doc) == input
}
