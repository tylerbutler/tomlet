import gleam/list
import gleam/string
import tomlet

fn check_edit(
  input: String,
  key: List(String),
  items: List(tomlet.Value),
  expected: String,
) -> tomlet.Document {
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(edited) = tomlet.set_array(doc, key, items)
  let output = tomlet.to_string(edited)
  assert output == expected
  let assert Ok(reparsed) = tomlet.parse(output)
  assert tomlet.get(reparsed, key) == Ok(tomlet.ArrayValue(items))
  assert tomlet.get(edited, key) == tomlet.get(reparsed, key)
  edited
}

pub fn no_op_preserves_exact_source_test() {
  let input =
    "[tools.licence_audit]\nallow=[\n  \"MIT\", # needed by foo\n  \"Apache-2.0\",\n]"
  let _edited =
    check_edit(
      input,
      ["tools", "licence_audit", "allow"],
      [tomlet.StringValue("MIT"), tomlet.StringValue("Apache-2.0")],
      input,
    )
}

pub fn append_preserves_comments_before_and_after_items_test() {
  let input =
    "allow = [\n  # first licence\n  'MIT', # needed by foo, not bar\n  \"Apache-2.0\",\n  # policy notes\n]\n"
  let _edited =
    check_edit(
      input,
      ["allow"],
      [
        tomlet.StringValue("MIT"),
        tomlet.StringValue("Apache-2.0"),
        tomlet.StringValue("BSD-3-Clause"),
      ],
      "allow = [\n  # first licence\n  'MIT', # needed by foo, not bar\n  \"Apache-2.0\",\n  \"BSD-3-Clause\",\n  # policy notes\n]\n",
    )
}

pub fn removing_items_removes_their_comments_test() {
  let input =
    "x = [\n  # remove before\n  1, # remove after\n  # keep before\n  2, # keep after\n  # closing\n]\n"
  let _edited =
    check_edit(
      input,
      ["x"],
      [tomlet.IntValue(2)],
      "x = [\n  # keep before\n  2, # keep after\n  # closing\n]\n",
    )
}

pub fn replacing_all_items_keeps_only_closing_comments_test() {
  let input = "x = [\n  # remove\n  1, # remove too\n  # closing\n]\n"
  let _edited =
    check_edit(
      input,
      ["x"],
      [tomlet.IntValue(9)],
      "x = [\n  9,\n  # closing\n]\n",
    )
}

pub fn empty_array_keeps_closing_comments_test() {
  let _edited =
    check_edit(
      "x = [\n  1, # remove\n  # closing\n]\n",
      ["x"],
      [],
      "x = [\n  # closing\n]\n",
    )
  let _edited =
    check_edit(
      "x = [\n  # closing\n]\n",
      ["x"],
      [tomlet.IntValue(1)],
      "x = [\n  1,\n  # closing\n]\n",
    )
}

pub fn reordering_and_duplicates_keep_occurrence_comments_test() {
  let input = "x = [\n  0x1, # first one\n  2, # two\n  1, # second one\n]\n"
  let _edited =
    check_edit(
      input,
      ["x"],
      [tomlet.IntValue(1), tomlet.IntValue(1), tomlet.IntValue(2)],
      "x = [\n  0x1, # first one\n  1, # second one\n  2, # two\n]\n",
    )
}

pub fn append_after_item_without_comma_test() {
  let _edited =
    check_edit(
      "x = [\n  1 # one\n]\n",
      ["x"],
      [tomlet.IntValue(1), tomlet.IntValue(2)],
      "x = [\n  1, # one\n  2,\n]\n",
    )
}

pub fn repeated_edits_keep_trivia_test() {
  let doc =
    check_edit(
      "x = [\n  1, # one\n]\n",
      ["x"],
      [tomlet.IntValue(1), tomlet.IntValue(2)],
      "x = [\n  1, # one\n  2,\n]\n",
    )
  let assert Ok(edited) =
    tomlet.set_array(doc, ["x"], [tomlet.IntValue(2), tomlet.IntValue(1)])
  assert tomlet.to_string(edited) == "x = [\n  2,\n  1, # one\n]\n"
  let assert Ok(reparsed) = tomlet.parse(tomlet.to_string(edited))
  assert tomlet.get(reparsed, ["x"]) == tomlet.get(edited, ["x"])
}

