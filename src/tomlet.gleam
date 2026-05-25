import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tomlet/ast
import tomlet/parser
import tomlet/path

pub opaque type Document {
  Document(
    root: ast.Table,
    trailing_trivia: String,
    line_ending: LineEnding,
    original_source: Option(String),
  )
}

pub type LineEnding {
  Lf
  Crlf
}

pub type ParseError {
  InvalidEncoding
  Unexpected(got: String, expected: String, offset: Int)
  KeyAlreadyInUse(key: List(String), offset: Int)
}

pub type GetError {
  KeyNotFound(key: List(String))
  WrongType(key: List(String), expected: String)
}

pub type EditError {
  EmptyKeyPath
  InvalidKeySegment(segment: String)
  InvalidCommentText
  MissingEditKey(key: List(String))
  KeyConflict(key: List(String))
}

pub fn new() -> Document {
  Document(
    root: ast.Table(entries: [], header: None),
    trailing_trivia: "",
    line_ending: Lf,
    original_source: None,
  )
}

pub fn parse(input: String) -> Result(Document, ParseError) {
  parse_string(input)
}

pub fn parse_bytes(input: BitArray) -> Result(Document, ParseError) {
  let utf8_bom = <<239, 187, 191>>
  let input_without_initial_bom = case bit_array.starts_with(input, utf8_bom) {
    True ->
      case bit_array.slice(input, 3, bit_array.byte_size(input) - 3) {
        Ok(rest) -> rest
        Error(_) -> input
      }
    False -> input
  }

  case bit_array_contains(input_without_initial_bom, utf8_bom) {
    True -> Error(InvalidEncoding)
    False ->
      case bit_array.to_string(input_without_initial_bom) {
        Ok(decoded) -> parse_string(decoded)
        Error(_) -> Error(InvalidEncoding)
      }
  }
}

fn bit_array_contains(input: BitArray, needle: BitArray) -> Bool {
  let input_size = bit_array.byte_size(input)
  case input_size < bit_array.byte_size(needle) {
    True -> False
    False ->
      case bit_array.starts_with(input, needle) {
        True -> True
        False ->
          case bit_array.slice(input, 1, input_size - 1) {
            Ok(rest) -> bit_array_contains(rest, needle)
            Error(_) -> False
          }
      }
  }
}

fn parse_string(input: String) -> Result(Document, ParseError) {
  let line_ending = case string.contains(input, "\r\n") {
    True -> Crlf
    False -> Lf
  }
  let input_without_initial_bom = drop_initial_bom(input)

  case string.contains(input_without_initial_bom, "\u{FEFF}") {
    True -> Error(InvalidEncoding)
    False -> {
      let normalized = string.replace(input_without_initial_bom, "\r\n", "\n")

      case parser.parse(normalized) {
        Ok(root) ->
          Ok(Document(
            root: root,
            trailing_trivia: "",
            line_ending: line_ending,
            original_source: Some(input),
          ))
        Error(parser.Unexpected(got, expected, offset)) ->
          Error(Unexpected(got, expected, offset))
        Error(parser.KeyAlreadyInUse(key, offset)) ->
          Error(KeyAlreadyInUse(key, offset))
      }
    }
  }
}

fn drop_initial_bom(input: String) -> String {
  case string.to_graphemes(input) {
    ["\u{FEFF}", ..rest] -> string.concat(rest)
    _ -> input
  }
}

pub fn to_string(doc: Document) -> String {
  case doc.original_source {
    Some(source) -> source
    None -> {
      let output = emit_table(doc.root) <> doc.trailing_trivia
      case doc.line_ending {
        Lf -> output
        Crlf -> string.replace(output, each: "\n", with: "\r\n")
      }
    }
  }
}

pub fn get_string(
  doc: Document,
  key: List(String),
) -> Result(String, GetError) {
  case get(doc, key) {
    Ok(ast.String(value, _, _)) -> Ok(value)
    Ok(_) -> Error(WrongType(key, "String"))
    Error(error) -> Error(error)
  }
}

pub fn get_int(doc: Document, key: List(String)) -> Result(Int, GetError) {
  case get(doc, key) {
    Ok(ast.Int(value, _)) -> Ok(value)
    Ok(_) -> Error(WrongType(key, "Int"))
    Error(error) -> Error(error)
  }
}

pub fn get_bool(doc: Document, key: List(String)) -> Result(Bool, GetError) {
  case get(doc, key) {
    Ok(ast.Bool(value, _)) -> Ok(value)
    Ok(_) -> Error(WrongType(key, "Bool"))
    Error(error) -> Error(error)
  }
}

