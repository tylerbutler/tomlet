//// A round-tripping TOML parser and writer.
////
//// Tomlet parses TOML into an opaque `Document`, preserves comments and
//// formatting during round-trips, and provides checked helpers for common
//// reads and edits.

import gleam/bit_array
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tomlet/ast
import tomlet/parser
import tomlet/path

/// A parsed TOML document.
///
/// Documents are opaque so Tomlet can preserve round-trip invariants while the
/// internal syntax tree changes.
pub opaque type Document {
  Document(
    root: ast.Table,
    trailing_trivia: String,
    line_ending: LineEnding,
    original_source: Option(String),
  )
}

type LineEnding {
  Lf
  Crlf
}

/// Errors that can occur while parsing TOML input.
///
/// Variants are part of the stable public API. Adding, removing, or renaming a
/// variant is treated as a breaking change.
pub type ParseError {
  /// Raw bytes could not be decoded as valid TOML text.
  InvalidEncoding

  /// TOML syntax was invalid at a byte offset.
  InvalidSyntax(kind: SyntaxErrorKind, offset: Int)

  /// A key was defined more than once.
  DuplicateKey(key: List(String), offset: Int)
}

/// Stable categories for TOML syntax errors.
///
/// Variants are part of the stable public API. Adding, removing, or renaming a
/// variant is treated as a breaking change.
pub type SyntaxErrorKind {
  /// A TOML value was expected.
  ExpectedValue

  /// A TOML key was expected.
  ExpectedKey

  /// A table header, such as `[table]` or `[[array.table]]`, was expected.
  ExpectedTableHeader

  /// TOML syntax was invalid, but the parser does not expose a narrower stable category.
  ///
  /// This catches syntax errors that do not have a narrower stable category.
  InvalidToml
}

/// Errors that can occur while reading typed values from a document.
///
/// Variants are part of the stable public API. Adding, removing, or renaming a
/// variant is treated as a breaking change.
pub type GetError {
  /// No value exists at the requested key path.
  KeyNotFound(key: List(String))

  /// A value exists at the requested key path, but it has a different TOML type.
  WrongType(key: List(String), expected: String)
}

