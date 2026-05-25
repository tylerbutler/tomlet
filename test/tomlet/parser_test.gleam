import gleam/list
import gleeunit
import tomlet
import tomlet/ast
import tomlet/parser

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_booleans_test() {
  let assert Ok(doc) = tomlet.parse("enabled = true\ndisabled = false\n")

  assert tomlet.get_bool(doc, ["enabled"]) == Ok(True)
  assert tomlet.get_bool(doc, ["disabled"]) == Ok(False)
}

pub fn parse_float_test() {
  let assert Ok(doc) = tomlet.parse("ratio = 3.14\n")

  assert tomlet.get_float(doc, ["ratio"]) == Ok(3.14)
}

pub fn parse_exponent_float_repr_test() {
  let assert Ok(doc) = tomlet.parse("ratio = 3e2\n")

  assert tomlet.get(doc, ["ratio"]) == Ok(ast.Float(300.0, source_text: "3e2"))
}

pub fn parse_special_float_repr_test() {
  let assert Ok(doc) =
    tomlet.parse("positive = inf\nnegative = -inf\nnan = nan\n")

  assert tomlet.get(doc, ["positive"])
    == Ok(ast.SpecialFloat(ast.PositiveInfinity, source_text: "inf"))
  assert tomlet.get(doc, ["negative"])
    == Ok(ast.SpecialFloat(ast.NegativeInfinity, source_text: "-inf"))
  assert tomlet.get(doc, ["nan"])
    == Ok(ast.SpecialFloat(ast.NotANumber, source_text: "nan"))
  assert tomlet.to_string(doc) == "positive = inf\nnegative = -inf\nnan = nan\n"
}

pub fn parse_based_integer_values_test() {
  let assert Ok(doc) = tomlet.parse("hex = 0xFF\noct = 0o755\nbin = 0b1010\n")

  assert tomlet.get(doc, ["hex"]) == Ok(ast.Int(255, source_text: "0xFF"))
  assert tomlet.get(doc, ["oct"]) == Ok(ast.Int(493, source_text: "0o755"))
  assert tomlet.get(doc, ["bin"]) == Ok(ast.Int(10, source_text: "0b1010"))
}

pub fn signed_based_integer_values_are_rejected_test() {
  let inputs = [
    "hex = +0xFF\n",
    "hex = -0xFF\n",
    "oct = +0o755\n",
    "oct = -0o755\n",
    "bin = +0b1010\n",
    "bin = -0b1010\n",
  ]

  list.each(inputs, fn(input) {
    let assert Error(_) = tomlet.parse(input)
  })
}

pub fn parse_literal_string_test() {
  let assert Ok(doc) = tomlet.parse("name = 'tomato\\nraw'\n")

  assert tomlet.get(doc, ["name"])
    == Ok(ast.String(
      "tomato\\nraw",
      ast.LiteralString,
      source_text: "'tomato\\nraw'",
    ))
}

pub fn parse_date_time_reprs_test() {
  let assert Ok(doc) =
    tomlet.parse("dob = 1979-05-27T07:32:00Z\nlocal = 1979-05-27\n")

  assert tomlet.get(doc, ["dob"])
    == Ok(ast.DateTime(source_text: "1979-05-27T07:32:00Z"))
  assert tomlet.get(doc, ["local"]) == Ok(ast.Date(source_text: "1979-05-27"))
}

pub fn parse_array_of_ints_test() {
  let assert Ok(doc) = tomlet.parse("ports = [8000, 8001, 8002]\n")

  assert tomlet.get(doc, ["ports"])
    == Ok(ast.Array(
      [
        ast.ArrayItem(
          ast.Trivia(""),
          ast.Int(8000, source_text: "8000"),
          ast.Trivia(""),
        ),
        ast.ArrayItem(
          ast.Trivia(""),
          ast.Int(8001, source_text: "8001"),
          ast.Trivia(""),
        ),
        ast.ArrayItem(
          ast.Trivia(""),
          ast.Int(8002, source_text: "8002"),
          ast.Trivia(""),
        ),
      ],
      source_text: "[8000, 8001, 8002]",
    ))
}

pub fn parse_nested_arrays_test() {
  let assert Ok(doc) = tomlet.parse("matrix = [[1, 2], [3, 4]]\n")

  let assert Ok(ast.Array([_, _], source_text: "[[1, 2], [3, 4]]")) =
    tomlet.get(doc, ["matrix"])
}

