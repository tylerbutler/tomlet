//// Internal module -- not part of Tomlet's public API.
////
//// This module may change without notice. Use the top-level `tomlet` module
//// for supported parsing, reading, editing, and writing APIs.

import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import tomlet/ast
import tomlet/key as key_utils
import tomlet/lexer
import william

pub type ParseError {
  Unexpected(got: String, expected: ExpectedTokenKind, offset: Int)
  KeyAlreadyInUse(key: List(String), offset: Int)
}

pub type ExpectedTokenKind {
  ExpectedValue
  ExpectedKey
  ExpectedTableHeader
  ExpectedSyntax
}

/// The TOML language version a document should be parsed against. Phase 1 only
/// implements TOML 1.0 behaviour; the variant is threaded through so later
/// phases can opt into 1.1 relaxations without changing the call sites.
pub type Version {
  Toml10
  Toml11
}

/// Parse normalized (LF-only, BOM-stripped) TOML source into the internal AST
/// using a token-driven assembly over the `william` lexer.
pub fn parse(input: String, version: Version) -> Result(ast.Table, ParseError) {
  // Disallowed control characters are never valid anywhere in TOML, so reject
  // them up front with a byte-accurate offset. This mirrors the per-line check
  // the legacy parser performed and keeps the token walk below simpler.
  case first_disallowed_control_offset(input) {
    Ok(offset) -> Error(Unexpected("", ExpectedSyntax, offset))
    Error(Nil) -> assemble(lexer.lex(input), version)
  }
}

type AssemblyState {
  AssemblyState(
    active_table: List(String),
    seen: List(List(String)),
    explicit_tables: List(List(String)),
    array_tables: List(List(String)),
    array_table_parents: List(List(String)),
    dotted_tables: List(List(String)),
  )
}

fn assemble(
  spans: List(lexer.Spanned),
  version: Version,
) -> Result(ast.Table, ParseError) {
  assemble_loop(
    spans,
    AssemblyState(
      active_table: [],
      seen: [],
      explicit_tables: [],
      array_tables: [],
      array_table_parents: [],
      dotted_tables: [],
    ),
    [],
    version,
  )
}

fn assemble_loop(
  spans: List(lexer.Spanned),
  state: AssemblyState,
  entries: List(ast.Entry),
  version: Version,
) -> Result(ast.Table, ParseError) {
  let #(leading_ws, rest) = take_whitespace(spans, "")
  case rest {
    [] ->
      case leading_ws {
        // A trailing whitespace-only segment with no newline is still a blank
        // line; a clean end-of-input is not.
        "" -> Ok(ast.Table(entries: list.reverse(entries), header: None))
        _ ->
          Ok(ast.Table(
            entries: list.reverse([ast.BlankLine, ..entries]),
            header: None,
          ))
      }
    [lexer.Spanned(william.EndOfLine(_), _), ..tail] ->
      assemble_loop(tail, state, [ast.BlankLine, ..entries], version)

    [lexer.Spanned(william.Comment(text), _), ..tail] ->
      assemble_loop(
        drop_one_eol(tail),
        state,
        [ast.Comment(leading_ws <> text), ..entries],
        version,
      )

    [lexer.Spanned(william.OpenTable, offset), ..tail] ->
      parse_header_tokens(
        tail,
        ast.StandardTable,
        offset,
        state,
        entries,
        version,
      )

    [lexer.Spanned(william.OpenArrayTable, offset), ..tail] ->
      parse_header_tokens(
        tail,
        ast.ArrayOfTablesHeader,
        offset,
        state,
        entries,
        version,
      )

    [lexer.Spanned(william.BareKey(_), offset), ..]
    | [lexer.Spanned(william.String(_, _), offset), ..] ->
      parse_key_value_tokens(rest, offset, state, entries, version)

    [lexer.Spanned(token, offset), ..] ->
      Error(Unexpected(token_src(token), ExpectedSyntax, offset))
  }
}

fn token_src(token: william.Token) -> String {
  william.to_source([token])
}

fn take_whitespace(
  spans: List(lexer.Spanned),
  acc: String,
) -> #(String, List(lexer.Spanned)) {
  case spans {
    [lexer.Spanned(william.Whitespace(text), _), ..rest] ->
      take_whitespace(rest, acc <> text)
    _ -> #(acc, spans)
  }
}

fn drop_one_eol(spans: List(lexer.Spanned)) -> List(lexer.Spanned) {
  case spans {
    [lexer.Spanned(william.EndOfLine(_), _), ..rest] -> rest
    _ -> spans
  }
}

// Collect dot-separated key segments, skipping interior whitespace. Returns the
// segments and the remaining spans, positioned at the first token that is not
// part of the key (the caller validates that terminator).
fn collect_segments(
  spans: List(lexer.Spanned),
  expect_segment: Bool,
  acc: List(ast.KeySegment),
  version: Version,
) -> Result(#(List(ast.KeySegment), List(lexer.Spanned)), ParseError) {
  let #(_ws, spans) = take_whitespace(spans, "")
  case spans {
    [lexer.Spanned(william.BareKey(name), _), ..rest] if expect_segment ->
      collect_segments(rest, False, [ast.BareKeySegment(name), ..acc], version)

    [lexer.Spanned(william.String(delimiter, value), offset), ..rest]
      if expect_segment
    ->
      case key_segment_from_string(delimiter, value, version) {
        Ok(segment) -> collect_segments(rest, False, [segment, ..acc], version)
        Error(Nil) ->
          Error(Unexpected(
            token_src(william.String(delimiter, value)),
            ExpectedKey,
            offset,
          ))
      }

    [lexer.Spanned(william.Dot, _), ..rest] if !expect_segment ->
      collect_segments(rest, True, acc, version)

    _ ->
      case expect_segment {
        True ->
          case spans {
            [lexer.Spanned(token, offset), ..] ->
              Error(Unexpected(token_src(token), ExpectedKey, offset))
            [] -> Error(Unexpected("", ExpectedKey, 0))
          }
        False -> Ok(#(list.reverse(acc), spans))
      }
  }
}

fn key_segment_from_string(
  delimiter: william.StringDelimiter,
  value: String,
  version: Version,
) -> Result(ast.KeySegment, Nil) {
  case delimiter {
    william.BasicString ->
      case basic_string_content_is_valid(value, version) {
        True ->
          Ok(ast.QuotedKeySegment(basic_key_value(value), "\"" <> value <> "\""))
        False -> Error(Nil)
      }
    william.LiteralString ->
      Ok(ast.QuotedKeySegment(value, "'" <> value <> "'"))
    // Multi-line strings are not valid keys.
    william.MultilineBasicString | william.MultilineLiteralString -> Error(Nil)
  }
}

fn parse_key_value_tokens(
  spans: List(lexer.Spanned),
  key_offset: Int,
  state: AssemblyState,
  entries: List(ast.Entry),
  version: Version,
) -> Result(ast.Table, ParseError) {
  use #(segments, after_key) <- result.try(collect_segments(
    spans,
    True,
    [],
    version,
  ))
  case after_key {
    [lexer.Spanned(william.Equal, equal_offset), ..after_equal] -> {
      let key = ast.Key(segments)
      use #(value, trailing, rest) <- result.try(parse_value_tokens(
        after_equal,
        equal_offset,
        version,
      ))
      let entry =
        ast.KeyValue(
          leading: ast.Trivia(""),
          key: key,
          value: value,
          trailing: ast.Trivia(trailing <> "\n"),
        )
      use next_state <- result.try(apply_key_value_state(state, key, key_offset))
      assemble_loop(rest, next_state, [entry, ..entries], version)
    }
    [lexer.Spanned(token, offset), ..] ->
      Error(Unexpected(token_src(token), ExpectedSyntax, offset))
    [] -> Error(Unexpected("", ExpectedSyntax, key_offset))
  }
}

// Determine the value's token span, reconstruct its exact source text, decode it
// through the shared value parser, then gather trailing trivia up to the line
// ending. Returns the value, the trailing trivia text (without the newline), and
// the spans following the consumed line.
fn parse_value_tokens(
  spans: List(lexer.Spanned),
  equal_offset: Int,
  version: Version,
) -> Result(#(ast.Value, String, List(lexer.Spanned)), ParseError) {
  let #(_ws, spans) = take_whitespace(spans, "")
  case spans {
    [lexer.Spanned(william.OpenBracket, offset), ..] -> {
      let #(span, rest) = balanced_span(spans, 0, [])
      finish_value(span, offset, rest, version)
    }
    [lexer.Spanned(william.OpenBrace, offset), ..] -> {
      let #(span, rest) = balanced_span(spans, 0, [])
      finish_value(span, offset, rest, version)
    }
    // No value before the line ends: report the missing value with the offset
    // of whatever follows the `=`.
    [lexer.Spanned(william.EndOfLine(_), offset), ..]
    | [lexer.Spanned(william.Comment(_), offset), ..] -> {
      use value <- result.map(parse_value("", offset, version))
      #(value, "", spans)
    }
    [] -> {
      use value <- result.map(parse_value("", equal_offset + 1, version))
      #(value, "", [])
    }
    [lexer.Spanned(token, offset), ..rest] -> {
      use value <- result.try(parse_value(token_src(token), offset, version))
      use #(trailing, after) <- result.map(scan_trailing(rest, ""))
      #(value, trailing, after)
    }
  }
}