pub fn get_float(doc: Document, key: List(String)) -> Result(Float, GetError) {
  case get(doc, key) {
    Ok(ast.Float(value, _)) -> Ok(value)
    Ok(_) -> Error(WrongType(key, "Float"))
    Error(error) -> Error(error)
  }
}

pub fn get(doc: Document, key: List(String)) -> Result(ast.Value, GetError) {
  path.get(doc.root, key)
  |> result.map_error(fn(_) { KeyNotFound(key) })
}

pub fn set_string(
  doc: Document,
  key: List(String),
  value: String,
) -> Result(Document, EditError) {
  set_value(
    doc,
    key,
    ast.String(value, ast.BasicString, basic_string_repr(value)),
  )
}

pub fn set_int(
  doc: Document,
  key: List(String),
  value: Int,
) -> Result(Document, EditError) {
  set_value(doc, key, ast.Int(value, int.to_string(value)))
}

pub fn remove(doc: Document, key: List(String)) -> Result(Document, EditError) {
  case validate_edit_key(key) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let Document(root: ast.Table(entries: entries, header: header), ..) = doc
      let #(next_entries, removed) = remove_entries(entries, [], key)
      case removed {
        True ->
          Ok(
            Document(
              ..doc,
              root: ast.Table(entries: next_entries, header: header),
              original_source: None,
            ),
          )
        False -> Error(MissingEditKey(key))
      }
    }
  }
}

pub fn insert_comment_before(
  doc: Document,
  key: List(String),
  text: String,
) -> Result(Document, EditError) {
  case validate_edit_key(key), validate_comment_text(text) {
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
    Ok(Nil), Ok(Nil) -> {
      let Document(
        root: ast.Table(entries: entries, header: header),
        trailing_trivia:,
        line_ending:,
        original_source: _,
      ) = doc
      let #(updated_entries, inserted) =
        insert_comment_before_entries(
          entries,
          key,
          [],
          ast.Comment(normalize_comment_text(text)),
        )

      case inserted {
        True ->
          Ok(Document(
            root: ast.Table(entries: updated_entries, header: header),
            trailing_trivia: trailing_trivia,
            line_ending: line_ending,
            original_source: None,
          ))
        False -> Error(MissingEditKey(key))
      }
    }
  }
}

fn insert_comment_before_entries(
  entries: List(ast.Entry),
  target: List(String),
  active_table: List(String),
  comment: ast.Entry,
) -> #(List(ast.Entry), Bool) {
  case entries {
    [] -> #([], False)
    [entry, ..rest] ->
      case entry {
        ast.TableHeader(header) -> {
          let table_key = header_key(header)
          case table_key == target {
            True -> #([comment, entry, ..rest], True)
            False -> {
              let #(updated_rest, inserted) =
                insert_comment_before_entries(rest, target, table_key, comment)
              #([entry, ..updated_rest], inserted)
            }
          }
        }
        ast.KeyValue(key: entry_key, ..) -> {
          let full_key = list.append(active_table, key_to_strings(entry_key))
          case full_key == target {
            True -> #([comment, entry, ..rest], True)
            False -> {
              let #(updated_rest, inserted) =
                insert_comment_before_entries(
                  rest,
                  target,
                  active_table,
                  comment,
                )
              #([entry, ..updated_rest], inserted)
            }
          }
        }
        _ -> {
          let #(updated_rest, inserted) =
            insert_comment_before_entries(rest, target, active_table, comment)
          #([entry, ..updated_rest], inserted)
        }
      }
  }
}

fn normalize_comment_text(text: String) -> String {
  let trimmed = string.trim(text)
  case trimmed {
    "" -> "#"
    _ ->
      case string.starts_with(trimmed, "#") {
        True -> trimmed
        False -> "# " <> trimmed
      }
  }
}

fn emit_table(table: ast.Table) -> String {
  case table {
    ast.Table(entries: [], header: _) -> ""
    ast.Table(entries: entries, header: _) ->
      entries
      |> list.map(emit_entry)
      |> string.join(with: "")
  }
}