pub fn parse_inline_table_test() {
  let assert Ok(doc) =
    tomlet.parse("package = { name = \"tomato\", version = \"0.1.0\" }\n")

  let assert Ok(ast.InlineTable(
    entries,
    source_text: "{ name = \"tomato\", version = \"0.1.0\" }",
  )) = tomlet.get(doc, ["package"])
  assert entries != []
}

pub fn parse_quoted_key_test() {
  let assert Ok(doc) = tomlet.parse("\"package name\" = \"tomato\"\n")

  assert tomlet.get_string(doc, ["package name"]) == Ok("tomato")
}

pub fn comments_and_blank_lines_do_not_block_parsing_test() {
  let assert Ok(doc) = tomlet.parse("# top\n\nname = \"tomato\" # inline\n")

  assert tomlet.get_string(doc, ["name"]) == Ok("tomato")
}

pub fn utf8_bom_is_accepted_test() {
  let assert Ok(doc) = tomlet.parse("\u{FEFF}name = \"tomato\"\n")

  assert tomlet.get_string(doc, ["name"]) == Ok("tomato")
}

pub fn leading_bom_in_string_input_is_accepted_test() {
  let assert Ok(doc) = tomlet.parse("\u{FEFF}name = \"tomlet\"\n")

  assert tomlet.get_string(doc, ["name"]) == Ok("tomlet")
}

pub fn misplaced_bom_in_string_input_is_rejected_test() {
  assert tomlet.parse("name = \"to\u{FEFF}mlet\"\n")
    == Error(tomlet.InvalidEncoding)
}

pub fn crlf_input_is_accepted_test() {
  let assert Ok(doc) = tomlet.parse("name = \"tomato\"\r\n")

  assert tomlet.get_string(doc, ["name"]) == Ok("tomato")
}

pub fn parse_multiline_basic_string_test() {
  let assert Ok(doc) = tomlet.parse("text = \"\"\"hello\nworld\"\"\"\n")

  assert tomlet.get(doc, ["text"])
    == Ok(ast.String(
      "hello\nworld",
      ast.MultiBasicString,
      source_text: "\"\"\"hello\nworld\"\"\"",
    ))
}

pub fn parse_multiline_literal_string_test() {
  let assert Ok(doc) = tomlet.parse("text = '''hello\nworld'''\n")

  assert tomlet.get(doc, ["text"])
    == Ok(ast.String(
      "hello\nworld",
      ast.MultiLiteralString,
      source_text: "'''hello\nworld'''",
    ))
}

pub fn duplicate_key_returns_error_test() {
  assert tomlet.parse("name = \"one\"\nname = \"two\"\n")
    == Error(tomlet.KeyAlreadyInUse(["name"], 13))
}

pub fn unterminated_basic_string_returns_positioned_error_test() {
  assert tomlet.parse("name = \"tomato\n")
    == Error(tomlet.Unexpected("\"tomato", "value", 7))
}

pub fn invalid_bare_value_returns_positioned_error_test() {
  assert tomlet.parse("name = ???\n")
    == Error(tomlet.Unexpected("???", "value", 7))
}

pub fn parser_module_uses_consistent_parse_error_names_test() {
  assert parser.parse("name = ???\n")
    == Error(parser.Unexpected("???", "value", 7))
}

pub fn invalid_inline_array_item_returns_nested_error_test() {
  assert tomlet.parse("bad = [0xZZ]\n")
    == Error(tomlet.Unexpected("0xZZ", "value", 7))
}

pub fn invalid_inline_table_value_returns_nested_error_test() {
  assert tomlet.parse("bad = {inner=0xZZ}\n")
    == Error(tomlet.Unexpected("0xZZ", "value", 13))
}

pub fn malformed_table_header_returns_positioned_error_test() {
  assert tomlet.parse("[package\n")
    == Error(tomlet.Unexpected("[package", "[table]", 0))
}

pub fn unclosed_quoted_table_header_key_returns_error_test() {
  assert tomlet.parse("[']\n") == Error(tomlet.Unexpected("'", "key", 1))
}

pub fn redefining_standard_table_returns_error_test() {
  assert tomlet.parse("[a]\nb = 1\n\n[a]\nc = 2\n")
    == Error(tomlet.KeyAlreadyInUse(["a"], 11))
}

pub fn redefining_dotted_key_table_returns_error_test() {
  assert tomlet.parse("[fruit]\napple.color = \"red\"\n\n[fruit.apple]\n")
    == Error(tomlet.KeyAlreadyInUse(["fruit", "apple"], 29))
}

