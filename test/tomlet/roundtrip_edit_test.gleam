import gleam/string
import tomlet

// Editing a document drops the original-source cache, so `to_string` re-emits
// from the AST. These tests pin the invariant that the re-emitted text is still
// valid TOML that round-trips: parse -> edit -> emit -> parse must succeed and
// preserve the surrounding structure.

pub fn edit_sibling_of_dotted_key_table_reparses_test() {
  let assert Ok(doc) = tomlet.parse("a.b.c = 1\n")
  let assert Ok(edited) = tomlet.set_int(doc, ["a", "b", "d"], 9)

  let output = tomlet.to_string(edited)

  // The emitted text must parse back; a synthesized `[a.b]` header after a
  // dotted-key definition is rejected by the parser.
  let assert Ok(reparsed) = tomlet.parse(output)
  assert tomlet.get_int(reparsed, ["a", "b", "c"]) == Ok(1)
  assert tomlet.get_int(reparsed, ["a", "b", "d"]) == Ok(9)
}

pub fn edit_sibling_of_dotted_key_under_header_reparses_test() {
  let assert Ok(doc) = tomlet.parse("[t]\na.b = 1\n")
  let assert Ok(edited) = tomlet.set_int(doc, ["t", "a", "c"], 9)

  let output = tomlet.to_string(edited)

  let assert Ok(reparsed) = tomlet.parse(output)
  assert tomlet.get_int(reparsed, ["t", "a", "b"]) == Ok(1)
  assert tomlet.get_int(reparsed, ["t", "a", "c"]) == Ok(9)
}

pub fn edit_implicit_parent_of_array_of_tables_reparses_test() {
  assert_parent_array_edits(
    "# exceptions\n[[tools.licence_audit.exceptions]]\npurl = \"pkg:hex/example@1.0.0\" # first\nlicence = \"MIT\"\n\n# second exception\n[[tools.licence_audit.exceptions]]\npurl = \"pkg:hex/other@2.0.0\"\nlicence = \"Apache-2.0\"\n",
  )
}

pub fn edit_implicit_parent_of_standard_table_reparses_test() {
  assert_parent_array_edits(
    "# exception\n[tools.licence_audit.exceptions]\npurl = \"pkg:hex/example@1.0.0\" # keep\nlicence = \"MIT\"\n",
  )
}

pub fn edit_implicit_parent_of_empty_child_tables_reparses_test() {
  assert_parent_array_edits("[[tools.licence_audit.exceptions]]\n")
  assert_parent_array_edits("[tools.licence_audit.exceptions]\n")
}

pub fn edit_implicit_parent_preserves_crlf_test() {
  assert_parent_array_edits(
    "# exception\r\n[[tools.licence_audit.exceptions]]\r\npurl = \"pkg:hex/example@1.0.0\"\r\nlicence = \"MIT\" # keep\r\n",
  )
}

fn assert_parent_array_edits(input: String) -> Nil {
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(exceptions) =
    tomlet.get(doc, ["tools", "licence_audit", "exceptions"])
  let assert Ok(edited) =
    tomlet.set_array(doc, ["tools", "licence_audit", "allow"], [
      tomlet.StringValue("MIT"),
    ])
  let output = tomlet.to_string(edited)
  let assert Ok(reparsed) = tomlet.parse(output)
  assert tomlet.get(reparsed, ["tools", "licence_audit", "allow"])
    == Ok(tomlet.ArrayValue([tomlet.StringValue("MIT")]))
  assert tomlet.get(reparsed, ["tools", "licence_audit", "exceptions"])
    == Ok(exceptions)
  assert string.starts_with(output, input)
  assert string.contains(string.replace(output, "\r\n", ""), "\n")
    == !string.contains(input, "\r\n")

  let assert Ok(edited_again) =
    tomlet.set_array(reparsed, ["tools", "licence_audit", "deny"], [
      tomlet.StringValue("GPL-3.0-only"),
    ])
  let second_output = tomlet.to_string(edited_again)
  let assert Ok(reparsed_again) = tomlet.parse(second_output)
  assert tomlet.get(reparsed_again, ["tools", "licence_audit", "allow"])
    == Ok(tomlet.ArrayValue([tomlet.StringValue("MIT")]))
  assert tomlet.get(reparsed_again, ["tools", "licence_audit", "deny"])
    == Ok(tomlet.ArrayValue([tomlet.StringValue("GPL-3.0-only")]))
  assert tomlet.get(reparsed_again, ["tools", "licence_audit", "exceptions"])
    == Ok(exceptions)
  assert string.starts_with(second_output, input)
  assert string.contains(string.replace(second_output, "\r\n", ""), "\n")
    == !string.contains(input, "\r\n")
}

pub fn edit_explicit_parent_before_child_table_reparses_test() {
  let input =
    "[tools.licence_audit]\n# exceptions\n[[tools.licence_audit.exceptions]]\nlicence = \"MIT\"\n"
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(edited) =
    tomlet.set_array(doc, ["tools", "licence_audit", "allow"], [
      tomlet.StringValue("MIT"),
    ])
  let assert Ok(reparsed) = tomlet.parse(tomlet.to_string(edited))
  assert tomlet.get(reparsed, ["tools", "licence_audit", "allow"])
    == Ok(tomlet.ArrayValue([tomlet.StringValue("MIT")]))
  assert tomlet.get(reparsed, ["tools", "licence_audit", "exceptions"])
    == tomlet.get(doc, ["tools", "licence_audit", "exceptions"])
  assert string.contains(tomlet.to_string(edited), "# exceptions\n")
}

pub fn edit_preserves_multiline_array_interior_comments_test() {
  let input = "x = [\n  1, # one\n  2,\n]\ny = 9\n"
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(edited) = tomlet.set_int(doc, ["y"], 100)

  let output = tomlet.to_string(edited)

  // The re-emitted document must still be valid TOML.
  let assert Ok(reparsed) = tomlet.parse(output)
  assert tomlet.get_int(reparsed, ["y"]) == Ok(100)
  assert tomlet.get(reparsed, ["x"])
    == Ok(tomlet.ArrayValue([tomlet.IntValue(1), tomlet.IntValue(2)]))

  // The interior comment must survive the round-trip.
  assert string.contains(output, "# one")
}

pub fn edit_preserves_multiline_array_trailing_comment_test() {
  let input = "x = [\n  1,\n  2,\n] # done\ny = 9\n"
  let assert Ok(doc) = tomlet.parse(input)
  let assert Ok(edited) = tomlet.set_int(doc, ["y"], 100)

  let output = tomlet.to_string(edited)

  let assert Ok(reparsed) = tomlet.parse(output)
  assert tomlet.get_int(reparsed, ["y"]) == Ok(100)
  assert string.contains(output, "# done")
}