fn finish_value(
  span: List(lexer.Spanned),
  offset: Int,
  rest: List(lexer.Spanned),
  version: Version,
) -> Result(#(ast.Value, String, List(lexer.Spanned)), ParseError) {
  let source = spans_source(span)
  use value <- result.try(parse_value(source, offset, version))
  use #(trailing, after) <- result.map(scan_trailing(rest, ""))
  #(value, trailing, after)
}

fn spans_source(spans: List(lexer.Spanned)) -> String {
  spans
  |> list.map(fn(span) {
    let lexer.Spanned(token, _) = span
    token
  })
  |> william.to_source
}

// Consume tokens until a value construct (array or inline table) returns to the
// top level, tracking bracket and brace nesting. If the stream ends while still
// nested, the whole remainder is returned so `parse_value` rejects it.
fn balanced_span(
  spans: List(lexer.Spanned),
  depth: Int,
  acc: List(lexer.Spanned),
) -> #(List(lexer.Spanned), List(lexer.Spanned)) {
  case spans {
    [] -> #(list.reverse(acc), [])
    [span, ..rest] -> {
      let lexer.Spanned(token, _) = span
      let next_depth = case token {
        william.OpenBracket | william.OpenBrace -> depth + 1
        william.CloseBracket | william.CloseBrace -> depth - 1
        _ -> depth
      }
      let acc = [span, ..acc]
      case next_depth == 0 {
        True -> #(list.reverse(acc), rest)
        False -> balanced_span(rest, next_depth, acc)
      }
    }
  }
}

// After a value, only whitespace and an optional comment may precede the line
// ending. Returns the trailing trivia text (without the newline) and the spans
// following the consumed line ending.
fn scan_trailing(
  spans: List(lexer.Spanned),
  acc: String,
) -> Result(#(String, List(lexer.Spanned)), ParseError) {
  case spans {
    [] -> Ok(#(acc, []))
    [lexer.Spanned(william.Whitespace(text), _), ..rest] ->
      scan_trailing(rest, acc <> text)
    [lexer.Spanned(william.Comment(text), _), ..rest] ->
      scan_trailing(rest, acc <> text)
    [lexer.Spanned(william.EndOfLine(_), _), ..rest] -> Ok(#(acc, rest))
    [lexer.Spanned(token, offset), ..] ->
      Error(Unexpected(token_src(token), ExpectedSyntax, offset))
  }
}

fn parse_header_tokens(
  spans: List(lexer.Spanned),
  kind: ast.HeaderKind,
  open_offset: Int,
  state: AssemblyState,
  entries: List(ast.Entry),
  version: Version,
) -> Result(ast.Table, ParseError) {
  use #(segments, after_key) <- result.try(collect_segments(
    spans,
    True,
    [],
    version,
  ))
  let closer = case kind {
    ast.StandardTable -> after_key_is_close_table(after_key)
    ast.ArrayOfTablesHeader -> after_key_is_close_array_table(after_key)
  }
  case closer {
    Ok(after_close) -> {
      use rest <- result.try(scan_header_trailing(after_close, open_offset))
      let header = ast.Header(ast.Key(segments), kind, ast.Trivia(""))
      let entry = ast.TableHeader(header)
      use next_state <- result.try(apply_header_state(
        state,
        header,
        open_offset,
      ))
      assemble_loop(rest, next_state, [entry, ..entries], version)
    }
    Error(Nil) -> Error(Unexpected("", ExpectedTableHeader, open_offset))
  }
}

fn after_key_is_close_table(
  spans: List(lexer.Spanned),
) -> Result(List(lexer.Spanned), Nil) {
  case spans {
    [lexer.Spanned(william.CloseTable, _), ..rest] -> Ok(rest)
    _ -> Error(Nil)
  }
}

fn after_key_is_close_array_table(
  spans: List(lexer.Spanned),
) -> Result(List(lexer.Spanned), Nil) {
  case spans {
    [lexer.Spanned(william.CloseArrayTable, _), ..rest] -> Ok(rest)
    _ -> Error(Nil)
  }
}

fn scan_header_trailing(
  spans: List(lexer.Spanned),
  open_offset: Int,
) -> Result(List(lexer.Spanned), ParseError) {
  case spans {
    [] -> Ok([])
    [lexer.Spanned(william.Whitespace(_), _), ..rest] ->
      scan_header_trailing(rest, open_offset)
    [lexer.Spanned(william.Comment(_), _), ..rest] ->
      scan_header_trailing(rest, open_offset)
    [lexer.Spanned(william.EndOfLine(_), _), ..rest] -> Ok(rest)
    [lexer.Spanned(_, _), ..] ->
      Error(Unexpected("", ExpectedTableHeader, open_offset))
  }
}

fn apply_key_value_state(
  state: AssemblyState,
  key: ast.Key,
  key_offset: Int,
) -> Result(AssemblyState, ParseError) {
  let full_key = list.append(state.active_table, key_utils.to_strings(key))
  case
    key_path_conflicts(state.seen, full_key)
    || dotted_key_extends_defined_table(
      state.explicit_tables,
      state.array_tables,
      state.active_table,
      full_key,
    )
  {
    True -> Error(KeyAlreadyInUse(full_key, key_offset))
    False ->
      Ok(
        AssemblyState(
          ..state,
          seen: [full_key, ..state.seen],
          dotted_tables: add_dotted_table_paths(
            state.dotted_tables,
            state.active_table,
            full_key,
          ),
        ),
      )
  }
}

fn apply_header_state(
  state: AssemblyState,
  header: ast.Header,
  open_offset: Int,
) -> Result(AssemblyState, ParseError) {
  let table_key = header_key(header)
  case
    key_path_conflicts_for_table_header(state.seen, table_key)
    || list.contains(state.dotted_tables, table_key)
    || standard_table_already_defined(header, state.explicit_tables, table_key)
    || table_kind_already_defined(
      header,
      state.explicit_tables,
      state.array_tables,
      table_key,
    )
    || array_table_parent_already_implied(
      header,
      state.array_tables,
      state.array_table_parents,
      table_key,
    )
  {
    True -> Error(KeyAlreadyInUse(table_key, open_offset))
    False -> {
      let is_array = case header {
        ast.Header(kind: ast.ArrayOfTablesHeader, ..) -> True
        _ -> False
      }
      let next_seen = case is_array {
        True -> remove_keys_under_table(state.seen, table_key)
        False -> state.seen
      }
      let next_explicit = case header {
        ast.Header(kind: ast.StandardTable, ..) -> [
          table_key,
          ..state.explicit_tables
        ]
        ast.Header(kind: ast.ArrayOfTablesHeader, ..) ->
          remove_keys_under_table(state.explicit_tables, table_key)
      }
      let next_dotted = case is_array {
        True -> remove_keys_under_table(state.dotted_tables, table_key)
        False -> state.dotted_tables
      }
      let next_arrays = case is_array {
        True -> [table_key, ..state.array_tables]
        False -> state.array_tables
      }
      let next_parents = case is_array {
        True ->
          add_paths(
            dotted_table_paths([], table_key),
            state.array_table_parents,
          )
        False -> state.array_table_parents
      }
      Ok(AssemblyState(
        active_table: table_key,
        seen: next_seen,
        explicit_tables: next_explicit,
        array_tables: next_arrays,
        array_table_parents: next_parents,
        dotted_tables: next_dotted,
      ))
    }
  }
}

fn first_disallowed_control_offset(input: String) -> Result(Int, Nil) {
  first_disallowed_control_offset_loop(string.to_graphemes(input), 0)
}

fn first_disallowed_control_offset_loop(
  chars: List(String),
  offset: Int,
) -> Result(Int, Nil) {
  case chars {
    [] -> Error(Nil)
    [char, ..rest] ->
      case char_is_disallowed_control(char) {
        True -> Ok(offset)
        False ->
          first_disallowed_control_offset_loop(
            rest,
            offset + string.byte_size(char),
          )
      }
  }
}