/// A TOML value without internal formatting trivia.
///
/// Variants are part of the stable public API. Adding, removing, or renaming a
/// variant is treated as a breaking change.
///
/// The table-shaped variants (`InlineTableValue`, `TableValue`,
/// `ArrayOfTablesValue`) expose their entries as an ordered association list of
/// `#(key_path, value)` pairs and will remain shaped that way. The key path is
/// the dotted path relative to the table, e.g. `["pkg", "name"]` for an entry
/// written as `pkg.name = ...` inside an inline table.
pub type Value {
  StringValue(String)
  IntValue(Int)
  FloatValue(Float)
  SpecialFloatValue(SpecialFloat)
  BoolValue(Bool)
  DateValue(Date)
  TimeValue(Time)
  DateTimeValue(DateTime)
  ArrayValue(List(Value))
  InlineTableValue(List(#(List(String), Value)))
  TableValue(List(#(List(String), Value)))
  ArrayOfTablesValue(List(List(#(List(String), Value))))
}

/// A TOML local date value.
///
/// Opaque so structured accessors can be added in a later release without
/// breaking existing code. Use `date_to_string` to read the original lexical
/// form (e.g. `"1979-05-27"`).
pub opaque type Date {
  Date(text: String)
}

/// A TOML local time value.
///
/// Opaque so structured accessors can be added in a later release without
/// breaking existing code. Use `time_to_string` to read the original lexical
/// form (e.g. `"07:32:00"`).
pub opaque type Time {
  Time(text: String)
}

/// A TOML date-time value.
///
/// Opaque so structured accessors can be added in a later release without
/// breaking existing code. Use `datetime_to_string` to read the original
/// lexical form (e.g. `"1979-05-27T07:32:00Z"`).
pub opaque type DateTime {
  DateTime(text: String)
}

/// Errors that can occur while constructing typed values from raw text.
///
/// Variants are part of the stable public API. Adding, removing, or renaming a
/// variant is treated as a breaking change.
pub type FormatError {
  /// The text is not a valid TOML local date literal (`YYYY-MM-DD`).
  InvalidDate(text: String)

  /// The text is not a valid TOML local time literal (`HH:MM:SS[.fraction]`).
  InvalidTime(text: String)

  /// The text is not a valid TOML date-time literal.
  InvalidDateTime(text: String)
}

/// Construct a `Date` from its TOML lexical form (e.g. `"1979-05-27"`).
///
/// ```gleam
/// let assert Ok(date) = tomlet.date_from_string("1979-05-27")
/// let assert Ok(doc) = tomlet.set_date(tomlet.new(), ["released"], date)
/// tomlet.to_string(doc)
/// // -> "released = 1979-05-27\n"
/// ```
pub fn date_from_string(text: String) -> Result(Date, FormatError) {
  case parser.date_repr_is_valid(text) {
    True -> Ok(Date(text))
    False -> Error(InvalidDate(text))
  }
}

/// Construct a `Time` from its TOML lexical form (e.g. `"07:32:00"`).
///
/// ```gleam
/// let assert Ok(time) = tomlet.time_from_string("07:32:00")
/// let assert Ok(doc) = tomlet.set_time(tomlet.new(), ["alarm"], time)
/// tomlet.to_string(doc)
/// // -> "alarm = 07:32:00\n"
/// ```
pub fn time_from_string(text: String) -> Result(Time, FormatError) {
  case parser.time_repr_is_valid(text) {
    True -> Ok(Time(text))
    False -> Error(InvalidTime(text))
  }
}

/// Construct a `DateTime` from its TOML lexical form
/// (e.g. `"1979-05-27T07:32:00Z"`).
///
/// ```gleam
/// let assert Ok(datetime) =
///   tomlet.datetime_from_string("1979-05-27T07:32:00Z")
/// let assert Ok(doc) =
///   tomlet.set_datetime(tomlet.new(), ["published"], datetime)
/// tomlet.to_string(doc)
/// // -> "published = 1979-05-27T07:32:00Z\n"
/// ```
pub fn datetime_from_string(text: String) -> Result(DateTime, FormatError) {
  case parser.datetime_repr_is_valid(text) {
    True -> Ok(DateTime(text))
    False -> Error(InvalidDateTime(text))
  }
}

/// Return the original lexical form of a TOML date value.
pub fn date_to_string(date: Date) -> String {
  date.text
}

/// Return the original lexical form of a TOML time value.
pub fn time_to_string(time: Time) -> String {
  time.text
}

/// Return the original lexical form of a TOML date-time value.
pub fn datetime_to_string(datetime: DateTime) -> String {
  datetime.text
}

/// A TOML special floating-point value.
///
/// Variants are part of the stable public API. Adding, removing, or renaming a
/// variant is treated as a breaking change.
///
/// ```gleam
/// let assert Ok(doc) = tomlet.parse("limit = inf\n")
/// let assert Ok(tomlet.SpecialFloatValue(tomlet.PositiveInfinity)) =
///   tomlet.get(doc, ["limit"])
/// ```
pub type SpecialFloat {
  PositiveInfinity
  NegativeInfinity
  NotANumber
}

/// Errors that can occur while editing a document.
///
/// Variants are part of the stable public API. Adding, removing, or renaming a
/// variant is treated as a breaking change.
pub type EditError {
  /// Edit paths must contain at least one key segment.
  EmptyKeyPath

  /// A key segment cannot be emitted as TOML.
  InvalidKeySegment(segment: String)

  /// Comments must be a single line.
  InvalidCommentText

  /// The edit requires an existing key, but no value exists at that key path.
  MissingEditKey(key: List(String))

  /// Inserting the key would conflict with an existing scalar, table, or array
  /// of tables.
  KeyConflict(key: List(String))

  /// The edit would have to insert a new key inside an existing inline table.
  ///
  /// Inline tables are written on a single line and cannot be extended in
  /// place. Rewrite the table shape explicitly (for example, with `set_*` on a
  /// standard table) instead of relying on implicit insertion.
  InlineTableInsertUnsupported(key: List(String))
}

/// Create an empty TOML document.
///
/// Equivalent to `parse("")` for downstream callers; the only observable
/// difference is that `parse("")` initially round-trips to `""` even after the
/// document is modified, while the document returned by `new` always emits its
/// current content.
pub fn new() -> Document {
  Document(
    root: ast.Table(entries: [], header: None),
    trailing_trivia: "",
    line_ending: Lf,
    original_source: None,
  )
}

/// Parse TOML 1.0 text into a document.
///
/// Successful parses return an opaque `Document` that preserves comments,
/// formatting trivia, key order, and the original line ending style for
/// round-tripping. Invalid text returns `ParseError`, including byte offsets for
/// syntax and duplicate-key diagnostics.
pub fn parse(input: String) -> Result(Document, ParseError) {
  parse_string(input)
}

/// Parse TOML bytes into a document.
///
/// This validates UTF-8 input and accepts a UTF-8 byte order mark only at the
/// start of the input.
///
/// ```gleam
/// let assert Ok(doc) = tomlet.parse_bytes(<<"answer = 42\n":utf8>>)
/// let assert Ok(answer) = tomlet.get_int(doc, ["answer"])
///
/// tomlet.parse_bytes(<<110, 97, 109, 101, 32, 61, 32, 255, 10>>)
/// // -> Error(tomlet.InvalidEncoding)
/// ```
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

  case bit_array_contains_utf8_bom(input_without_initial_bom) {
    True -> Error(InvalidEncoding)
    False ->
      case bit_array.to_string(input_without_initial_bom) {
        Ok(decoded) -> parse_string(decoded)
        Error(_) -> Error(InvalidEncoding)
      }
  }
}

/// A one-based source position.
///
/// Positions are opaque so Tomlet can add more source-location details later
/// without changing the public constructor shape. Use `position_line` and
/// `position_column` to inspect one.
pub opaque type Position {
  Position(line: Int, column: Int)
}

/// Convert a byte offset into a one-based line and column.
///
/// Offsets beyond the end of the input return the position just after the last
/// character. CRLF is treated as a single line break.
///
/// ```gleam
/// let input = "name = \n"
/// case tomlet.parse(input) {
///   Error(tomlet.InvalidSyntax(_, offset)) -> {
///     let position = tomlet.line_column(input, offset)
///     let line = tomlet.position_line(position)
///     let column = tomlet.position_column(position)
///     // Show line and column in your application's diagnostic.
///   }
///   _ -> Nil
/// }
/// ```
pub fn line_column(input: String, offset: Int) -> Position {
  let #(line, column) =
    line_column_loop(string.to_utf_codepoints(input), offset, 0, 1, 1)
  Position(line: line, column: column)
}

/// Return the one-based line number for a source position.
pub fn position_line(position: Position) -> Int {
  position.line
}

/// Return the one-based column number for a source position.
pub fn position_column(position: Position) -> Int {
  position.column
}

fn line_column_loop(
  codepoints: List(UtfCodepoint),
  target: Int,
  current: Int,
  line: Int,
  column: Int,
) -> #(Int, Int) {
  case current >= target, codepoints {
    True, _ -> #(line, column)
    False, [] -> #(line, column)
    False, [first, second, ..rest] -> {
      case
        string.utf_codepoint_to_int(first),
        string.utf_codepoint_to_int(second)
      {
        13, 10 -> line_column_loop(rest, target, current + 2, line + 1, 1)
        _, _ ->
          line_column_next(
            [first, second, ..rest],
            target,
            current,
            line,
            column,
          )
      }
    }
    False, remaining ->
      line_column_next(remaining, target, current, line, column)
  }
}

fn line_column_next(
  codepoints: List(UtfCodepoint),
  target: Int,
  current: Int,
  line: Int,
  column: Int,
) -> #(Int, Int) {
  case codepoints {
    [] -> #(line, column)
    [codepoint, ..rest] -> {
      case string.utf_codepoint_to_int(codepoint) {
        10 -> line_column_loop(rest, target, current + 1, line + 1, 1)
        13 -> line_column_loop(rest, target, current + 1, line + 1, 1)
        _ -> {
          let width = string.byte_size(string.from_utf_codepoints([codepoint]))
          line_column_loop(rest, target, current + width, line, column + 1)
        }
      }
    }
  }
}

fn bit_array_contains_utf8_bom(input: BitArray) -> Bool {
  case input {
    <<>> -> False
    <<239, 187, 191, _rest:bits>> -> True
    <<_, rest:bits>> -> bit_array_contains_utf8_bom(rest)
    _ -> False
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
      // Parsed AST source_text is LF-only; CRLF is tracked separately on Document.
      let normalized = string.replace(input_without_initial_bom, "\r\n", "\n")

      case parser.parse(normalized) {
        Ok(root) ->
          Ok(Document(
            root: root,
            trailing_trivia: "",
            line_ending: line_ending,
            original_source: Some(input),
          ))
        Error(parser.Unexpected(_got, expected, offset)) ->
          Error(InvalidSyntax(syntax_error_kind(expected), offset))
        Error(parser.KeyAlreadyInUse(key, offset)) ->
          Error(DuplicateKey(key, offset))
      }
    }
  }
}

fn syntax_error_kind(expected: parser.ExpectedTokenKind) -> SyntaxErrorKind {
  case expected {
    parser.ExpectedValue -> ExpectedValue
    parser.ExpectedKey -> ExpectedKey
    parser.ExpectedTableHeader -> ExpectedTableHeader
    parser.ExpectedSyntax -> InvalidToml
  }
}

fn drop_initial_bom(input: String) -> String {
  case string.to_graphemes(input) {
    ["\u{FEFF}", ..rest] -> string.concat(rest)
    _ -> input
  }
}

/// Emit a document as TOML text.
///
/// Unedited parsed documents round-trip to their original source text.
pub fn to_string(doc: Document) -> String {
  case doc.original_source {
    Some(source) -> source
    None -> {
      let output = emit_table(doc.root) <> doc.trailing_trivia
      case doc.line_ending {
        Lf -> output
        // Safe because every stored source_text fragment was normalized to LF.
        Crlf -> string.replace(output, each: "\n", with: "\r\n")
      }
    }
  }
}

/// Read a TOML value at a key path.
///
/// Use `get` instead of the typed `get_*` helpers when you need to inspect
/// arrays, inline tables, standard tables, arrays of tables, or special floats.
///
/// ```gleam
/// let assert Ok(doc) =
///   tomlet.parse("package = { name = \"tomato\", downloads = 42 }\n")
/// let assert Ok(value) = tomlet.get(doc, ["package"])
/// // -> tomlet.InlineTableValue([
/// //   #(["name"], tomlet.StringValue("tomato")),
/// //   #(["downloads"], tomlet.IntValue(42)),
/// // ])
/// ```
pub fn get(doc: Document, key: List(String)) -> Result(Value, GetError) {
  case get_value(doc, key) {
    Ok(value) -> Ok(public_value(value))
    Error(_) -> get_table_value(doc, key)
  }
}

/// Read a TOML string value at a key path.
pub fn get_string(
  doc: Document,
  key: List(String),
) -> Result(String, GetError) {
  case get_value(doc, key) {
    Ok(ast.String(value, _, _)) -> Ok(value)
    Ok(_) -> Error(WrongType(key, "String"))
    Error(error) -> Error(error)
  }
}

/// Read a TOML integer value at a key path.
pub fn get_int(doc: Document, key: List(String)) -> Result(Int, GetError) {
  case get_value(doc, key) {
    Ok(ast.Int(value, _)) -> Ok(value)
    Ok(_) -> Error(WrongType(key, "Int"))
    Error(error) -> Error(error)
  }
}

/// Read a TOML boolean value at a key path.
pub fn get_bool(doc: Document, key: List(String)) -> Result(Bool, GetError) {
  case get_value(doc, key) {
    Ok(ast.Bool(value, _)) -> Ok(value)
    Ok(_) -> Error(WrongType(key, "Bool"))
    Error(error) -> Error(error)
  }
}

/// Read a TOML float value at a key path.
pub fn get_float(doc: Document, key: List(String)) -> Result(Float, GetError) {
  case get_value(doc, key) {
    Ok(ast.Float(value, _)) -> Ok(value)
    Ok(_) -> Error(WrongType(key, "Float"))
    Error(error) -> Error(error)
  }
}

/// Read a TOML local date value at a key path.
pub fn get_date(doc: Document, key: List(String)) -> Result(Date, GetError) {
  case get_value(doc, key) {
    Ok(ast.Date(source_text)) -> Ok(Date(source_text))
    Ok(_) -> Error(WrongType(key, "Date"))
    Error(error) -> Error(error)
  }
}

/// Read a TOML local time value at a key path.
pub fn get_time(doc: Document, key: List(String)) -> Result(Time, GetError) {
  case get_value(doc, key) {
    Ok(ast.Time(source_text)) -> Ok(Time(source_text))
    Ok(_) -> Error(WrongType(key, "Time"))
    Error(error) -> Error(error)
  }
}

/// Read a TOML date-time value at a key path.
pub fn get_datetime(
  doc: Document,
  key: List(String),
) -> Result(DateTime, GetError) {
  case get_value(doc, key) {
    Ok(ast.DateTime(source_text)) -> Ok(DateTime(source_text))
    Ok(_) -> Error(WrongType(key, "DateTime"))
    Error(error) -> Error(error)
  }
}

fn get_value(doc: Document, key: List(String)) -> Result(ast.Value, GetError) {
  path.get(doc.root, key)
  |> result.map_error(fn(_) { KeyNotFound(key) })
}

fn get_table_value(
  doc: Document,
  key: List(String),
) -> Result(Value, GetError) {
  case key {
    [] -> Error(KeyNotFound(key))
    _ -> {
      let Document(root: ast.Table(entries: entries, ..), ..) = doc
      let #(table_entries, found) =
        collect_table_entries(entries, [], key, False, [])
      case found {
        True -> Ok(TableValue(table_entries))
        False -> Error(KeyNotFound(key))
      }
    }
  }
}

fn public_value(value: ast.Value) -> Value {
  case value {
    ast.Int(value, source_text: _) -> IntValue(value)
    ast.Float(value, source_text: _) -> FloatValue(value)
    ast.SpecialFloat(value, source_text: _) ->
      SpecialFloatValue(public_special_float(value))
    ast.Bool(value, source_text: _) -> BoolValue(value)
    ast.String(value, style: _, source_text: _) -> StringValue(value)
    ast.Date(source_text) -> DateValue(Date(source_text))
    ast.Time(source_text) -> TimeValue(Time(source_text))
    ast.DateTime(source_text) -> DateTimeValue(DateTime(source_text))
    ast.Array(items, source_text: _) ->
      ArrayValue(list.map(items, public_array_item))
    ast.InlineTable(entries, source_text: _) ->
      InlineTableValue(list.map(entries, public_inline_table_entry))
    ast.ArrayOfTables(items) ->
      ArrayOfTablesValue(list.map(items, public_table_entries))
  }
}

fn public_special_float(value: ast.SpecialFloat) -> SpecialFloat {
  case value {
    ast.PositiveInfinity -> PositiveInfinity
    ast.NegativeInfinity -> NegativeInfinity
    ast.NotANumber -> NotANumber
  }
}

fn public_array_item(item: ast.ArrayItem) -> Value {
  let ast.ArrayItem(leading: _, value: value, trailing: _) = item
  public_value(value)
}

fn public_inline_table_entry(
  entry: ast.InlineTableEntry,
) -> #(List(String), Value) {
  let ast.InlineTableEntry(leading: _, key: key, value: value, trailing: _) =
    entry
  #(key_to_strings(key), public_value(value))
}

fn public_table_entries(table: ast.Table) -> List(#(List(String), Value)) {
  let ast.Table(entries: entries, header: _) = table
  let #(table_entries, _) = collect_table_entries(entries, [], [], True, [])
  table_entries
}

fn collect_table_entries(
  entries: List(ast.Entry),
  active_table: List(String),
  target: List(String),
  found: Bool,
  collected: List(#(List(String), Value)),
) -> #(List(#(List(String), Value)), Bool) {
  case entries {
    [] -> #(list.reverse(collected), found)
    [entry, ..rest] -> {
      let next_active_table = case entry {
        ast.TableHeader(header) -> header_key(header)
        _ -> active_table
      }
      let next_found = case entry {
        ast.TableHeader(header) ->
          found
          || {
            header_is_standard_table(header) && header_key(header) == target
          }
        _ -> found
      }
      case entry {
        ast.KeyValue(key: key, value: value, ..) -> {
          let full_key = list.append(active_table, key_to_strings(key))
          case list_starts_with(full_key, target) && full_key != target {
            True ->
              collect_table_entries(rest, next_active_table, target, True, [
                #(drop_prefix(full_key, target), public_value(value)),
                ..collected
              ])
            False ->
              collect_table_entries(
                rest,
                next_active_table,
                target,
                next_found,
                collected,
              )
          }
        }
        _ ->
          collect_table_entries(
            rest,
            next_active_table,
            target,
            next_found,
            collected,
          )
      }
    }
  }
}

fn drop_prefix(values: List(String), prefix: List(String)) -> List(String) {
  case values, prefix {
    rest, [] -> rest
    [_, ..rest], [_, ..prefix_rest] -> drop_prefix(rest, prefix_rest)
    _, _ -> []
  }
}

/// Set a TOML string value at a key path.
///
/// Existing values are replaced in place. Missing keys are inserted, creating a
/// table header when needed.
///
/// ```gleam
/// let assert Ok(doc) =
///   tomlet.set_string(tomlet.new(), ["package", "name"], "tomlet")
/// tomlet.to_string(doc)
/// // -> "
/// // [package]
/// // name = \"tomlet\"
/// // "
/// ```
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

/// Set a TOML integer value at a key path.
///
/// Existing values are replaced in place. Missing keys are inserted, creating a
/// table header when needed.
pub fn set_int(
  doc: Document,
  key: List(String),
  value: Int,
) -> Result(Document, EditError) {
  set_value(doc, key, ast.Int(value, int.to_string(value)))
}

/// Set a TOML boolean value at a key path.
///
/// Existing values are replaced in place. Missing keys are inserted, creating a
/// table header when needed.
pub fn set_bool(
  doc: Document,
  key: List(String),
  value: Bool,
) -> Result(Document, EditError) {
  let repr = case value {
    True -> "true"
    False -> "false"
  }
  set_value(doc, key, ast.Bool(value, repr))
}

/// Set a TOML float value at a key path.
///
/// Existing values are replaced in place. Missing keys are inserted, creating a
/// table header when needed.
pub fn set_float(
  doc: Document,
  key: List(String),
  value: Float,
) -> Result(Document, EditError) {
  set_value(doc, key, ast.Float(value, float.to_string(value)))
}

/// Set a TOML local date value at a key path.
///
/// Existing values are replaced in place. Missing keys are inserted, creating a
/// table header when needed.
pub fn set_date(
  doc: Document,
  key: List(String),
  value: Date,
) -> Result(Document, EditError) {
  set_value(doc, key, ast.Date(value.text))
}

/// Set a TOML local time value at a key path.
///
/// Existing values are replaced in place. Missing keys are inserted, creating a
/// table header when needed.
pub fn set_time(
  doc: Document,
  key: List(String),
  value: Time,
) -> Result(Document, EditError) {
  set_value(doc, key, ast.Time(value.text))
}

/// Set a TOML date-time value at a key path.
///
/// Existing values are replaced in place. Missing keys are inserted, creating a
/// table header when needed.
pub fn set_datetime(
  doc: Document,
  key: List(String),
  value: DateTime,
) -> Result(Document, EditError) {
  set_value(doc, key, ast.DateTime(value.text))
}

/// Set a TOML array value at a key path.
///
/// Items are emitted in order using a default flow-style representation
/// (`[a, b, c]`). Existing values are replaced in place. Missing keys are
/// inserted, creating a table header when needed.
///
/// ```gleam
/// let assert Ok(doc) =
///   tomlet.set_array(tomlet.new(), ["ports"], [
///     tomlet.IntValue(8000),
///     tomlet.IntValue(8001),
///   ])
/// tomlet.to_string(doc)
/// // -> "ports = [8000, 8001]\n"
/// ```
pub fn set_array(
  doc: Document,
  key: List(String),
  items: List(Value),
) -> Result(Document, EditError) {
  let ast_items = list.map(items, value_to_array_item)
  set_value(doc, key, ast.Array(ast_items, emit_array_items(ast_items)))
}

/// Set a TOML inline table value at a key path.
///
/// Entries are emitted in order using a default flow-style representation
/// (`{ a = 1, b = 2 }`). Each entry's key path is rendered as a dotted key
/// when it contains more than one segment. Existing values are replaced in
/// place. Missing keys are inserted, creating a table header when needed.
///
/// ```gleam
/// let assert Ok(doc) =
///   tomlet.set_inline_table(tomlet.new(), ["pkg"], [
///     #(["name"], tomlet.StringValue("tomato")),
///     #(["meta", "downloads"], tomlet.IntValue(42)),
///   ])
/// tomlet.to_string(doc)
/// // -> "pkg = { name = \"tomato\", meta.downloads = 42 }\n"
/// ```
pub fn set_inline_table(
  doc: Document,
  key: List(String),
  entries: List(#(List(String), Value)),
) -> Result(Document, EditError) {
  case validate_inline_entry_keys(entries) {
    Error(error) -> Error(error)
    Ok(Nil) -> {
      let ast_entries = list.map(entries, value_to_inline_entry)
      set_value(
        doc,
        key,
        ast.InlineTable(ast_entries, emit_inline_table(ast_entries)),
      )
    }
  }
}

/// Append a new table to an array of tables at a key path.
///
/// A `[[key]]` header is appended to the document followed by the supplied
/// entries. Works whether or not an array of tables already exists at the key
/// path; if no array of tables exists yet, a new one is created.
///
/// ```gleam
/// let assert Ok(doc) =
///   tomlet.append_array_of_tables(tomlet.new(), ["packages"], [
///     #(["name"], tomlet.StringValue("tomato")),
///   ])
/// tomlet.to_string(doc)
/// // -> "
/// // [[packages]]
/// // name = \"tomato\"
/// // "
/// ```
pub fn append_array_of_tables(
  doc: Document,
  key: List(String),
  entries: List(#(List(String), Value)),
) -> Result(Document, EditError) {
  case validate_edit_key(key) {
    Error(error) -> Error(error)
    Ok(Nil) ->
      case validate_inline_entry_keys(entries) {
        Error(error) -> Error(error)
        Ok(Nil) -> {
          let Document(
            root: ast.Table(entries: doc_entries, header: header),
            ..,
          ) = doc
          case array_of_tables_key_conflicts(doc_entries, [], False, key) {
            True -> Error(KeyConflict(key))
            False -> {
              let new_entries =
                list.append(
                  [
                    ast.TableHeader(ast.Header(
                      key: key_from_strings(key),
                      kind: ast.ArrayOfTablesHeader,
                      trivia: ast.Trivia(""),
                    )),
                  ],
                  list.map(entries, fn(entry) {
                    let #(path, value) = entry
                    ast.KeyValue(
                      leading: ast.Trivia(""),
                      key: key_from_strings(path),
                      value: value_to_ast(value),
                      trailing: ast.Trivia("\n"),
                    )
                  }),
                )
              Ok(
                Document(
                  ..doc,
                  root: ast.Table(
                    entries: list.append(doc_entries, new_entries),
                    header: header,
                  ),
                  original_source: None,
                ),
              )
            }
          }
        }
      }
  }
}

fn value_to_ast(value: Value) -> ast.Value {
  case value {
    StringValue(s) -> ast.String(s, ast.BasicString, basic_string_repr(s))
    IntValue(i) -> ast.Int(i, int.to_string(i))
    FloatValue(f) -> ast.Float(f, float.to_string(f))
    SpecialFloatValue(s) -> {
      let #(internal, source_text) = case s {
        PositiveInfinity -> #(ast.PositiveInfinity, "inf")
        NegativeInfinity -> #(ast.NegativeInfinity, "-inf")
        NotANumber -> #(ast.NotANumber, "nan")
      }
      ast.SpecialFloat(internal, source_text)
    }
    BoolValue(b) -> {
      let repr = case b {
        True -> "true"
        False -> "false"
      }
      ast.Bool(b, repr)
    }
    DateValue(d) -> ast.Date(d.text)
    TimeValue(t) -> ast.Time(t.text)
    DateTimeValue(d) -> ast.DateTime(d.text)
    ArrayValue(items) -> {
      let ast_items = list.map(items, value_to_array_item)
      ast.Array(ast_items, emit_array_items(ast_items))
    }
    InlineTableValue(entries) -> {
      let ast_entries = list.map(entries, value_to_inline_entry)
      ast.InlineTable(ast_entries, emit_inline_table(ast_entries))
    }
    // TableValue inside a Value is rendered as an inline table; the only
    // structural difference between `TableValue` and `InlineTableValue` is
    // where they appear in a document, and nested values can only embed
    // inline tables.
    TableValue(entries) -> {
      let ast_entries = list.map(entries, value_to_inline_entry)
      ast.InlineTable(ast_entries, emit_inline_table(ast_entries))
    }
    ArrayOfTablesValue(items) -> {
      let ast_items =
        list.map(items, fn(entries) {
          let ast_entries = list.map(entries, value_to_inline_entry)
          ast.ArrayItem(
            leading: ast.Trivia(""),
            value: ast.InlineTable(ast_entries, emit_inline_table(ast_entries)),
            trailing: ast.Trivia(""),
          )
        })
      ast.Array(ast_items, emit_array_items(ast_items))
    }
  }
}

fn value_to_array_item(value: Value) -> ast.ArrayItem {
  ast.ArrayItem(
    leading: ast.Trivia(""),
    value: value_to_ast(value),
    trailing: ast.Trivia(""),
  )
}

fn value_to_inline_entry(
  entry: #(List(String), Value),
) -> ast.InlineTableEntry {
  let #(path, value) = entry
  ast.InlineTableEntry(
    leading: ast.Trivia(""),
    key: key_from_strings(path),
    value: value_to_ast(value),
    trailing: ast.Trivia(""),
  )
}

fn emit_array_items(items: List(ast.ArrayItem)) -> String {
  case items {
    [] -> "[]"
    _ ->
      "["
      <> {
        items
        |> list.map(fn(item) {
          let ast.ArrayItem(leading: _, value: value, trailing: _) = item
          emit_value(value)
        })
        |> string.join(with: ", ")
      }
      <> "]"
  }
}

fn validate_inline_entry_keys(
  entries: List(#(List(String), Value)),
) -> Result(Nil, EditError) {
  case entries {
    [] -> Ok(Nil)
    [#(path, _), ..rest] ->
      case validate_edit_key(path) {
        Error(error) -> Error(error)
        Ok(Nil) -> validate_inline_entry_keys(rest)
      }
  }
}

fn array_of_tables_key_conflicts(
  entries: List(ast.Entry),
  active_table: List(String),
  in_aot: Bool,
  target: List(String),
) -> Bool {
  case entries {
    [] -> False
    [entry, ..rest] -> {
      let #(next_active_table, next_in_aot) = case entry {
        ast.TableHeader(ast.Header(key: key, kind: kind, trivia: _)) -> #(
          key_to_strings(key),
          kind == ast.ArrayOfTablesHeader,
        )
        _ -> #(active_table, in_aot)
      }
      let conflicts = case entry {
        ast.TableHeader(ast.Header(key: key, kind: ast.StandardTable, trivia: _)) ->
          key_to_strings(key) == target
        ast.TableHeader(ast.Header(
          key: key,
          kind: ast.ArrayOfTablesHeader,
          trivia: _,
        )) -> {
          let header_key = key_to_strings(key)
          // Appending to an existing array of tables at the same path is the
          // intended behavior; only flag prefix-overlapping AoT headers as
          // conflicts.
          header_key != target && key_path_conflicts(header_key, target)
        }
        ast.KeyValue(key: key, ..) ->
          case in_aot {
            // KeyValues inside an AoT instance are scoped to that instance
            // and do not conflict with root-level paths.
            True -> False
            False -> {
              let full_key = list.append(active_table, key_to_strings(key))
              key_path_conflicts(full_key, target)
            }
          }
        _ -> False
      }
      conflicts
      || array_of_tables_key_conflicts(
        rest,
        next_active_table,
        next_in_aot,
        target,
      )
    }
  }
}

/// Remove an existing value from a document.
///
/// Returns `MissingEditKey` when the key path does not exist, and
/// `EmptyKeyPath` when the key path is empty.
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

/// Insert a standalone comment before an existing key.
///
/// The comment text may include a leading `#`, but must not contain TOML
/// comment control characters. Returns `MissingEditKey` when the target key
/// does not exist, `InvalidCommentText` when the comment is unsafe to emit, and
/// `EmptyKeyPath` when the key path is empty.
///
/// ```gleam
/// let assert Ok(doc) = tomlet.parse("released = 1979-05-27\n")
/// let assert Ok(doc) =
///   tomlet.insert_comment_before(doc, ["released"], "release date")
/// tomlet.to_string(doc)
/// // -> "
/// // # release date
/// // released = 1979-05-27
/// // "
/// ```
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

fn emit_inline_table(entries: List(ast.InlineTableEntry)) -> String {
  case entries {
    [] -> "{}"
    _ ->
      "{ "
      <> {
        entries
        |> list.map(emit_inline_table_entry)
        |> string.join(with: ", ")
      }
      <> " }"
  }
}

fn emit_inline_table_entry(entry: ast.InlineTableEntry) -> String {
  let ast.InlineTableEntry(leading, key, value, trailing) = entry
  emit_trivia(leading)
  <> emit_key(key)
  <> " = "
  <> emit_value(value)
  <> emit_trivia(trailing)
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
          case inline_table_blocks_key(entries, [], key) {
            True -> Error(InlineTableInsertUnsupported(key))
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
        ast.KeyValue(
          leading: leading,
          key: key,
          value: entry_value,
          trailing: trailing,
        ) -> {
          let full_key = list.append(active_table, key_to_strings(key))
          case full_key == target {
            True -> #(
              [ast.KeyValue(leading, key, value, trailing), ..rest],
              True,
            )
            False ->
              case entry_value {
                ast.InlineTable(entries, source_text: _) -> {
                  let #(updated_inline_entries, inline_found) =
                    update_inline_entries(entries, full_key, target, value)
                  case inline_found {
                    True -> {
                      let updated_value =
                        ast.InlineTable(
                          updated_inline_entries,
                          emit_inline_table(updated_inline_entries),
                        )
                      #(
                        [
                          ast.KeyValue(leading, key, updated_value, trailing),
                          ..rest
                        ],
                        True,
                      )
                    }
                    False -> {
                      let #(updated_rest, found) =
                        update_existing_entries(
                          rest,
                          next_active_table,
                          target,
                          value,
                        )
                      #([entry, ..updated_rest], found)
                    }
                  }
                }
                _ -> {
                  let #(updated_rest, found) =
                    update_existing_entries(
                      rest,
                      next_active_table,
                      target,
                      value,
                    )
                  #([entry, ..updated_rest], found)
                }
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

fn update_inline_entries(
  entries: List(ast.InlineTableEntry),
  active_path: List(String),
  target: List(String),
  value: ast.Value,
) -> #(List(ast.InlineTableEntry), Bool) {
  case entries {
    [] -> #([], False)
    [
      ast.InlineTableEntry(
        leading: leading,
        key: key,
        value: entry_value,
        trailing: trailing,
      ),
      ..rest
    ] -> {
      let full_key = list.append(active_path, key_to_strings(key))
      case full_key == target {
        True -> #(
          [ast.InlineTableEntry(leading, key, value, trailing), ..rest],
          True,
        )
        False ->
          case entry_value {
            ast.InlineTable(nested_entries, source_text: _) -> {
              let #(updated_nested_entries, nested_found) =
                update_inline_entries(nested_entries, full_key, target, value)
              case nested_found {
                True -> {
                  let updated_value =
                    ast.InlineTable(
                      updated_nested_entries,
                      emit_inline_table(updated_nested_entries),
                    )
                  #(
                    [
                      ast.InlineTableEntry(
                        leading,
                        key,
                        updated_value,
                        trailing,
                      ),
                      ..rest
                    ],
                    True,
                  )
                }
                False -> {
                  let #(updated_rest, found) =
                    update_inline_entries(rest, active_path, target, value)
                  #(
                    [
                      ast.InlineTableEntry(leading, key, entry_value, trailing),
                      ..updated_rest
                    ],
                    found,
                  )
                }
              }
            }
            _ -> {
              let #(updated_rest, found) =
                update_inline_entries(rest, active_path, target, value)
              #(
                [
                  ast.InlineTableEntry(leading, key, entry_value, trailing),
                  ..updated_rest
                ],
                found,
              )
            }
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

fn inline_table_blocks_key(
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
      let blocks = case entry {
        ast.KeyValue(key: key, value: ast.InlineTable(..), ..) -> {
          let full_key = list.append(active_table, key_to_strings(key))
          list_starts_with(target, full_key) && full_key != target
        }
        _ -> False
      }
      blocks || inline_table_blocks_key(rest, next_active_table, target)
    }
  }
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
  text
  |> string.to_utf_codepoints
  |> validate_comment_codepoints
}

fn validate_comment_codepoints(
  codepoints: List(UtfCodepoint),
) -> Result(Nil, EditError) {
  case codepoints {
    [] -> Ok(Nil)
    [codepoint, ..rest] -> {
      let value = string.utf_codepoint_to_int(codepoint)
      case { value <= 8 } || { value >= 10 && value <= 31 } || value == 127 {
        True -> Error(InvalidCommentText)
        False -> validate_comment_codepoints(rest)
      }
    }
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