pub fn nested_values_keep_source_and_comments_test() {
  let input =
    "x = [\n  [1, # inner\n   2], # array\n  {s = '#,]'}, # table\n  '''a,#\nb''', # string\n]\n"
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(tomlet.ArrayValue(items)) = tomlet.get(doc, ["x"])
  let assert Ok(edited) =
    tomlet.set_array(doc, ["x"], list.append(items, [tomlet.BoolValue(True)]))
  let output = tomlet.to_string(edited)
  assert string.contains(output, "[1, # inner\n   2], # array")
  assert string.contains(output, "{s = '#,]'}, # table")
  assert string.contains(output, "'''a,#\nb''', # string")
  let assert Ok(reparsed) = tomlet.parse(output)
  assert tomlet.get(reparsed, ["x"]) == tomlet.get(edited, ["x"])
}

pub fn inline_table_path_preserves_array_comments_test() {
  let _edited =
    check_edit(
      "pkg = { allow = [\n  'MIT', # keep\n] }\n",
      ["pkg", "allow"],
      [tomlet.StringValue("MIT"), tomlet.StringValue("BSD")],
      "pkg = { allow = [\n  'MIT', # keep\n  \"BSD\",\n] }\n",
    )
}

pub fn crlf_edits_and_no_ops_test() {
  let input = "x = [\r\n  1, # one\r\n]\r\n"
  let _edited = check_edit(input, ["x"], [tomlet.IntValue(1)], input)
  let _edited =
    check_edit(
      input,
      ["x"],
      [tomlet.IntValue(1), tomlet.IntValue(2)],
      "x = [\r\n  1, # one\r\n  2,\r\n]\r\n",
    )
}

pub fn flow_array_retains_lexical_forms_test() {
  let _edited =
    check_edit(
      "x = [0x1, 'two']\n",
      ["x"],
      [tomlet.IntValue(1), tomlet.StringValue("two"), tomlet.BoolValue(True)],
      "x = [0x1, 'two', true]\n",
    )
}

pub fn insertions_keep_leading_comments_with_their_items_test() {
  let _edited =
    check_edit(
      "x = [\n\t# one\n\t1,\n\t# two\n\t2,\n]\n",
      ["x"],
      [
        tomlet.IntValue(0),
        tomlet.IntValue(1),
        tomlet.IntValue(3),
        tomlet.IntValue(2),
      ],
      "x = [\n\t0,\n\t# one\n\t1,\n\t3,\n\t# two\n\t2,\n]\n",
    )
}

pub fn zero_indentation_and_inline_final_comment_test() {
  let _edited =
    check_edit(
      "x = [1,\n2, # two\n]\n",
      ["x"],
      [tomlet.IntValue(2), tomlet.IntValue(3)],
      "x = [\n2, # two\n3,\n]\n",
    )
}

pub fn no_op_preserves_all_value_kinds_test() {
  let input =
    "x=[ 0xA, +1.00, -nan, true, 'raw', 1979-05-27, 07:32:00, 1979-05-27T07:32:00Z, [1, 2], { a = 1 } ]"
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(tomlet.ArrayValue(items)) = tomlet.get(doc, ["x"])
  let assert Ok(edited) = tomlet.set_array(doc, ["x"], items)
  assert tomlet.to_string(edited) == input
}

pub fn no_op_after_another_edit_keeps_array_source_test() {
  let assert Ok(doc) = tomlet.parse("x = [\n  0x1, # one\n]\ny = 1\n")
  let assert Ok(doc) = tomlet.set_int(doc, ["y"], 2)
  let assert Ok(edited) = tomlet.set_array(doc, ["x"], [tomlet.IntValue(1)])
  assert tomlet.to_string(edited) == "x = [\n  0x1, # one\n]\ny = 2\n"
}

pub fn added_duplicates_do_not_duplicate_comments_test() {
  let _edited =
    check_edit(
      "x = [\n  1, # one\n]\n",
      ["x"],
      [tomlet.IntValue(1), tomlet.IntValue(1)],
      "x = [\n  1, # one\n  1,\n]\n",
    )
}

pub fn empty_path_and_invalid_items_remain_checked_test() {
  let assert Ok(doc) = tomlet.parse("x = []\n")
  assert tomlet.set_array(doc, [], []) == Error(tomlet.EmptyKeyPath)
  assert tomlet.set_array(doc, ["x"], [tomlet.StandardTableValue([])])
    == Error(tomlet.InvalidValue)
  assert tomlet.set_array(doc, ["bad\nkey"], [])
    == Error(tomlet.InvalidKeySegment("bad\nkey"))
}

pub fn inline_table_comments_before_nested_array_do_not_break_parsing_test() {
  let _edited =
    check_edit(
      "pkg = { allow = # before array\n [\n  1, # one\n] }\n",
      ["pkg", "allow"],
      [tomlet.IntValue(1), tomlet.IntValue(2)],
      "pkg = { allow = [\n  1, # one\n  2,\n] }\n",
    )
}