fn parse_key(text: String, version: Version) -> Result(ast.Key, Nil) {
  split_key_segments_text(text)
  |> list.try_map(fn(segment) { parse_key_segment(segment, version) })
  |> result.map(ast.Key)
}

fn split_key_value(line: String) -> Result(#(String, String), Nil) {
  split_key_value_loop(string.to_graphemes(line), "", "", False, False, False)
}

fn split_key_segments_text(text: String) -> List(String) {
  split_key_segments_loop(string.to_graphemes(text), "", [], False, False)
}

fn split_key_segments_loop(
  chars: List(String),
  current: String,
  segments: List(String),
  in_basic: Bool,
  in_literal: Bool,
) -> List(String) {
  case chars {
    [] -> list.reverse([current, ..segments])
    ["\\", escaped, ..rest] ->
      case in_basic {
        True ->
          split_key_segments_loop(
            rest,
            current <> "\\" <> escaped,
            segments,
            in_basic,
            in_literal,
          )
        False ->
          split_key_segments_loop(
            rest,
            current <> "\\",
            segments,
            in_basic,
            in_literal,
          )
      }
    [".", ..rest] ->
      case in_basic || in_literal {
        True ->
          split_key_segments_loop(
            rest,
            current <> ".",
            segments,
            in_basic,
            in_literal,
          )
        False ->
          split_key_segments_loop(
            rest,
            "",
            [current, ..segments],
            in_basic,
            in_literal,
          )
      }
    ["\"", ..rest] ->
      case in_literal {
        True ->
          split_key_segments_loop(
            rest,
            current <> "\"",
            segments,
            in_basic,
            in_literal,
          )
        False ->
          split_key_segments_loop(
            rest,
            current <> "\"",
            segments,
            !in_basic,
            in_literal,
          )
      }
    ["'", ..rest] ->
      case in_basic {
        True ->
          split_key_segments_loop(
            rest,
            current <> "'",
            segments,
            in_basic,
            in_literal,
          )
        False ->
          split_key_segments_loop(
            rest,
            current <> "'",
            segments,
            in_basic,
            !in_literal,
          )
      }
    [char, ..rest] ->
      split_key_segments_loop(
        rest,
        current <> char,
        segments,
        in_basic,
        in_literal,
      )
  }
}

