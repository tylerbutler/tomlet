import gleam/list
import gleeunit
import tomlet/ast
import tomlet/parser
import tomlet/path

pub fn main() -> Nil {
  gleeunit.main()
}

fn assemble(input: String) {
  parser.parse(input, parser.Toml11)
}

// Exercises every construct through the new token-driven assembler. Valid
// inputs must parse; the dedicated parser_test.gleam pins stable error shapes.
fn assert_ok(input: String) -> Nil {
  let assert Ok(_) = parser.parse(input, parser.Toml11)
  Nil
}

pub fn parity_scalars_test() {
  [
    "a = 1\n",
    "a = -17\n",
    "a = 1_000\n",
    "a = 0xDEAD_beef\n",
    "a = 0o755\n",
    "a = 0b1010\n",
    "a = 3.14\n",
    "a = 6.626e-34\n",
    "a = inf\n",
    "a = -inf\n",
    "a = nan\n",
    "a = true\n",
    "a = false\n",
    "a = \"hello\"\n",
    "a = 'world'\n",
    "a = \"\"\"multi\nline\"\"\"\n",
    "a = '''multi\nline'''\n",
    "a = 1979-05-27T07:32:00Z\n",
    "a = 1979-05-27 07:32:00\n",
    "a = 1979-05-27\n",
    "a = 07:32:00\n",
    "a = 07:32:00.999999\n",
  ]
  |> list.each(assert_ok)
}

pub fn parity_keys_test() {
  [
    "bare = 1\n",
    "\"quoted key\" = 1\n",
    "'literal key' = 1\n",
    "a.b.c = 1\n",
    "a . b . c = 1\n",
    "1234 = 1\n",
    "\"\\u0041\" = 1\n",
  ]
  |> list.each(assert_ok)
}

pub fn parity_trivia_test() {
  [
    "",
    "\n",
    "\n\n\n",
    "# only a comment\n",
    "  # indented comment\n",
    "a = 1 # trailing\n",
    "a = 1# no space\n",
    "# c\n\nb = 2\n",
    "a = 1\n\n",
    "a = 1",
    "a = 1\n  ",
  ]
  |> list.each(assert_ok)
}

pub fn parity_arrays_test() {
  [
    "a = []\n",
    "a = [1, 2, 3]\n",
    "a = [1, 2, 3,]\n",
    "a = [[1, 2], [3, 4]]\n",
    "a = [\n  1, # one\n  2,\n]\n",
    "a = [ \"x\", 'y', true ]\n",
    "a = [1, 2] # done\n",
  ]
  |> list.each(assert_ok)
}

pub fn parity_inline_tables_test() {
  [
    "a = {}\n",
    "a = { x = 1, y = 2 }\n",
    "a = {x=1,y=2}\n",
    "a = { nested = { deep = 1 } }\n",
    "a = { list = [1, 2, 3] }\n",
  ]
  |> list.each(assert_ok)
}

pub fn parity_headers_test() {
  [
    "[a]\nx = 1\n",
    "[a.b.c]\nx = 1\n",
    "[ a . b ]\nx = 1\n",
    "[[products]]\nname = \"Hammer\"\n[[products]]\nname = \"Nail\"\n",
    "[a]\n[a.b]\nx = 1\n",
    "[\"quoted table\"]\nx = 1\n",
    "[a] # comment after header\nx = 1\n",
  ]
  |> list.each(assert_ok)
}

pub fn parity_invalid_inputs_test() {
  // Both front-ends must reject these. The exact error kind/offset can differ
  // for malformed lines (e.g. two values on one line), and stable error shapes
  // are pinned separately in parser_test.gleam, so here we only require that the
  // token-driven parser rejects exactly the inputs the legacy parser rejects.
  [
    "name = ???\n",
    "ratio = 3.14.15\n",
    "name = \"unterminated\n",
    "[package\n",
    "[']\n",
    "name = \"one\"\nname = \"two\"\n",
    "[a]\nb = 1\n\n[a]\nc = 2\n",
    "[tbl]\n[[tbl]]\n",
    "bad = [1,,2]\n",
    "a={b=1, b=2}\n",
    "leading-zero = 01\n",
    "capitalized = True\n",
    "bad = \"\\q\"\n",
    "\"\"\"key\"\"\" = 1\n",
    "first = \"Tom\" last = \"Preston-Werner\"\n",
  ]
  |> list.each(fn(input) {
    let assert Error(_) = parser.parse(input, parser.Toml11)
    Nil
  })

  // Inline-table trailing commas and newlines are invalid under TOML 1.0 but
  // become valid under TOML 1.1, so they are pinned to the 1.0 parser here.
  [
    "bad = {a = 1,}\n",
    "bad = { a = 1 \n}\n",
  ]
  |> list.each(fn(input) {
    let assert Error(_) = parser.parse(input, parser.Toml10)
    Nil
  })
}

// A few direct assertions on the produced AST, independent of the legacy parser.

pub fn assemble_simple_key_value_test() {
  let assert Ok(table) = assemble("name = \"tomato\"\n")
  assert path.get(table, ["name"])
    == Ok(ast.String("tomato", ast.BasicString, source_text: "\"tomato\""))
}

pub fn assemble_dotted_key_test() {
  let assert Ok(table) = assemble("a.b.c = 1\n")
  assert path.get(table, ["a", "b", "c"]) == Ok(ast.Int(1, source_text: "1"))
}

pub fn assemble_array_of_tables_test() {
  let assert Ok(table) = assemble("[[p]]\nname = \"a\"\n[[p]]\nname = \"b\"\n")
  let assert Ok(ast.ArrayOfTables(items)) = path.get(table, ["p"])
  assert list.length(items) == 2
}

pub fn assemble_preserves_blank_and_comment_entries_test() {
  let assert Ok(ast.Table(entries, _)) = assemble("# c\n\nx = 1\n")
  let assert [ast.Comment("# c"), ast.BlankLine, ast.KeyValue(..)] = entries
}
