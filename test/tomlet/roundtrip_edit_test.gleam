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