fn split_key_value_loop(
  chars: List(String),
  key: String,
  value: String,
  in_basic: Bool,
  in_literal: Bool,
  found: Bool,
) -> Result(#(String, String), Nil) {
  case chars {
    [] ->
      case found {
        True -> Ok(#(key, value))
        False -> Error(Nil)
      }
    [char, ..rest] ->
      case char, found, in_basic, in_literal {
        "\\", _, True, False -> {
          case rest {
            [] ->
              split_key_value_loop(
                rest,
                key,
                value,
                in_basic,
                in_literal,
                found,
              )
            [escaped, ..after_escape] ->
              split_key_value_loop(
                after_escape,
                key <> bool_pick(!found, "\\" <> escaped, ""),
                value <> bool_pick(found, "\\" <> escaped, ""),
                in_basic,
                in_literal,
                found,
              )
          }
        }
        "=", False, False, False ->
          split_key_value_loop(rest, key, value, in_basic, in_literal, True)
        "\"", _, _, False ->
          split_key_value_loop(
            rest,
            key <> bool_pick(!found, "\"", ""),
            value <> bool_pick(found, "\"", ""),
            !in_basic,
            in_literal,
            found,
          )
        "'", _, False, _ ->
          split_key_value_loop(
            rest,
            key <> bool_pick(!found, "'", ""),
            value <> bool_pick(found, "'", ""),
            in_basic,
            !in_literal,
            found,
          )
        _, False, _, _ ->
          split_key_value_loop(
            rest,
            key <> char,
            value,
            in_basic,
            in_literal,
            found,
          )
        _, True, _, _ ->
          split_key_value_loop(
            rest,
            key,
            value <> char,
            in_basic,
            in_literal,
            found,
          )
      }
  }
}

fn bool_pick(condition: Bool, yes: String, no: String) -> String {
  use <- bool.guard(when: condition, return: yes)
  no
}

fn parse_key_segment(
  segment: String,
  version: Version,
) -> Result(ast.KeySegment, Nil) {
  let trimmed = string.trim(segment)
  use <- bool.guard(when: trimmed == "", return: Error(Nil))
  use <- bool.guard(
    when: string_is_multiline_delimited(trimmed),
    return: Error(Nil),
  )
  case
    string.starts_with(trimmed, "\"")
    && string.ends_with(trimmed, "\"")
    && string.length(trimmed) > 1
  {
    True -> {
      let inner =
        trimmed
        |> string.drop_start(1)
        |> string.drop_end(1)
      case basic_string_content_is_valid(inner, version) {
        True -> Ok(ast.QuotedKeySegment(basic_key_value(inner), trimmed))
        False -> Error(Nil)
      }
    }
    False ->
      case
        string.starts_with(trimmed, "'")
        && string.ends_with(trimmed, "'")
        && string.length(trimmed) > 1
      {
        True ->
          Ok(ast.QuotedKeySegment(
            trimmed
              |> string.drop_start(1)
              |> string.drop_end(1),
            trimmed,
          ))
        False ->
          case
            string.starts_with(trimmed, "\"")
            || string.ends_with(trimmed, "\"")
            || string.starts_with(trimmed, "'")
            || string.ends_with(trimmed, "'")
            || !key_utils.is_bare_key(trimmed)
          {
            True -> Error(Nil)
            False -> Ok(ast.BareKeySegment(trimmed))
          }
      }
  }
}

fn header_key(header: ast.Header) -> List(String) {
  let ast.Header(key: key, kind: _, trivia: _) = header
  key_utils.to_strings(key)
}

fn remove_keys_under_table(
  seen: List(List(String)),
  table_key: List(String),
) -> List(List(String)) {
  list.filter(seen, fn(key) { !key_utils.starts_with(key, table_key) })
}

fn key_path_conflicts(seen: List(List(String)), key: List(String)) -> Bool {
  case seen {
    [] -> False
    [existing, ..rest] ->
      key_utils.starts_with(existing, key)
      || key_utils.starts_with(key, existing)
      || key_path_conflicts(rest, key)
  }
}

fn key_path_conflicts_for_table_header(
  seen: List(List(String)),
  key: List(String),
) -> Bool {
  case seen {
    [] -> False
    [existing, ..rest] ->
      existing == key
      || key_utils.starts_with(key, existing)
      || key_path_conflicts_for_table_header(rest, key)
  }
}

fn standard_table_already_defined(
  header: ast.Header,
  explicit_tables: List(List(String)),
  key: List(String),
) -> Bool {
  case header {
    ast.Header(kind: ast.StandardTable, ..) ->
      list.contains(explicit_tables, key)
    _ -> False
  }
}

fn table_kind_already_defined(
  header: ast.Header,
  explicit_tables: List(List(String)),
  array_tables: List(List(String)),
  key: List(String),
) -> Bool {
  case header {
    ast.Header(kind: ast.StandardTable, ..) -> list.contains(array_tables, key)
    ast.Header(kind: ast.ArrayOfTablesHeader, ..) ->
      list.contains(explicit_tables, key)
  }
}

fn array_table_parent_already_implied(
  header: ast.Header,
  array_tables: List(List(String)),
  array_table_parents: List(List(String)),
  key: List(String),
) -> Bool {
  case header {
    ast.Header(kind: ast.ArrayOfTablesHeader, ..) ->
      list.contains(array_table_parents, key)
      && !list.contains(array_tables, key)
    _ -> False
  }
}

fn dotted_key_extends_defined_table(
  explicit_tables: List(List(String)),
  array_tables: List(List(String)),
  active_table: List(String),
  key: List(String),
) -> Bool {
  dotted_key_extends_table(explicit_tables, active_table, key)
  || dotted_key_extends_table(array_tables, active_table, key)
}

fn dotted_key_extends_table(
  table_paths: List(List(String)),
  active_table: List(String),
  key: List(String),
) -> Bool {
  case table_paths {
    [] -> False
    [table, ..rest] ->
      {
        key_utils.starts_with(key, table)
        && !key_utils.starts_with(active_table, table)
      }
      || dotted_key_extends_table(rest, active_table, key)
  }
}

fn add_dotted_table_paths(
  existing: List(List(String)),
  active_table: List(String),
  key: List(String),
) -> List(List(String)) {
  add_paths(dotted_table_paths(active_table, key), existing)
}

fn dotted_table_paths(
  active_table: List(String),
  key: List(String),
) -> List(List(String)) {
  dotted_table_paths_loop(key, [], active_table, [])
}

fn dotted_table_paths_loop(
  key: List(String),
  prefix: List(String),
  active_table: List(String),
  acc: List(List(String)),
) -> List(List(String)) {
  case key {
    [] -> acc
    [_leaf] -> acc
    [segment, ..rest] -> {
      let next_prefix = list.append(prefix, [segment])
      let next_acc = case list.length(next_prefix) > list.length(active_table) {
        True -> [next_prefix, ..acc]
        False -> acc
      }
      dotted_table_paths_loop(rest, next_prefix, active_table, next_acc)
    }
  }
}

fn add_paths(
  paths: List(List(String)),
  existing: List(List(String)),
) -> List(List(String)) {
  case paths {
    [] -> existing
    [path, ..rest] ->
      case list.contains(existing, path) {
        True -> add_paths(rest, existing)
        False -> add_paths(rest, [path, ..existing])
      }
  }
}

fn parse_value(
  text: String,
  offset: Int,
  version: Version,
) -> Result(ast.Value, ParseError) {
  case string.starts_with(text, "[") {
    True -> parse_array_value(text, offset, version)
    False ->
      case string.starts_with(text, "{") {
        True -> parse_inline_table_value(text, offset, version)
        False -> parse_scalar_value(text, offset, version)
      }
  }
}

fn parse_scalar_value(
  text: String,
  offset: Int,
  version: Version,
) -> Result(ast.Value, ParseError) {
  let parsers = [
    fn(text) { parse_multiline_basic_string(text, version) },
    parse_multiline_literal_string,
    fn(text) { parse_basic_string(text, version) },
    parse_literal_string,
    parse_bool_value,
    parse_float_value,
    fn(text) { parse_date_like_value(text, version) },
  ]
  case list.find_map(parsers, fn(parse) { parse(text) }) {
    Ok(value) -> Ok(value)
    Error(Nil) -> parse_int_value(text, offset)
  }
}

fn split_top_level_commas(text: String) -> List(#(String, Int)) {
  split_top_level_commas_loop(
    string.to_graphemes(text),
    0,
    StripNormal,
    "",
    0,
    [],
  )
}

fn split_top_level_commas_loop(
  chars: List(String),
  depth: Int,
  state: StripState,
  current: String,
  current_start: Int,
  parts: List(#(String, Int)),
) -> List(#(String, Int)) {
  case state, chars {
    _, [] ->
      list.reverse([
        #(string.trim(current), current_start + trim_start_byte_offset(current)),
        ..parts
      ])

    StripNormal, [",", ..rest] if depth == 0 ->
      split_top_level_commas_loop(
        rest,
        depth,
        StripNormal,
        "",
        current_start + string.byte_size(current) + 1,
        [
          #(
            string.trim(current),
            current_start + trim_start_byte_offset(current),
          ),
          ..parts
        ],
      )
    StripNormal, ["[", ..rest] ->
      split_top_level_commas_loop(
        rest,
        depth + 1,
        StripNormal,
        current <> "[",
        current_start,
        parts,
      )
    StripNormal, ["{", ..rest] ->
      split_top_level_commas_loop(
        rest,
        depth + 1,
        StripNormal,
        current <> "{",
        current_start,
        parts,
      )
    StripNormal, ["]", ..rest] ->
      split_top_level_commas_loop(
        rest,
        depth - 1,
        StripNormal,
        current <> "]",
        current_start,
        parts,
      )
    StripNormal, ["}", ..rest] ->
      split_top_level_commas_loop(
        rest,
        depth - 1,
        StripNormal,
        current <> "}",
        current_start,
        parts,
      )

    _, _ -> {
      let StripStep(rest, next_state, consumed) =
        strip_state_step(chars, state, False)
      split_top_level_commas_loop(
        rest,
        depth,
        next_state,
        current <> consumed,
        current_start,
        parts,
      )
    }
  }
}

fn trim_start_byte_offset(text: String) -> Int {
  string.byte_size(text) - string.byte_size(string.trim_start(text))
}

fn parse_array_value(
  text: String,
  offset: Int,
  version: Version,
) -> Result(ast.Value, ParseError) {
  let is_array = string.starts_with(text, "[") && string.ends_with(text, "]")
  use <- bool.guard(
    when: !is_array,
    return: Error(Unexpected(text, ExpectedSyntax, offset)),
  )
  let body =
    text
    |> string.drop_start(1)
    |> string.drop_end(1)
  let clean_body = strip_inline_comments_by_line(body)

  case string.trim(clean_body) {
    "" -> Ok(ast.Array([], text))
    _ ->
      case
        parse_array_items(
          split_top_level_commas(clean_body),
          offset + 1,
          version,
        )
      {
        Ok(items) -> Ok(ast.Array(items, text))
        Error(error) -> Error(error)
      }
  }
}

fn parse_array_items(
  parts: List(#(String, Int)),
  body_offset: Int,
  version: Version,
) -> Result(List(ast.ArrayItem), ParseError) {
  case parts {
    [] -> Ok([])
    [#(part, part_offset), ..rest] ->
      case string.trim(strip_inline_comments_by_line(part)) {
        "" ->
          case rest {
            [] -> Ok([])
            _ -> Error(Unexpected("", ExpectedValue, body_offset + part_offset))
          }
        clean_part ->
          case parse_value(clean_part, body_offset + part_offset, version) {
            Ok(value) ->
              case parse_array_items(rest, body_offset, version) {
                Ok(items) ->
                  Ok([
                    ast.ArrayItem(ast.Trivia(""), value, ast.Trivia("")),
                    ..items
                  ])
                Error(error) -> Error(error)
              }
            Error(error) -> Error(error)
          }
      }
  }
}

fn parse_inline_table_value(
  text: String,
  offset: Int,
  version: Version,
) -> Result(ast.Value, ParseError) {
  let is_inline_table =
    string.starts_with(text, "{") && string.ends_with(text, "}")
  use <- bool.guard(
    when: !is_inline_table,
    return: Error(Unexpected(text, ExpectedSyntax, offset)),
  )
  let body =
    text
    |> string.drop_start(1)
    |> string.drop_end(1)
  let clean_body = strip_inline_comments_by_line(body)

  use <- bool.guard(
    when: !inline_table_newlines_are_valid(body, version),
    return: Error(Unexpected(text, ExpectedSyntax, offset)),
  )
  case string.trim(clean_body) {
    "" -> Ok(ast.InlineTable([], text))
    _ ->
      case
        parse_inline_entries(
          split_top_level_commas(clean_body),
          offset + 1,
          [],
          version,
        )
      {
        Ok(entries) -> Ok(ast.InlineTable(entries, text))
        Error(error) -> Error(error)
      }
  }
}

fn inline_table_newlines_are_valid(text: String, version: Version) -> Bool {
  case version {
    Toml11 -> True
    Toml10 ->
      inline_table_newlines_are_valid_loop(
        string.to_graphemes(text),
        0,
        StripNormal,
      )
  }
}

fn inline_table_newlines_are_valid_loop(
  chars: List(String),
  depth: Int,
  state: StripState,
) -> Bool {
  case state, chars {
    _, [] -> True

    StripNormal, ["\n", ..rest] ->
      case depth > 0 {
        True -> inline_table_newlines_are_valid_loop(rest, depth, StripNormal)
        False -> False
      }
    StripNormal, ["[", ..rest] ->
      inline_table_newlines_are_valid_loop(rest, depth + 1, StripNormal)
    StripNormal, ["{", ..rest] ->
      inline_table_newlines_are_valid_loop(rest, depth + 1, StripNormal)
    StripNormal, ["]", ..rest] ->
      inline_table_newlines_are_valid_loop(rest, depth - 1, StripNormal)
    StripNormal, ["}", ..rest] ->
      inline_table_newlines_are_valid_loop(rest, depth - 1, StripNormal)

    _, _ -> {
      let StripStep(rest, next_state, _) = strip_state_step(chars, state, False)
      inline_table_newlines_are_valid_loop(rest, depth, next_state)
    }
  }
}

fn parse_inline_entries(
  parts: List(#(String, Int)),
  body_offset: Int,
  seen: List(List(String)),
  version: Version,
) -> Result(List(ast.InlineTableEntry), ParseError) {
  case parts {
    [] -> Ok([])
    [#(part, part_offset), ..rest] -> {
      let entry_offset = body_offset + part_offset
      // A whitespace-only segment is normally invalid. In TOML 1.1 a single
      // trailing comma before `}` produces an empty final segment, which is
      // permitted; in 1.0 it remains an error. Comments were already stripped
      // from the body before splitting, so a plain trim identifies it.
      case string.trim(part) {
        "" ->
          case version, rest {
            Toml11, [] -> Ok([])
            _, _ -> Error(Unexpected("", ExpectedSyntax, entry_offset))
          }
        _ -> {
          use #(raw_key, raw_value) <- result.try(result.replace_error(
            split_key_value(part),
            Unexpected(part, ExpectedSyntax, entry_offset),
          ))
          use key <- result.try(result.replace_error(
            parse_key(string.trim(raw_key), version),
            Unexpected(part, ExpectedKey, entry_offset),
          ))
          let key_path = key_utils.to_strings(key)
          use <- bool.guard(
            when: key_path_conflicts(seen, key_path),
            return: Error(Unexpected(part, ExpectedSyntax, entry_offset)),
          )
          use value <- result.try(parse_value(
            string.trim(strip_inline_comments_by_line(raw_value)),
            entry_offset
              + string.byte_size(raw_key)
              + 1
              + trim_start_byte_offset(raw_value),
            version,
          ))
          use entries <- result.try(parse_inline_entries(
            rest,
            body_offset,
            [key_path, ..seen],
            version,
          ))
          Ok([
            ast.InlineTableEntry(ast.Trivia(""), key, value, ast.Trivia("")),
            ..entries
          ])
        }
      }
    }
  }
}

// Strips `#` comments from an inline-table or array body while preserving every
// string literal verbatim. A single pass tracks single-line basic (`"`) and
// literal (`'`) strings as well as multi-line basic (`"""`) and literal (`'''`)
// strings, so comments that follow a closing multi-line delimiter on a later
// physical line are removed correctly. Newlines are preserved so byte offsets in
// downstream errors stay accurate.
fn strip_inline_comments_by_line(text: String) -> String {
  strip_inline_comments_loop(string.to_graphemes(text), StripNormal, "")
}

type StripState {
  StripNormal
  StripBasic
  StripLiteral
  StripMultiBasic
  StripMultiLiteral
}

type StripStep {
  StripStep(rest: List(String), state: StripState, consumed: String)
}

fn strip_state_step(
  chars: List(String),
  state: StripState,
  close_single_line_on_newline: Bool,
) -> StripStep {
  case state, chars {
    _, [] -> StripStep([], state, "")

    StripNormal, ["\"", "\"", "\"", ..rest] ->
      StripStep(rest, StripMultiBasic, "\"\"\"")
    StripNormal, ["'", "'", "'", ..rest] ->
      StripStep(rest, StripMultiLiteral, "'''")
    StripNormal, ["\"", ..rest] -> StripStep(rest, StripBasic, "\"")
    StripNormal, ["'", ..rest] -> StripStep(rest, StripLiteral, "'")
    StripNormal, [char, ..rest] -> StripStep(rest, StripNormal, char)

    StripBasic, ["\\", escaped, ..rest] ->
      StripStep(rest, StripBasic, "\\" <> escaped)
    StripBasic, ["\"", ..rest] -> StripStep(rest, StripNormal, "\"")
    StripBasic, ["\n", ..rest] if close_single_line_on_newline ->
      StripStep(rest, StripNormal, "\n")
    StripBasic, [char, ..rest] -> StripStep(rest, StripBasic, char)

    StripLiteral, ["'", ..rest] -> StripStep(rest, StripNormal, "'")
    StripLiteral, ["\n", ..rest] if close_single_line_on_newline ->
      StripStep(rest, StripNormal, "\n")
    StripLiteral, [char, ..rest] -> StripStep(rest, StripLiteral, char)

    StripMultiBasic, ["\\", escaped, ..rest] ->
      StripStep(rest, StripMultiBasic, "\\" <> escaped)
    StripMultiBasic, ["\"", "\"", "\"", ..rest] ->
      StripStep(rest, StripNormal, "\"\"\"")
    StripMultiBasic, [char, ..rest] -> StripStep(rest, StripMultiBasic, char)

    StripMultiLiteral, ["'", "'", "'", ..rest] ->
      StripStep(rest, StripNormal, "'''")
    StripMultiLiteral, [char, ..rest] ->
      StripStep(rest, StripMultiLiteral, char)
  }
}

fn strip_inline_comments_loop(
  chars: List(String),
  state: StripState,
  acc: String,
) -> String {
  case state, chars {
    _, [] -> acc

    StripNormal, ["#", ..rest] ->
      strip_inline_comments_loop(
        list.drop_while(rest, fn(char) { char != "\n" }),
        StripNormal,
        acc,
      )
    _, _ -> {
      let StripStep(rest, next_state, consumed) =
        strip_state_step(chars, state, True)
      strip_inline_comments_loop(rest, next_state, acc <> consumed)
    }
  }
}

fn parse_multiline_basic_string(
  text: String,
  version: Version,
) -> Result(ast.Value, Nil) {
  let is_delimited =
    string.starts_with(text, "\"\"\"") && string.ends_with(text, "\"\"\"")
  use <- bool.guard(when: !is_delimited, return: Error(Nil))
  let inner =
    text
    |> string.drop_start(3)
    |> string.drop_end(3)

  let content_valid =
    text != "\"\"\"" && multiline_basic_string_content_is_valid(inner, version)
  use <- bool.guard(when: !content_valid, return: Error(Nil))
  Ok(ast.String(inner, ast.MultiBasicString, text))
}

fn parse_multiline_literal_string(text: String) -> Result(ast.Value, Nil) {
  let is_delimited =
    string.starts_with(text, "'''") && string.ends_with(text, "'''")
  use <- bool.guard(when: !is_delimited, return: Error(Nil))
  let inner =
    text
    |> string.drop_start(3)
    |> string.drop_end(3)

  let content_valid =
    text != "'''" && multiline_literal_string_content_is_valid(inner)
  use <- bool.guard(when: !content_valid, return: Error(Nil))
  Ok(ast.String(inner, ast.MultiLiteralString, text))
}

fn parse_basic_string(
  text: String,
  version: Version,
) -> Result(ast.Value, Nil) {
  let is_delimited =
    string.starts_with(text, "\"") && string.ends_with(text, "\"")
  use <- bool.guard(when: !is_delimited, return: Error(Nil))
  let inner =
    text
    |> string.drop_start(1)
    |> string.drop_end(1)

  use <- bool.guard(
    when: !basic_string_content_is_valid(inner, version),
    return: Error(Nil),
  )
  Ok(ast.String(inner, ast.BasicString, text))
}

fn parse_literal_string(text: String) -> Result(ast.Value, Nil) {
  let is_delimited =
    string.starts_with(text, "'") && string.ends_with(text, "'")
  use <- bool.guard(when: !is_delimited, return: Error(Nil))
  let inner =
    text
    |> string.drop_start(1)
    |> string.drop_end(1)

  use <- bool.guard(
    when: !literal_string_content_is_valid(inner),
    return: Error(Nil),
  )
  Ok(ast.String(inner, ast.LiteralString, text))
}

fn literal_string_content_is_valid(text: String) -> Bool {
  literal_string_chars_are_valid(string.to_graphemes(text))
}

fn literal_string_chars_are_valid(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    ["'", ..] -> False
    ["\n", ..] -> False
    [char, ..rest] ->
      case char_is_disallowed_control(char) {
        True -> False
        False -> literal_string_chars_are_valid(rest)
      }
  }
}

fn string_is_multiline_delimited(text: String) -> Bool {
  { string.starts_with(text, "\"\"\"") && string.ends_with(text, "\"\"\"") }
  || { string.starts_with(text, "'''") && string.ends_with(text, "'''") }
}

fn multiline_basic_string_content_is_valid(
  text: String,
  version: Version,
) -> Bool {
  multiline_basic_string_chars_are_valid(string.to_graphemes(text), version)
}

fn multiline_basic_string_chars_are_valid(
  chars: List(String),
  version: Version,
) -> Bool {
  case chars {
    [] -> True
    ["\\"] -> False
    ["\\", ..rest] -> multiline_basic_escape_is_valid(rest, version)
    ["\"", "\"", "\"", ..] -> False
    [char, ..rest] ->
      case char_is_disallowed_control(char) {
        True -> False
        False -> multiline_basic_string_chars_are_valid(rest, version)
      }
  }
}

fn multiline_basic_escape_is_valid(
  chars: List(String),
  version: Version,
) -> Bool {
  let continue = fn(rest) {
    multiline_basic_string_chars_are_valid(rest, version)
  }
  case chars {
    [] -> False
    ["\n", ..rest] -> continue(rest)
    ["\r", "\n", ..rest] -> continue(rest)
    [" ", ..rest] -> multiline_basic_line_ending_escape_is_valid(rest, version)
    ["\t", ..rest] -> multiline_basic_line_ending_escape_is_valid(rest, version)
    ["e", ..rest] if version == Toml11 -> continue(rest)
    ["x", ..rest] if version == Toml11 ->
      hex_escape_is_valid_for(continue, rest)
    [escaped, ..rest] ->
      case escaped {
        "b" | "t" | "n" | "f" | "r" | "\"" | "\\" -> continue(rest)
        "u" -> unicode_escape_is_valid_for(continue, rest, 4)
        "U" -> unicode_escape_is_valid_for(continue, rest, 8)
        _ -> False
      }
  }
}

fn multiline_basic_line_ending_escape_is_valid(
  chars: List(String),
  version: Version,
) -> Bool {
  case chars {
    [] -> False
    [" ", ..rest] -> multiline_basic_line_ending_escape_is_valid(rest, version)
    ["\t", ..rest] -> multiline_basic_line_ending_escape_is_valid(rest, version)
    ["\n", ..rest] -> multiline_basic_string_chars_are_valid(rest, version)
    ["\r", "\n", ..rest] ->
      multiline_basic_string_chars_are_valid(rest, version)
    _ -> False
  }
}

fn multiline_literal_string_content_is_valid(text: String) -> Bool {
  multiline_literal_string_chars_are_valid(string.to_graphemes(text))
}

fn multiline_literal_string_chars_are_valid(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    ["'", "'", "'", ..] -> False
    [char, ..rest] ->
      case char_is_disallowed_control(char) {
        True -> False
        False -> multiline_literal_string_chars_are_valid(rest)
      }
  }
}