fn remove_entries(
  entries: List(ast.Entry),
  active_table: List(String),
  target: List(String),
) -> #(List(ast.Entry), Bool) {
  case entries {
    [] -> #([], False)
    [entry, ..rest] ->
      case entry {
        ast.TableHeader(ast.Header(key: key, ..)) -> {
          let table_key = key_to_strings(key)
          let #(next_rest, removed) = remove_entries(rest, table_key, target)
          #([entry, ..next_rest], removed)
        }
        ast.KeyValue(key: key, ..) -> {
          let full_key = list.append(active_table, key_to_strings(key))
          let #(next_rest, removed) = remove_entries(rest, active_table, target)
          case full_key == target {
            True -> #(next_rest, True)
            False -> #([entry, ..next_rest], removed)
          }
        }
        _ -> {
          let #(next_rest, removed) = remove_entries(rest, active_table, target)
          #([entry, ..next_rest], removed)
        }
      }
  }
}

fn emit_entry(entry: ast.Entry) -> String {
  case entry {
    ast.KeyValue(leading, key, value, trailing) ->
      emit_trivia(leading)
      <> emit_key(key)
      <> " = "
      <> emit_value(value)
      <> emit_trivia(trailing)
    ast.TableHeader(header) -> emit_header(header) <> "\n"
    ast.Comment(text) -> text <> "\n"
    ast.BlankLine -> "\n"
  }
}

fn emit_header(header: ast.Header) -> String {
  let ast.Header(key: key, kind: kind, trivia: _) = header
  case kind {
    ast.StandardTable -> "[" <> emit_key(key) <> "]"
    ast.ArrayOfTablesHeader -> "[[" <> emit_key(key) <> "]]"
  }
}

fn emit_key(key: ast.Key) -> String {
  let ast.Key(segments) = key
  segments
  |> list.map(emit_key_segment)
  |> string.join(with: ".")
}

fn emit_key_segment(segment: ast.KeySegment) -> String {
  case segment {
    ast.BareKeySegment(text) -> text
    ast.QuotedKeySegment(_, source_text) -> source_text
  }
}

fn emit_value(value: ast.Value) -> String {
  case value {
    ast.Int(_, source_text) -> source_text
    ast.Float(_, source_text) -> source_text
    ast.SpecialFloat(_, source_text) -> source_text
    ast.Bool(_, source_text) -> source_text
    ast.String(_, _, source_text) -> source_text
    ast.Date(source_text) -> source_text
    ast.Time(source_text) -> source_text
    ast.DateTime(source_text) -> source_text
    ast.Array(_, source_text) -> source_text
    ast.InlineTable(_, source_text) -> source_text
    ast.ArrayOfTables(items) ->
      items
      |> list.map(emit_table)
      |> string.join(with: "")
  }
}

fn emit_trivia(trivia: ast.Trivia) -> String {
  let ast.Trivia(text) = trivia
  text
}

fn set_value(
  doc: Document,
  key: List(String),
  value: ast.Value,
) -> Result(Document, EditError) {
  case validate_edit_key(key) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let Document(
        root: root,
        trailing_trivia: trailing_trivia,
        line_ending: line_ending,
        original_source: _,
      ) = doc
      let ast.Table(entries: entries, header: header) = root
      let #(updated_entries, found) =
        update_existing_entries(entries, [], key, value)

      case found {
        True ->
          Ok(Document(
            root: ast.Table(entries: updated_entries, header: header),
            trailing_trivia: trailing_trivia,
            line_ending: line_ending,
            original_source: None,
          ))
        False ->
          case new_key_conflicts(entries, key) {
            True -> Error(KeyConflict(key))
            False -> {
              let assert Ok(#(parent, leaf)) = parent_and_leaf(key)
              let new_entry = new_key_value(leaf, value)
              let appended_entries =
                append_new_entry(updated_entries, parent, new_entry)
              Ok(Document(
                root: ast.Table(entries: appended_entries, header: header),
                trailing_trivia: trailing_trivia,
                line_ending: line_ending,
                original_source: None,
              ))
            }
          }
      }
    }
  }
}

fn update_existing_entries(
  entries: List(ast.Entry),
  active_table: List(String),
  target: List(String),
  value: ast.Value,
) -> #(List(ast.Entry), Bool) {
  case entries {
    [] -> #([], False)
    [entry, ..rest] -> {
      let next_active_table = case entry {
        ast.TableHeader(header) -> header_key(header)
        _ -> active_table
      }

      case entry {
        ast.KeyValue(leading: leading, key: key, value: _, trailing: trailing) -> {
          case list.append(active_table, key_to_strings(key)) == target {
            True -> #(
              [ast.KeyValue(leading, key, value, trailing), ..rest],
              True,
            )
            False -> {
              let #(updated_rest, found) =
                update_existing_entries(rest, next_active_table, target, value)
              #([entry, ..updated_rest], found)
            }
          }
        }
        _ -> {
          let #(updated_rest, found) =
            update_existing_entries(rest, next_active_table, target, value)
          #([entry, ..updated_rest], found)
        }
      }
    }
  }
}

