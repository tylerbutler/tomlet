import gleam/list
import gleeunit
import tomlet
import tomlet/ast
import tomlet/parser
import tomlet/path

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn get_from_dotted_key_test() {
  let assert Ok(doc) = tomlet.parse("package.name = \"tomato\"\n")

  assert tomlet.get_string(doc, ["package", "name"]) == Ok("tomato")
}

pub fn get_from_standard_table_test() {
  let assert Ok(doc) =
    tomlet.parse("[package]\nname = \"tomato\"\nversion = \"0.1.0\"\n")

  assert tomlet.get_string(doc, ["package", "name"]) == Ok("tomato")
  assert tomlet.get_string(doc, ["package", "version"]) == Ok("0.1.0")
}

pub fn get_from_inline_table_test() {
  let assert Ok(doc) =
    tomlet.parse("package = { name = \"tomato\", version = \"0.1.0\" }\n")

  assert tomlet.get_string(doc, ["package", "name"]) == Ok("tomato")
  assert tomlet.get_string(doc, ["package", "version"]) == Ok("0.1.0")
}

pub fn get_from_nested_inline_table_test() {
  let assert Ok(doc) =
    tomlet.parse("package = { metadata = { name = \"tomato\" } }\n")

  assert tomlet.get_string(doc, ["package", "metadata", "name"]) == Ok("tomato")
}

pub fn get_from_deeply_nested_inline_table_test() {
  let assert Ok(doc) =
    tomlet.parse(
      "package = { metadata = { release = { owner = { name = \"tomato\" } } } }\n",
    )

  assert tomlet.get_string(doc, [
      "package",
      "metadata",
      "release",
      "owner",
      "name",
    ])
    == Ok("tomato")
}

pub fn get_from_inline_table_inside_standard_table_test() {
  let assert Ok(doc) =
    tomlet.parse("[package]\nmetadata = { release = { name = \"tomato\" } }\n")

  assert tomlet.get_string(doc, ["package", "metadata", "release", "name"])
    == Ok("tomato")
}

pub fn get_from_dotted_key_inside_inline_table_test() {
  let assert Ok(doc) =
    tomlet.parse("package = { metadata.name = \"tomato\" }\n")

  assert tomlet.get_string(doc, ["package", "metadata", "name"]) == Ok("tomato")
}

pub fn get_nested_inline_table_wrong_type_test() {
  let assert Ok(doc) =
    tomlet.parse("package = { metadata = { downloads = 42 } }\n")

  assert tomlet.get_string(doc, ["package", "metadata", "downloads"])
    == Error(tomlet.WrongType(["package", "metadata", "downloads"], "String"))
}

pub fn inline_table_missing_nested_key_is_key_not_found_test() {
  let assert Ok(doc) = tomlet.parse("package = { name = \"tomato\" }\n")

  assert tomlet.get_string(doc, ["package", "version"])
    == Error(tomlet.KeyNotFound(["package", "version"]))
}

pub fn root_and_table_values_can_coexist_test() {
  let assert Ok(doc) =
    tomlet.parse("name = \"root\"\n[package]\nname = \"tomato\"\n")

  assert tomlet.get_string(doc, ["name"]) == Ok("root")
  assert tomlet.get_string(doc, ["package", "name"]) == Ok("tomato")
}

pub fn get_array_of_tables_test() {
  let assert Ok(table) =
    parser.parse(
      "[[products]]\nname = \"Hammer\"\n[[products]]\nname = \"Nail\"\n",
    )

  let assert Ok(ast.ArrayOfTables(items)) = path.get(table, ["products"])
  assert list.length(items) == 2
}