fn parse_bool_value(text: String) -> Result(ast.Value, Nil) {
  case text {
    "true" -> Ok(ast.Bool(True, text))
    "false" -> Ok(ast.Bool(False, text))
    _ -> Error(Nil)
  }
}

fn parse_float_value(text: String) -> Result(ast.Value, Nil) {
  let normalized = string.replace(text, each: "_", with: "")
  case
    float_repr_is_valid(text)
    && {
      string.contains(normalized, ".")
      || string.contains(normalized, "e")
      || string.contains(normalized, "E")
      || normalized == "inf"
      || normalized == "+inf"
      || normalized == "-inf"
      || normalized == "nan"
      || normalized == "+nan"
      || normalized == "-nan"
    }
  {
    True ->
      case parse_special_float_value(normalized, text) {
        Ok(value) -> Ok(value)
        Error(Nil) ->
          case parse_toml_float(normalized) {
            Ok(value) -> Ok(ast.Float(value, text))
            Error(_) -> Error(Nil)
          }
      }
    False -> Error(Nil)
  }
}

fn parse_special_float_value(
  normalized: String,
  source_text: String,
) -> Result(ast.Value, Nil) {
  case normalized {
    "inf" | "+inf" ->
      Ok(ast.SpecialFloat(ast.PositiveInfinity, source_text: source_text))
    "-inf" ->
      Ok(ast.SpecialFloat(ast.NegativeInfinity, source_text: source_text))
    "nan" | "+nan" | "-nan" ->
      Ok(ast.SpecialFloat(ast.NotANumber, source_text: source_text))
    _ -> Error(Nil)
  }
}