fn append_new_entry(
  entries: List(ast.Entry),
  parent: List(String),
  new_entry: ast.Entry,
) -> List(ast.Entry) {
  case parent {
    [] -> append_root_entry(entries, new_entry)
    _ -> {
      let #(updated_entries, found) =
        append_table_entry(entries, parent, new_entry)
      case found {
        True -> updated_entries
        False -> list.append(entries, [new_table_header(parent), new_entry])
      }
    }
  }
}

fn append_root_entry(
  entries: List(ast.Entry),
  new_entry: ast.Entry,
) -> List(ast.Entry) {
  case entries {
    [] -> [new_entry]
    [entry, ..rest] ->
      case entry {
        ast.TableHeader(_) -> [new_entry, entry, ..rest]
        _ -> [entry, ..append_root_entry(rest, new_entry)]
      }
  }
}

fn append_table_entry(
  entries: List(ast.Entry),
  parent: List(String),
  new_entry: ast.Entry,
) -> #(List(ast.Entry), Bool) {
  case entries {
    [] -> #([], False)
    [entry, ..rest] ->
      case entry {
        ast.TableHeader(header) ->
          case
            header_key(header) == parent && header_is_standard_table(header)
          {
            True -> {
              let #(updated_rest, found) = append_inside_table(rest, new_entry)
              #([entry, ..updated_rest], found)
            }
            False -> {
              let #(updated_rest, found) =
                append_table_entry(rest, parent, new_entry)
              #([entry, ..updated_rest], found)
            }
          }
        _ -> {
          let #(updated_rest, found) =
            append_table_entry(rest, parent, new_entry)
          #([entry, ..updated_rest], found)
        }
      }
  }
}

fn append_inside_table(
  entries: List(ast.Entry),
  new_entry: ast.Entry,
) -> #(List(ast.Entry), Bool) {
  case entries {
    [] -> #([new_entry], True)
    [entry, ..rest] ->
      case entry {
        ast.TableHeader(_) -> #([new_entry, entry, ..rest], True)
        _ -> {
          let #(updated_rest, found) = append_inside_table(rest, new_entry)
          #([entry, ..updated_rest], found)
        }
      }
  }
}

fn new_key_conflicts(entries: List(ast.Entry), target: List(String)) -> Bool {
  new_key_conflicts_with_table(entries, [], target)
}

fn new_key_conflicts_with_table(
  entries: List(ast.Entry),
  active_table: List(String),
  target: List(String),
) -> Bool {
  case entries {
    [] -> False
    [entry, ..rest] -> {
      let next_active_table = case entry {
        ast.TableHeader(header) -> header_key(header)
        _ -> active_table
      }

      case entry {
        ast.TableHeader(header) ->
          header_conflicts_with_new_key(header, target)
          || new_key_conflicts_with_table(rest, next_active_table, target)
        ast.KeyValue(key: key, ..) -> {
          let full_key = list.append(active_table, key_to_strings(key))
          key_path_conflicts(full_key, target)
          || new_key_conflicts_with_table(rest, next_active_table, target)
        }
        _ -> new_key_conflicts_with_table(rest, next_active_table, target)
      }
    }
  }
}

fn header_conflicts_with_new_key(
  header: ast.Header,
  target: List(String),
) -> Bool {
  let ast.Header(kind: kind, ..) = header
  let key = header_key(header)
  case kind {
    ast.StandardTable -> target == key || list_starts_with(key, target)
    ast.ArrayOfTablesHeader -> key_path_conflicts(key, target)
  }
}

fn key_path_conflicts(existing: List(String), target: List(String)) -> Bool {
  list_starts_with(target, existing) || list_starts_with(existing, target)
}

fn list_starts_with(list_value: List(String), prefix: List(String)) -> Bool {
  case list_value, prefix {
    _, [] -> True
    [value, ..rest_values], [prefix_value, ..rest_prefix] ->
      value == prefix_value && list_starts_with(rest_values, rest_prefix)
    _, _ -> False
  }
}

fn new_key_value(key: String, value: ast.Value) -> ast.Entry {
  ast.KeyValue(
    leading: ast.Trivia(""),
    key: ast.Key([key_segment_from_string(key)]),
    value: value,
    trailing: ast.Trivia("\n"),
  )
}