pub fn dotted_key_cannot_append_to_explicit_table_from_parent_test() {
  assert tomlet.parse("[a.b.c]\nz = 9\n\n[a]\nb.c.t = \"nope\"\n")
    == Error(tomlet.KeyAlreadyInUse(["a", "b", "c", "t"], 19))
}

pub fn standard_table_cannot_be_redefined_as_array_table_test() {
  assert tomlet.parse("[tbl]\n[[tbl]]\n")
    == Error(tomlet.KeyAlreadyInUse(["tbl"], 6))
}

pub fn dotted_key_cannot_append_to_array_table_from_parent_test() {
  assert tomlet.parse("[[a.b]]\n\n[a]\nb.y = 2\n")
    == Error(tomlet.KeyAlreadyInUse(["a", "b", "y"], 13))
}

pub fn array_table_parent_cannot_later_be_array_table_test() {
  assert tomlet.parse("[[albums.songs]]\nname = \"Glory Days\"\n\n[[albums]]\n")
    == Error(tomlet.KeyAlreadyInUse(["albums"], 38))
}

pub fn invalid_float_returns_positioned_error_test() {
  assert tomlet.parse("ratio = 3.14.15\n")
    == Error(tomlet.Unexpected("3.14.15", "value", 8))
}

pub fn invalid_corpus_gap_rejections_test() {
  let invalid_inputs = [
    "double-comma-01 = [1,,2]\n",
    "arrr = [true false]\n",
    "only-comma-01 = [,]\n",
    "capitalized-true = True\n",
    "leading-zero-01 = 01\n",
    "\"only 28 or 29 days in february\" = 1988-02-30T15:15:15Z\n",
    "bad-escape = \"\\q\"\n",
    "bare-key-space = a b = 1\n",
    "first = \"Tom\" last = \"Preston-Werner\"\n",
    "a = 1\n\"\\u0061\" = 2\n",
    "\"a'b\" = 1\n\"a\\u0027b\" = 2\n",
    "bad = \"\\uD801\"\n",
    "bad = \"\\UFFFFFFFF\"\n",
  ]

  list.each(invalid_inputs, fn(input) {
    let assert Error(_) = tomlet.parse(input)
  })
}

pub fn invalid_inline_table_corpus_rejections_test() {
  let invalid_inputs = [
    "simple = { a = 1 \n}\n",
    "a={b=1, b=2}\n",
    "a={a.b=1, a=2}\n",
    "a.b=0\na={}\n",
    "a={}\n[a.b]\n",
    "inline-t = { nest = {} }\n[[inline-t.nest]]\n",
  ]

  list.each(invalid_inputs, fn(input) {
    let assert Error(_) = tomlet.parse(input)
  })
}

pub fn invalid_control_character_corpus_rejections_test() {
  let invalid_inputs = [
    "comment-null = \"null\"   # \u{0000}\n",
    "comment-del = \"del\"   # \u{007F}\n",
    "\u{000C}",
    "bare-cr = \"foo\"\r",
    "# First on next line is U+3000 IDEOGRAPHIC SPACE\n\u{3000}foo = \"bar\"\n",
  ]

  list.each(invalid_inputs, fn(input) {
    let assert Error(_) = tomlet.parse(input)
  })
}

pub fn invalid_multiline_string_corpus_rejections_test() {
  let invalid_inputs = [
    "bad = \"\"\"val\\ue\"\"\"\n",
    "bad = \"\"\"val\\Ux\"\"\"\n",
    "bad = \"\"\"\\UFFFFFFFF\"\"\"\n",
    "bad = \"\"\"\\uD801\"\"\"\n",
    "bad = \"\"\"\\@\"\"\"\n",
    "bad = \"\"\"t\\a\"\"\"\n",
    "bad = \"\"\"t\\ t\"\"\"\n",
    "backslash = \"\"\"\\\"\"\"\n",
    "bad = '''6 apostrophes: ''''''\n\n",
    "bad = '''15 apostrophes: ''''''''''''''''''\n",
    "bad = '''\n",
    "bad = '''\nhee\ngee ''\n",
    "bad = \"\"\"\n",
  ]

  list.each(invalid_inputs, fn(input) {
    let assert Error(_) = tomlet.parse(input)
  })
}

pub fn multiline_strings_are_not_keys_test() {
  let invalid_inputs = [
    "\"\"\"key\"\"\" = 1\n",
    "'''key''' = 1\n",
    "[\"\"\"tbl\"\"\"]\nk = 1\n",
    "['''tbl''']\nk = 1\n",
  ]

  list.each(invalid_inputs, fn(input) {
    let assert Error(_) = tomlet.parse(input)
  })
}