fn parse_toml_float(text: String) -> Result(Float, Nil) {
  case float.parse(text) {
    Ok(value) -> Ok(value)
    Error(Nil) -> parse_exponent_float(text)
  }
}

fn parse_exponent_float(text: String) -> Result(Float, Nil) {
  case string.split_once(text, "e") {
    Ok(parts) -> parse_exponent_float_parts(parts)
    Error(Nil) ->
      case string.split_once(text, "E") {
        Ok(parts) -> parse_exponent_float_parts(parts)
        Error(Nil) -> Error(Nil)
      }
  }
}

fn parse_exponent_float_parts(parts: #(String, String)) -> Result(Float, Nil) {
  let #(mantissa, exponent) = parts
  case parse_number_part_as_float(mantissa), parse_signed_exponent(exponent) {
    Ok(mantissa_value), Ok(exponent_value) ->
      case float.power(10.0, int.to_float(exponent_value)) {
        Ok(scale) -> Ok(mantissa_value *. scale)
        Error(Nil) -> Error(Nil)
      }
    _, _ -> Error(Nil)
  }
}

fn parse_number_part_as_float(text: String) -> Result(Float, Nil) {
  case float.parse(text) {
    Ok(value) -> Ok(value)
    Error(Nil) ->
      case int.parse(text) {
        Ok(value) -> Ok(int.to_float(value))
        Error(Nil) -> Error(Nil)
      }
  }
}

fn parse_signed_exponent(text: String) -> Result(Int, Nil) {
  let without_plus = case string.starts_with(text, "+") {
    True -> string.drop_start(text, 1)
    False -> text
  }
  int.parse(without_plus)
}

fn parse_date_like_value(
  text: String,
  version: Version,
) -> Result(ast.Value, Nil) {
  use <- bool.guard(
    when: datetime_repr_is_valid_versioned(text, version),
    return: Ok(ast.DateTime(text)),
  )
  use <- bool.guard(
    when: time_repr_is_valid_versioned(text, version),
    return: Ok(ast.Time(text)),
  )
  use <- bool.guard(when: date_repr_is_valid(text), return: Ok(ast.Date(text)))
  Error(Nil)
}

fn parse_int_value(text: String, offset: Int) -> Result(ast.Value, ParseError) {
  let normalized = string.replace(text, each: "_", with: "")
  case int_repr_is_valid(text) {
    True ->
      case int.parse(normalized) {
        Ok(value) -> Ok(ast.Int(value, text))
        Error(Nil) -> parse_based_int_value(normalized, text, offset)
      }
    False -> Error(Unexpected(text, ExpectedValue, offset))
  }
}

fn parse_based_int_value(
  normalized: String,
  source_text: String,
  offset: Int,
) -> Result(ast.Value, ParseError) {
  case string.starts_with(normalized, "0x") {
    True ->
      parse_based_int_digits(string.drop_start(normalized, 2), 16, 0)
      |> based_int_result(source_text, offset)
    False ->
      case string.starts_with(normalized, "0o") {
        True ->
          parse_based_int_digits(string.drop_start(normalized, 2), 8, 0)
          |> based_int_result(source_text, offset)
        False ->
          case string.starts_with(normalized, "0b") {
            True ->
              parse_based_int_digits(string.drop_start(normalized, 2), 2, 0)
              |> based_int_result(source_text, offset)
            False -> Error(Unexpected(source_text, ExpectedValue, offset))
          }
      }
  }
}

fn based_int_result(
  result: Result(Int, Nil),
  source_text: String,
  offset: Int,
) -> Result(ast.Value, ParseError) {
  case result {
    Ok(value) -> Ok(ast.Int(value, source_text))
    Error(Nil) -> Error(Unexpected(source_text, ExpectedValue, offset))
  }
}

fn parse_based_int_digits(
  text: String,
  base: Int,
  acc: Int,
) -> Result(Int, Nil) {
  parse_based_int_digits_loop(string.to_graphemes(text), base, acc)
}

fn parse_based_int_digits_loop(
  chars: List(String),
  base: Int,
  acc: Int,
) -> Result(Int, Nil) {
  case chars {
    [] -> Ok(acc)
    [char, ..rest] ->
      case based_digit_value(char) {
        Ok(value) ->
          case value < base {
            True -> parse_based_int_digits_loop(rest, base, acc * base + value)
            False -> Error(Nil)
          }
        Error(Nil) -> Error(Nil)
      }
  }
}

fn based_digit_value(char: String) -> Result(Int, Nil) {
  case char {
    "0" -> Ok(0)
    "1" -> Ok(1)
    "2" -> Ok(2)
    "3" -> Ok(3)
    "4" -> Ok(4)
    "5" -> Ok(5)
    "6" -> Ok(6)
    "7" -> Ok(7)
    "8" -> Ok(8)
    "9" -> Ok(9)
    "a" | "A" -> Ok(10)
    "b" | "B" -> Ok(11)
    "c" | "C" -> Ok(12)
    "d" | "D" -> Ok(13)
    "e" | "E" -> Ok(14)
    "f" | "F" -> Ok(15)
    _ -> Error(Nil)
  }
}

fn basic_string_content_is_valid(text: String, version: Version) -> Bool {
  basic_string_chars_are_valid(string.to_graphemes(text), version)
}