fn new_table_header(key: List(String)) -> ast.Entry {
  ast.TableHeader(ast.Header(
    key: key_from_strings(key),
    kind: ast.StandardTable,
    trivia: ast.Trivia(""),
  ))
}

fn parent_and_leaf(key: List(String)) -> Result(#(List(String), String), Nil) {
  case key {
    [] -> Error(Nil)
    [leaf] -> Ok(#([], leaf))
    [segment, ..rest] -> {
      case parent_and_leaf(rest) {
        Ok(#(parent, leaf)) -> Ok(#([segment, ..parent], leaf))
        Error(Nil) -> Error(Nil)
      }
    }
  }
}

fn header_key(header: ast.Header) -> List(String) {
  let ast.Header(key: key, kind: _, trivia: _) = header
  key_to_strings(key)
}

fn header_is_standard_table(header: ast.Header) -> Bool {
  let ast.Header(kind: kind, ..) = header
  kind == ast.StandardTable
}

fn key_to_strings(key: ast.Key) -> List(String) {
  let ast.Key(segments) = key
  list.map(segments, fn(segment) {
    case segment {
      ast.BareKeySegment(text) -> text
      ast.QuotedKeySegment(value, source_text: _) -> value
    }
  })
}

fn key_from_strings(segments: List(String)) -> ast.Key {
  ast.Key(list.map(segments, key_segment_from_string))
}

fn key_segment_from_string(segment: String) -> ast.KeySegment {
  case is_bare_key(segment) {
    True -> ast.BareKeySegment(segment)
    False -> ast.QuotedKeySegment(segment, basic_string_repr(segment))
  }
}

fn validate_edit_key(key: List(String)) -> Result(Nil, EditError) {
  case key {
    [] -> Error(EmptyKeyPath)
    _ -> validate_key_segments(key)
  }
}

fn validate_key_segments(key: List(String)) -> Result(Nil, EditError) {
  case key {
    [] -> Ok(Nil)
    [segment, ..rest] ->
      case string.contains(segment, "\n") || string.contains(segment, "\r") {
        True -> Error(InvalidKeySegment(segment))
        False -> validate_key_segments(rest)
      }
  }
}

fn validate_comment_text(text: String) -> Result(Nil, EditError) {
  case string.contains(text, "\n") || string.contains(text, "\r") {
    True -> Error(InvalidCommentText)
    False -> Ok(Nil)
  }
}

fn is_bare_key(segment: String) -> Bool {
  string.length(segment) > 0
  && all_bare_key_codepoints(string.to_utf_codepoints(segment))
}

fn all_bare_key_codepoints(codepoints: List(UtfCodepoint)) -> Bool {
  case codepoints {
    [] -> True
    [codepoint, ..rest] ->
      is_bare_key_codepoint(string.utf_codepoint_to_int(codepoint))
      && all_bare_key_codepoints(rest)
  }
}

fn is_bare_key_codepoint(codepoint: Int) -> Bool {
  { codepoint >= 65 && codepoint <= 90 }
  || { codepoint >= 97 && codepoint <= 122 }
  || { codepoint >= 48 && codepoint <= 57 }
  || codepoint == 45
  || codepoint == 95
}

fn basic_string_repr(value: String) -> String {
  "\"" <> escape_basic_string(value) <> "\""
}

fn escape_basic_string(value: String) -> String {
  value
  |> string.to_utf_codepoints
  |> escape_basic_string_codepoints
}

fn escape_basic_string_codepoints(codepoints: List(UtfCodepoint)) -> String {
  case codepoints {
    [] -> ""
    [codepoint, ..rest] -> {
      let codepoint_int = string.utf_codepoint_to_int(codepoint)
      let escaped = case codepoint_int {
        8 -> "\\b"
        9 -> "\\t"
        10 -> "\\n"
        12 -> "\\f"
        13 -> "\\r"
        34 -> "\\\""
        92 -> "\\\\"
        i if i < 32 || i == 127 -> "\\u" <> padded_hex(i)
        _ -> string.from_utf_codepoints([codepoint])
      }
      escaped <> escape_basic_string_codepoints(rest)
    }
  }
}

fn padded_hex(value: Int) -> String {
  let assert Ok(hex) = int.to_base_string(value, 16)
  case string.length(hex) {
    1 -> "000" <> hex
    2 -> "00" <> hex
    3 -> "0" <> hex
    _ -> hex
  }
}