fn basic_string_chars_are_valid(chars: List(String), version: Version) -> Bool {
  case chars {
    [] -> True
    ["\\"] -> False
    ["\\", "e", ..rest] if version == Toml11 ->
      basic_string_chars_are_valid(rest, version)
    ["\\", "x", ..rest] if version == Toml11 ->
      hex_escape_is_valid_for(
        fn(remaining) { basic_string_chars_are_valid(remaining, version) },
        rest,
      )
    ["\\", escaped, ..rest] ->
      case escaped {
        "b" | "t" | "n" | "f" | "r" | "\"" | "\\" ->
          basic_string_chars_are_valid(rest, version)
        "u" -> unicode_escape_is_valid(rest, 4, version)
        "U" -> unicode_escape_is_valid(rest, 8, version)
        _ -> False
      }
    ["\n", ..] -> False
    ["\"", ..] -> False
    [char, ..rest] ->
      case char_is_disallowed_control(char) {
        True -> False
        False -> basic_string_chars_are_valid(rest, version)
      }
  }
}

// A `\xHH` escape (TOML 1.1) requires exactly two hex digits; the resulting
// value is at most 0xFF, which is always a valid scalar, so no further range
// check is needed.
fn hex_escape_is_valid_for(
  validate_remaining: fn(List(String)) -> Bool,
  chars: List(String),
) -> Bool {
  case chars {
    [high, low, ..rest] ->
      case is_hex_digit_string(high) && is_hex_digit_string(low) {
        True -> validate_remaining(rest)
        False -> False
      }
    _ -> False
  }
}

fn unicode_escape_is_valid(
  chars: List(String),
  count: Int,
  version: Version,
) -> Bool {
  unicode_escape_is_valid_for(
    fn(remaining) { basic_string_chars_are_valid(remaining, version) },
    chars,
    count,
  )
}

fn unicode_escape_is_valid_for(
  validate_remaining: fn(List(String)) -> Bool,
  chars: List(String),
  count: Int,
) -> Bool {
  let #(escape, remaining) = take_chars(chars, count, "")
  case
    string.length(escape) == count && unicode_escape_scalar_is_valid(escape)
  {
    True -> validate_remaining(remaining)
    False -> False
  }
}

fn unicode_escape_scalar_is_valid(escape: String) -> Bool {
  case hex_to_int(string.to_graphemes(escape), 0) {
    Ok(value) ->
      case string.utf_codepoint(value) {
        Ok(_) -> True
        Error(Nil) -> False
      }
    Error(Nil) -> False
  }
}

fn int_repr_is_valid(text: String) -> Bool {
  let has_sign = string.starts_with(text, "+") || string.starts_with(text, "-")
  let unsigned = drop_sign(text)
  case string.starts_with(unsigned, "0x") {
    True ->
      !has_sign
      && based_digits_are_valid(
        string.drop_start(unsigned, 2),
        is_hex_digit_string,
      )
    False ->
      case string.starts_with(unsigned, "0o") {
        True ->
          !has_sign
          && based_digits_are_valid(
            string.drop_start(unsigned, 2),
            is_oct_digit_string,
          )
        False ->
          case string.starts_with(unsigned, "0b") {
            True ->
              !has_sign
              && based_digits_are_valid(
                string.drop_start(unsigned, 2),
                is_bin_digit_string,
              )
            False -> decimal_digits_are_valid(unsigned)
          }
      }
  }
}

fn decimal_digits_are_valid(text: String) -> Bool {
  use <- bool.guard(
    when: !separated_digits_are_valid(string.to_graphemes(text), char_is_digit),
    return: False,
  )
  case string.replace(text, each: "_", with: "") {
    "" -> False
    digits -> {
      let has_leading_zero =
        string.length(digits) > 1 && string.starts_with(digits, "0")
      !has_leading_zero
    }
  }
}

fn based_digits_are_valid(
  text: String,
  is_valid_digit: fn(String) -> Bool,
) -> Bool {
  case string.replace(text, each: "_", with: "") {
    "" -> False
    _ -> separated_digits_are_valid(string.to_graphemes(text), is_valid_digit)
  }
}

fn separated_digits_are_valid(
  chars: List(String),
  is_valid_digit: fn(String) -> Bool,
) -> Bool {
  separated_digits_loop(chars, is_valid_digit, False, False)
}

fn separated_digits_loop(
  chars: List(String),
  is_valid_digit: fn(String) -> Bool,
  seen_digit: Bool,
  previous_was_underscore: Bool,
) -> Bool {
  case chars {
    [] -> seen_digit && !previous_was_underscore
    ["_", ..rest] ->
      case seen_digit && !previous_was_underscore {
        True -> separated_digits_loop(rest, is_valid_digit, seen_digit, True)
        False -> False
      }
    [char, ..rest] ->
      case is_valid_digit(char) {
        True -> separated_digits_loop(rest, is_valid_digit, True, False)
        False -> False
      }
  }
}

fn float_repr_is_valid(text: String) -> Bool {
  case text {
    "inf" | "+inf" | "-inf" | "nan" | "+nan" | "-nan" -> True
    _ -> {
      let unsigned = drop_sign(text)
      case string.split_once(unsigned, "e") {
        Ok(#(mantissa, exponent)) ->
          mantissa_repr_is_valid(mantissa) && exponent_repr_is_valid(exponent)
        Error(Nil) ->
          case string.split_once(unsigned, "E") {
            Ok(#(mantissa, exponent)) ->
              mantissa_repr_is_valid(mantissa)
              && exponent_repr_is_valid(exponent)
            Error(Nil) -> mantissa_repr_is_valid(unsigned)
          }
      }
    }
  }
}

fn mantissa_repr_is_valid(text: String) -> Bool {
  case string.split_once(text, ".") {
    Ok(#(whole, fraction)) ->
      decimal_digits_are_valid(whole)
      && separated_digits_are_valid(
        string.to_graphemes(fraction),
        char_is_digit,
      )
    Error(Nil) -> decimal_digits_are_valid(text)
  }
}

fn exponent_repr_is_valid(text: String) -> Bool {
  separated_digits_are_valid(
    string.to_graphemes(drop_sign(text)),
    char_is_digit,
  )
}

pub fn date_repr_is_valid(text: String) -> Bool {
  let has_date_shape =
    string.length(text) == 10
    && string.slice(text, 4, 1) == "-"
    && string.slice(text, 7, 1) == "-"
  use <- bool.guard(when: !has_date_shape, return: False)
  date_parts_are_valid(text)
}

// Split a datetime into its date and time-offset halves on any of the three
// permitted separators (`T`, `t`, or a space).
fn split_datetime(text: String) -> Result(#(String, String), Nil) {
  case string.split_once(text, "T") {
    Ok(parts) -> Ok(parts)
    Error(Nil) ->
      case string.split_once(text, "t") {
        Ok(parts) -> Ok(parts)
        Error(Nil) -> string.split_once(text, " ")
      }
  }
}

pub fn datetime_repr_is_valid(text: String) -> Bool {
  case split_datetime(text) {
    Ok(#(date, time_offset)) ->
      date_repr_is_valid(date) && time_offset_repr_is_valid(time_offset)
    Error(Nil) -> False
  }
}

fn time_offset_repr_is_valid(text: String) -> Bool {
  case string.ends_with(text, "Z") || string.ends_with(text, "z") {
    True -> time_repr_is_valid(string.drop_end(text, 1))
    False ->
      case find_offset_separator(string.to_graphemes(text), "") {
        Ok(#(time, offset)) ->
          time_repr_is_valid(time) && offset_repr_is_valid(offset)
        Error(Nil) -> time_repr_is_valid(text)
      }
  }
}

// Version-aware date-time / time validators. They reuse the strict 1.0 logic
// but additionally accept the second-less `HH:MM` time shape under TOML 1.1.
fn datetime_repr_is_valid_versioned(text: String, version: Version) -> Bool {
  case version {
    Toml10 -> datetime_repr_is_valid(text)
    Toml11 ->
      case split_datetime(text) {
        Ok(#(date, time_offset)) ->
          date_repr_is_valid(date)
          && time_offset_repr_is_valid_versioned(time_offset, version)
        Error(Nil) -> False
      }
  }
}

fn time_offset_repr_is_valid_versioned(text: String, version: Version) -> Bool {
  case string.ends_with(text, "Z") || string.ends_with(text, "z") {
    True -> time_repr_is_valid_versioned(string.drop_end(text, 1), version)
    False ->
      case find_offset_separator(string.to_graphemes(text), "") {
        Ok(#(time, offset)) ->
          time_repr_is_valid_versioned(time, version)
          && offset_repr_is_valid(offset)
        Error(Nil) -> time_repr_is_valid_versioned(text, version)
      }
  }
}

fn time_repr_is_valid_versioned(text: String, version: Version) -> Bool {
  case version {
    Toml10 -> time_repr_is_valid(text)
    Toml11 -> time_repr_is_valid(text) || hour_minute_repr_is_valid(text)
  }
}

// The second-less `HH:MM` time shape introduced in TOML 1.1. The fixed length of
// 5 guarantees there is no trailing seconds or fractional component.
fn hour_minute_repr_is_valid(text: String) -> Bool {
  string.length(text) == 5
  && string.slice(text, 2, 1) == ":"
  && two_digits_in_range(string.slice(text, 0, 2), 0, 23)
  && two_digits_in_range(string.slice(text, 3, 2), 0, 59)
}

fn find_offset_separator(
  chars: List(String),
  before: String,
) -> Result(#(String, String), Nil) {
  case chars {
    [] -> Error(Nil)
    [char, ..rest] ->
      case char == "+" || char == "-" {
        True -> Ok(#(before, char <> string.join(rest, with: "")))
        False -> find_offset_separator(rest, before <> char)
      }
  }
}

fn offset_repr_is_valid(text: String) -> Bool {
  let has_offset_shape =
    string.length(text) == 6
    && { string.starts_with(text, "+") || string.starts_with(text, "-") }
    && string.slice(text, 3, 1) == ":"
  use <- bool.guard(when: !has_offset_shape, return: False)
  let hour = string.slice(text, 1, 2)
  let minute = string.slice(text, 4, 2)
  two_digits_in_range(hour, 0, 23) && two_digits_in_range(minute, 0, 59)
}

pub fn time_repr_is_valid(text: String) -> Bool {
  let has_time_shape =
    string.length(text) >= 8
    && string.slice(text, 2, 1) == ":"
    && string.slice(text, 5, 1) == ":"
  use <- bool.guard(when: !has_time_shape, return: False)
  let hour = string.slice(text, 0, 2)
  let minute = string.slice(text, 3, 2)
  let seconds = string.slice(text, 6, 2)
  let fraction = string.drop_start(text, 8)
  two_digits_in_range(hour, 0, 23)
  && two_digits_in_range(minute, 0, 59)
  && two_digits_in_range(seconds, 0, 59)
  && fraction_is_valid(fraction)
}

fn fraction_is_valid(text: String) -> Bool {
  case text {
    "" -> True
    _ ->
      case string.starts_with(text, ".") {
        True -> {
          let digits = string.drop_start(text, 1)
          separated_digits_are_valid(string.to_graphemes(digits), char_is_digit)
        }
        False -> False
      }
  }
}

fn date_parts_are_valid(text: String) -> Bool {
  let year = string.slice(text, 0, 4)
  let month = string.slice(text, 5, 2)
  let day = string.slice(text, 8, 2)
  case
    separated_digits_are_valid(string.to_graphemes(year), char_is_digit)
    && two_digits_in_range(month, 1, 12)
    && two_digits_in_range(day, 1, 31)
  {
    True ->
      case int.parse(year), int.parse(month), int.parse(day) {
        Ok(year_number), Ok(month_number), Ok(day_number) ->
          day_number <= days_in_month(year_number, month_number)
        _, _, _ -> False
      }
    False -> False
  }
}

fn days_in_month(year: Int, month: Int) -> Int {
  case month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
    4 | 6 | 9 | 11 -> 30
    2 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    _ -> 0
  }
}

fn is_leap_year(year: Int) -> Bool {
  year % 4 == 0 && { year % 100 != 0 || year % 400 == 0 }
}

fn two_digits_in_range(text: String, minimum: Int, maximum: Int) -> Bool {
  let has_two_digits =
    string.length(text) == 2
    && separated_digits_are_valid(string.to_graphemes(text), char_is_digit)
  use <- bool.guard(when: !has_two_digits, return: False)
  case int.parse(text) {
    Ok(value) -> value >= minimum && value <= maximum
    Error(Nil) -> False
  }
}

fn drop_sign(text: String) -> String {
  let has_sign = string.starts_with(text, "+") || string.starts_with(text, "-")
  use <- bool.guard(when: !has_sign, return: text)
  string.drop_start(text, 1)
}

fn char_is_digit(char: String) -> Bool {
  case char {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9" -> True
    _ -> False
  }
}

fn char_is_hex_digit(char: String) -> Bool {
  char_is_digit(char)
  || {
    case char {
      "a" | "b" | "c" | "d" | "e" | "f" | "A" | "B" | "C" | "D" | "E" | "F" ->
        True
      _ -> False
    }
  }
}

fn is_hex_digit_string(char: String) -> Bool {
  char_is_hex_digit(char)
}

fn is_oct_digit_string(char: String) -> Bool {
  case char {
    "0" | "1" | "2" | "3" | "4" | "5" | "6" | "7" -> True
    _ -> False
  }
}

fn is_bin_digit_string(char: String) -> Bool {
  char == "0" || char == "1"
}

fn char_is_disallowed_control(char: String) -> Bool {
  case char {
    "\u{0000}"
    | "\u{0001}"
    | "\u{0002}"
    | "\u{0003}"
    | "\u{0004}"
    | "\u{0005}"
    | "\u{0006}"
    | "\u{0007}"
    | "\u{0008}"
    | "\u{000B}"
    | "\u{000C}"
    | "\r"
    | "\u{000E}"
    | "\u{000F}"
    | "\u{0010}"
    | "\u{0011}"
    | "\u{0012}"
    | "\u{0013}"
    | "\u{0014}"
    | "\u{0015}"
    | "\u{0016}"
    | "\u{0017}"
    | "\u{0018}"
    | "\u{0019}"
    | "\u{001A}"
    | "\u{001B}"
    | "\u{001C}"
    | "\u{001D}"
    | "\u{001E}"
    | "\u{001F}"
    | "\u{007F}" -> True
    _ -> False
  }
}

fn basic_key_value(text: String) -> String {
  basic_key_value_loop(string.to_graphemes(text), "")
}

fn basic_key_value_loop(chars: List(String), acc: String) -> String {
  case chars {
    [] -> acc
    ["\\", escaped, ..rest] ->
      case escaped {
        "b" -> basic_key_value_loop(rest, acc <> "\u{0008}")
        "t" -> basic_key_value_loop(rest, acc <> "\t")
        "n" -> basic_key_value_loop(rest, acc <> "\n")
        "f" -> basic_key_value_loop(rest, acc <> "\u{000C}")
        "r" -> basic_key_value_loop(rest, acc <> "\r")
        "\"" -> basic_key_value_loop(rest, acc <> "\"")
        "\\" -> basic_key_value_loop(rest, acc <> "\\")
        "e" -> basic_key_value_loop(rest, acc <> "\u{001B}")
        "x" -> {
          let #(escape, remaining) = take_chars(rest, 2, "")
          basic_key_value_loop(
            remaining,
            acc <> unicode_escape_to_string(escape),
          )
        }
        "u" -> {
          let #(escape, remaining) = take_chars(rest, 4, "")
          basic_key_value_loop(
            remaining,
            acc <> unicode_escape_to_string(escape),
          )
        }
        "U" -> {
          let #(escape, remaining) = take_chars(rest, 8, "")
          basic_key_value_loop(
            remaining,
            acc <> unicode_escape_to_string(escape),
          )
        }
        _ -> basic_key_value_loop(rest, acc <> "\\" <> escaped)
      }
    [char, ..rest] -> basic_key_value_loop(rest, acc <> char)
  }
}

fn unicode_escape_to_string(escape: String) -> String {
  case hex_to_int(string.to_graphemes(escape), 0) {
    Ok(value) ->
      case string.utf_codepoint(value) {
        Ok(codepoint) -> string.from_utf_codepoints([codepoint])
        Error(Nil) -> "\\u{" <> escape <> "}"
      }
    Error(Nil) -> "\\u{" <> escape <> "}"
  }
}

fn hex_to_int(chars: List(String), acc: Int) -> Result(Int, Nil) {
  case chars {
    [] -> Ok(acc)
    [char, ..rest] ->
      case based_digit_value(char) {
        Ok(value) -> hex_to_int(rest, acc * 16 + value)
        Error(Nil) -> Error(Nil)
      }
  }
}

fn take_chars(
  chars: List(String),
  count: Int,
  acc: String,
) -> #(String, List(String)) {
  case count, chars {
    0, _ -> #(acc, chars)
    _, [char, ..rest] -> take_chars(rest, count - 1, acc <> char)
    _, [] -> #(acc, [])
  }
}
