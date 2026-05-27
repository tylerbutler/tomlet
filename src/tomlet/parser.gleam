//// Internal module -- not part of Tomlet's public API.
////
//// This module may change without notice. Use the top-level `tomlet` module
//// for supported parsing, reading, editing, and writing APIs.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import tomlet/ast
import tomlet/key as key_utils

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

pub fn parse(input: String) -> Result(ast.Table, ParseError) {
  parse_lines(
    merge_multiline_lines(string.split(input, "\n"), []),
    0,
    [],
    [],
    [],
    [],
    [],
    [],
    [],
  )
}

fn merge_multiline_lines(
  lines: List(String),
  acc: List(String),
) -> List(String) {
  case lines {
    [] -> list.reverse(acc)
    [line, ..rest] -> {
      case line_needs_more_lines(line) {
        True -> {
          let #(merged, remaining) = collect_until_complete_value(rest, line)
          merge_multiline_lines(remaining, [merged, ..acc])
        }
        False -> merge_multiline_lines(rest, [line, ..acc])
      }
    }
  }
}

fn line_needs_more_lines(line: String) -> Bool {
  case starts_multiline_value(line) && !multiline_is_closed(line) {
    True -> True
    False -> {
      let value = line_value_text(line)
      case value {
        "" -> False
        _ -> !brackets_are_balanced(strip_inline_comments_by_line(value))
      }
    }
  }
}

fn starts_multiline_value(line: String) -> Bool {
  string.contains(line, "\"\"\"") || string.contains(line, "'''")
}

fn collect_until_complete_value(
  lines: List(String),
  current: String,
) -> #(String, List(String)) {
  case lines {
    [] -> #(current, [])
    [line, ..rest] -> {
      let next = current <> "\n" <> line
      case !line_needs_more_lines(next) {
        True -> #(next, rest)
        False -> collect_until_complete_value(rest, next)
      }
    }
  }
}

fn multiline_is_closed(text: String) -> Bool {
  let triples = string.split(text, "\"\"\"")
  let literal_triples = string.split(text, "'''")
  list.length(triples) > 2 || list.length(literal_triples) > 2
}

fn line_value_text(line: String) -> String {
  case string.split_once(line, "=") {
    Ok(#(_, raw_value)) -> string.trim(raw_value)
    Error(Nil) -> ""
  }
}

fn parse_lines(
  lines: List(String),
  offset: Int,
  active_table: List(String),
  seen: List(List(String)),
  explicit_tables: List(List(String)),
  array_tables: List(List(String)),
  array_table_parents: List(List(String)),
  dotted_tables: List(List(String)),
  entries: List(ast.Entry),
) -> Result(ast.Table, ParseError) {
  case lines {
    [] -> Ok(ast.Table(entries: list.reverse(entries), header: None))
    [line, ..rest] -> {
      let line_len = string.byte_size(line) + 1
      case line == "" && rest == [] {
        True -> Ok(ast.Table(entries: list.reverse(entries), header: None))
        False ->
          case parse_line(line, offset) {
            Ok(None) ->
              parse_lines(
                rest,
                offset + line_len,
                active_table,
                seen,
                explicit_tables,
                array_tables,
                array_table_parents,
                dotted_tables,
                entries,
              )
            Ok(Some(entry)) ->
              case entry {
                ast.TableHeader(header) -> {
                  let table_key = header_key(header)
                  case
                    key_path_conflicts_for_table_header(seen, table_key)
                    || list.contains(dotted_tables, table_key)
                    || standard_table_already_defined(
                      header,
                      explicit_tables,
                      table_key,
                    )
                    || table_kind_already_defined(
                      header,
                      explicit_tables,
                      array_tables,
                      table_key,
                    )
                    || array_table_parent_already_implied(
                      header,
                      array_tables,
                      array_table_parents,
                      table_key,
                    )
                  {
                    True -> Error(KeyAlreadyInUse(table_key, offset))
                    False -> {
                      let next_seen = case header {
                        ast.Header(kind: ast.ArrayOfTablesHeader, ..) ->
                          remove_keys_under_table(seen, table_key)
                        _ -> seen
                      }
                      let next_explicit_tables = case header {
                        ast.Header(kind: ast.StandardTable, ..) -> [
                          table_key,
                          ..explicit_tables
                        ]
                        ast.Header(kind: ast.ArrayOfTablesHeader, ..) ->
                          remove_keys_under_table(explicit_tables, table_key)
                      }
                      let next_dotted_tables_after_header = case header {
                        ast.Header(kind: ast.ArrayOfTablesHeader, ..) ->
                          remove_keys_under_table(dotted_tables, table_key)
                        _ -> dotted_tables
                      }
                      let next_array_tables = case header {
                        ast.Header(kind: ast.ArrayOfTablesHeader, ..) -> [
                          table_key,
                          ..array_tables
                        ]
                        _ -> array_tables
                      }
                      let next_array_table_parents = case header {
                        ast.Header(kind: ast.ArrayOfTablesHeader, ..) ->
                          add_paths(
                            dotted_table_paths([], table_key),
                            array_table_parents,
                          )
                        _ -> array_table_parents
                      }
                      parse_lines(
                        rest,
                        offset + line_len,
                        table_key,
                        next_seen,
                        next_explicit_tables,
                        next_array_tables,
                        next_array_table_parents,
                        next_dotted_tables_after_header,
                        [entry, ..entries],
                      )
                    }
                  }
                }
                ast.KeyValue(key: key, ..) -> {
                  let full_key =
                    list.append(active_table, key_utils.to_strings(key))
                  case
                    key_path_conflicts(seen, full_key)
                    || dotted_key_extends_defined_table(
                      explicit_tables,
                      array_tables,
                      active_table,
                      full_key,
                    )
                  {
                    True -> Error(KeyAlreadyInUse(full_key, offset))
                    False -> {
                      let next_dotted_tables =
                        add_dotted_table_paths(
                          dotted_tables,
                          active_table,
                          full_key,
                        )
                      parse_lines(
                        rest,
                        offset + line_len,
                        active_table,
                        [full_key, ..seen],
                        explicit_tables,
                        array_tables,
                        array_table_parents,
                        next_dotted_tables,
                        [entry, ..entries],
                      )
                    }
                  }
                }
                _ ->
                  parse_lines(
                    rest,
                    offset + line_len,
                    active_table,
                    seen,
                    explicit_tables,
                    array_tables,
                    array_table_parents,
                    dotted_tables,
                    [entry, ..entries],
                  )
              }
            Error(error) -> Error(error)
          }
      }
    }
  }
}

fn parse_line(
  line: String,
  offset: Int,
) -> Result(Option(ast.Entry), ParseError) {
  case
    string_contains_disallowed_control(line)
    || string_contains_disallowed_unquoted_unicode(line)
  {
    True -> Error(Unexpected(line, ExpectedSyntax, offset))
    False -> {
      let trimmed_line = string.trim(line)
      let trimmed = string.trim(strip_inline_comment(line))
      case trimmed {
        "" ->
          case string.starts_with(trimmed_line, "#") {
            True -> Ok(Some(ast.Comment(line)))
            False -> Ok(Some(ast.BlankLine))
          }
        _ -> {
          case string.starts_with(trimmed_line, "#") {
            True -> Ok(Some(ast.Comment(line)))
            False ->
              case
                string.starts_with(trimmed, "[[")
                && string.ends_with(trimmed, "]]")
              {
                True -> parse_array_of_tables_header(trimmed, offset)
                False ->
                  case
                    string.starts_with(trimmed, "[")
                    && string.ends_with(trimmed, "]")
                  {
                    True -> parse_table_header(trimmed, offset)
                    False ->
                      case string.starts_with(trimmed, "[") {
                        True ->
                          Error(Unexpected(trimmed, ExpectedTableHeader, offset))
                        False -> parse_key_value(line, offset)
                      }
                  }
              }
          }
        }
      }
    }
  }
}

fn parse_table_header(
  trimmed: String,
  offset: Int,
) -> Result(Option(ast.Entry), ParseError) {
  parse_header(trimmed, 1, ast.StandardTable, offset)
}

fn parse_array_of_tables_header(
  trimmed: String,
  offset: Int,
) -> Result(Option(ast.Entry), ParseError) {
  parse_header(trimmed, 2, ast.ArrayOfTablesHeader, offset)
}

fn parse_header(
  trimmed: String,
  delimiter_width: Int,
  kind: ast.HeaderKind,
  offset: Int,
) -> Result(Option(ast.Entry), ParseError) {
  let name =
    trimmed
    |> string.drop_start(delimiter_width)
    |> string.drop_end(delimiter_width)
    |> string.trim

  case parse_key(name) {
    Ok(key) ->
      Ok(
        Some(
          ast.TableHeader(ast.Header(
            key: key,
            kind: kind,
            trivia: ast.Trivia(""),
          )),
        ),
      )
    Error(Nil) -> Error(Unexpected(name, ExpectedKey, offset + delimiter_width))
  }
}

fn parse_key_value(
  line: String,
  offset: Int,
) -> Result(Option(ast.Entry), ParseError) {
  case split_key_value(line) {
    Ok(#(raw_key, raw_value)) -> {
      let key_text = string.trim(raw_key)
      let value_text = string.trim(strip_value_comments(raw_value))
      let value_offset =
        offset
        + string.byte_size(raw_key)
        + 1
        + trim_start_byte_offset(raw_value)
      case parse_key(key_text) {
        Ok(key) ->
          case parse_value(value_text, value_offset) {
            Ok(value) ->
              Ok(
                Some(ast.KeyValue(
                  leading: ast.Trivia(""),
                  key: key,
                  value: value,
                  trailing: ast.Trivia(
                    trailing_after_value(raw_value, value_text) <> "\n",
                  ),
                )),
              )
            Error(error) -> Error(error)
          }
        Error(Nil) -> Error(Unexpected(key_text, ExpectedKey, offset))
      }
    }
    Error(Nil) -> Error(Unexpected(line, ExpectedSyntax, offset))
  }
}

fn trailing_after_value(raw_value: String, value_text: String) -> String {
  raw_value
  |> string.drop_start(trim_start_offset(raw_value))
  |> string.drop_start(string.length(value_text))
}

fn parse_key(text: String) -> Result(ast.Key, Nil) {
  split_key_segments_text(text)
  |> list.try_map(parse_key_segment)
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
  case condition {
    True -> yes
    False -> no
  }
}

fn parse_key_segment(segment: String) -> Result(ast.KeySegment, Nil) {
  let trimmed = string.trim(segment)
  case trimmed {
    "" -> Error(Nil)
    _ ->
      case string_is_multiline_delimited(trimmed) {
        True -> Error(Nil)
        False ->
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
              case basic_string_content_is_valid(inner) {
                True ->
                  Ok(ast.QuotedKeySegment(basic_key_value(inner), trimmed))
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

fn add_paths(paths: List(List(String)), existing: List(List(String))) {
  case paths {
    [] -> existing
    [path, ..rest] ->
      case list.contains(existing, path) {
        True -> add_paths(rest, existing)
        False -> add_paths(rest, [path, ..existing])
      }
  }
}

fn parse_value(text: String, offset: Int) -> Result(ast.Value, ParseError) {
  case string.starts_with(text, "[") {
    True -> parse_array_value(text, offset)
    False ->
      case string.starts_with(text, "{") {
        True -> parse_inline_table_value(text, offset)
        False -> parse_scalar_value(text, offset)
      }
  }
}

fn parse_scalar_value(
  text: String,
  offset: Int,
) -> Result(ast.Value, ParseError) {
  case parse_multiline_basic_string(text) {
    Ok(value) -> Ok(value)
    Error(Nil) ->
      case parse_multiline_literal_string(text) {
        Ok(value) -> Ok(value)
        Error(Nil) ->
          case parse_basic_string(text) {
            Ok(value) -> Ok(value)
            Error(Nil) ->
              case parse_literal_string(text) {
                Ok(value) -> Ok(value)
                Error(Nil) ->
                  case parse_bool_value(text) {
                    Ok(value) -> Ok(value)
                    Error(Nil) ->
                      case parse_float_value(text) {
                        Ok(value) -> Ok(value)
                        Error(Nil) ->
                          case parse_date_like_value(text) {
                            Ok(value) -> Ok(value)
                            Error(Nil) -> parse_int_value(text, offset)
                          }
                      }
                  }
              }
          }
      }
  }
}

fn split_top_level_commas(text: String) -> List(#(String, Int)) {
  split_top_level_commas_loop(
    string.to_graphemes(text),
    0,
    False,
    False,
    "",
    0,
    [],
  )
}

fn split_top_level_commas_loop(
  chars: List(String),
  depth: Int,
  in_basic: Bool,
  in_literal: Bool,
  current: String,
  current_start: Int,
  parts: List(#(String, Int)),
) -> List(#(String, Int)) {
  case chars {
    [] ->
      list.reverse([
        #(string.trim(current), current_start + trim_start_byte_offset(current)),
        ..parts
      ])
    [char, ..rest] ->
      case char, depth, in_basic, in_literal {
        "\\", _, True, False -> {
          case rest {
            [] ->
              split_top_level_commas_loop(
                rest,
                depth,
                in_basic,
                in_literal,
                current <> char,
                current_start,
                parts,
              )
            [escaped, ..after_escape] ->
              split_top_level_commas_loop(
                after_escape,
                depth,
                in_basic,
                in_literal,
                current <> "\\" <> escaped,
                current_start,
                parts,
              )
          }
        }
        ",", 0, False, False ->
          split_top_level_commas_loop(
            rest,
            depth,
            in_basic,
            in_literal,
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
        "\"", _, _, False ->
          split_top_level_commas_loop(
            rest,
            depth,
            !in_basic,
            in_literal,
            current <> char,
            current_start,
            parts,
          )
        "'", _, False, _ ->
          split_top_level_commas_loop(
            rest,
            depth,
            in_basic,
            !in_literal,
            current <> char,
            current_start,
            parts,
          )
        "[", _, False, False ->
          split_top_level_commas_loop(
            rest,
            depth + 1,
            in_basic,
            in_literal,
            current <> char,
            current_start,
            parts,
          )
        "{", _, False, False ->
          split_top_level_commas_loop(
            rest,
            depth + 1,
            in_basic,
            in_literal,
            current <> char,
            current_start,
            parts,
          )
        "]", _, False, False ->
          split_top_level_commas_loop(
            rest,
            depth - 1,
            in_basic,
            in_literal,
            current <> char,
            current_start,
            parts,
          )
        "}", _, False, False ->
          split_top_level_commas_loop(
            rest,
            depth - 1,
            in_basic,
            in_literal,
            current <> char,
            current_start,
            parts,
          )
        _, _, _, _ ->
          split_top_level_commas_loop(
            rest,
            depth,
            in_basic,
            in_literal,
            current <> char,
            current_start,
            parts,
          )
      }
  }
}

fn trim_start_offset(text: String) -> Int {
  string.length(text) - string.length(string.trim_start(text))
}

fn trim_start_byte_offset(text: String) -> Int {
  string.byte_size(text) - string.byte_size(string.trim_start(text))
}

fn brackets_are_balanced(text: String) -> Bool {
  bracket_depth(string.to_graphemes(text), 0, False, False) == 0
}

fn bracket_depth(
  chars: List(String),
  depth: Int,
  in_basic: Bool,
  in_literal: Bool,
) -> Int {
  case chars {
    [] -> depth
    [char, ..rest] ->
      case char, in_basic, in_literal {
        "\\", True, False -> {
          case rest {
            [] -> bracket_depth(rest, depth, in_basic, in_literal)
            [_, ..after_escape] ->
              bracket_depth(after_escape, depth, in_basic, in_literal)
          }
        }
        "\"", _, False -> bracket_depth(rest, depth, !in_basic, in_literal)
        "'", False, _ -> bracket_depth(rest, depth, in_basic, !in_literal)
        "[", False, False ->
          bracket_depth(rest, depth + 1, in_basic, in_literal)
        "{", False, False ->
          bracket_depth(rest, depth + 1, in_basic, in_literal)
        "]", False, False ->
          bracket_depth(rest, depth - 1, in_basic, in_literal)
        "}", False, False ->
          bracket_depth(rest, depth - 1, in_basic, in_literal)
        _, _, _ -> bracket_depth(rest, depth, in_basic, in_literal)
      }
  }
}

fn parse_array_value(
  text: String,
  offset: Int,
) -> Result(ast.Value, ParseError) {
  case string.starts_with(text, "[") && string.ends_with(text, "]") {
    True -> {
      let body =
        text
        |> string.drop_start(1)
        |> string.drop_end(1)
      let clean_body = strip_inline_comments_by_line(body)

      case string.trim(clean_body) {
        "" -> Ok(ast.Array([], text))
        _ ->
          case
            parse_array_items(split_top_level_commas(clean_body), offset + 1)
          {
            Ok(items) -> Ok(ast.Array(items, text))
            Error(error) -> Error(error)
          }
      }
    }
    False -> Error(Unexpected(text, ExpectedSyntax, offset))
  }
}

fn parse_array_items(
  parts: List(#(String, Int)),
  body_offset: Int,
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
          case parse_value(clean_part, body_offset + part_offset) {
            Ok(value) ->
              case parse_array_items(rest, body_offset) {
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
) -> Result(ast.Value, ParseError) {
  case string.starts_with(text, "{") && string.ends_with(text, "}") {
    True -> {
      let body =
        text
        |> string.drop_start(1)
        |> string.drop_end(1)
      let clean_body = strip_inline_comments_by_line(body)

      case inline_table_newlines_are_valid(body) {
        False -> Error(Unexpected(text, ExpectedSyntax, offset))
        True ->
          case string.trim(clean_body) {
            "" -> Ok(ast.InlineTable([], text))
            _ ->
              case
                parse_inline_entries(
                  split_top_level_commas(clean_body),
                  offset + 1,
                  [],
                )
              {
                Ok(entries) -> Ok(ast.InlineTable(entries, text))
                Error(error) -> Error(error)
              }
          }
      }
    }
    False -> Error(Unexpected(text, ExpectedSyntax, offset))
  }
}

fn inline_table_newlines_are_valid(text: String) -> Bool {
  inline_table_newlines_are_valid_loop(
    string.to_graphemes(text),
    0,
    False,
    False,
  )
}

fn inline_table_newlines_are_valid_loop(
  chars: List(String),
  depth: Int,
  in_basic: Bool,
  in_literal: Bool,
) -> Bool {
  case chars {
    [] -> True
    ["\\", _, ..rest] if in_basic ->
      inline_table_newlines_are_valid_loop(rest, depth, in_basic, in_literal)
    ["\n", ..rest] ->
      case depth > 0 || in_basic || in_literal {
        True ->
          inline_table_newlines_are_valid_loop(
            rest,
            depth,
            in_basic,
            in_literal,
          )
        False -> False
      }
    ["\"", ..rest] if !in_literal ->
      inline_table_newlines_are_valid_loop(rest, depth, !in_basic, in_literal)
    ["'", ..rest] if !in_basic ->
      inline_table_newlines_are_valid_loop(rest, depth, in_basic, !in_literal)
    ["[", ..rest] if !in_basic && !in_literal ->
      inline_table_newlines_are_valid_loop(
        rest,
        depth + 1,
        in_basic,
        in_literal,
      )
    ["{", ..rest] if !in_basic && !in_literal ->
      inline_table_newlines_are_valid_loop(
        rest,
        depth + 1,
        in_basic,
        in_literal,
      )
    ["]", ..rest] if !in_basic && !in_literal ->
      inline_table_newlines_are_valid_loop(
        rest,
        depth - 1,
        in_basic,
        in_literal,
      )
    ["}", ..rest] if !in_basic && !in_literal ->
      inline_table_newlines_are_valid_loop(
        rest,
        depth - 1,
        in_basic,
        in_literal,
      )
    [_, ..rest] ->
      inline_table_newlines_are_valid_loop(rest, depth, in_basic, in_literal)
  }
}

fn parse_inline_entries(
  parts: List(#(String, Int)),
  body_offset: Int,
  seen: List(List(String)),
) -> Result(List(ast.InlineTableEntry), ParseError) {
  case parts {
    [] -> Ok([])
    [#(part, part_offset), ..rest] -> {
      let entry_offset = body_offset + part_offset
      case string.trim(part) {
        "" -> Error(Unexpected("", ExpectedSyntax, entry_offset))
        _ ->
          case split_key_value(part) {
            Ok(#(raw_key, raw_value)) ->
              case parse_key(string.trim(raw_key)) {
                Ok(key) -> {
                  let key_path = key_utils.to_strings(key)
                  case key_path_conflicts(seen, key_path) {
                    True ->
                      Error(Unexpected(part, ExpectedSyntax, entry_offset))
                    False ->
                      case
                        parse_value(
                          string.trim(strip_inline_comments_by_line(raw_value)),
                          entry_offset
                            + string.byte_size(raw_key)
                            + 1
                            + trim_start_byte_offset(raw_value),
                        )
                      {
                        Ok(value) ->
                          case
                            parse_inline_entries(rest, body_offset, [
                              key_path,
                              ..seen
                            ])
                          {
                            Ok(entries) ->
                              Ok([
                                ast.InlineTableEntry(
                                  ast.Trivia(""),
                                  key,
                                  value,
                                  ast.Trivia(""),
                                ),
                                ..entries
                              ])
                            Error(error) -> Error(error)
                          }
                        Error(error) -> Error(error)
                      }
                  }
                }
                Error(Nil) -> Error(Unexpected(part, ExpectedKey, entry_offset))
              }
            Error(Nil) -> Error(Unexpected(part, ExpectedSyntax, entry_offset))
          }
      }
    }
  }
}

fn strip_inline_comment(text: String) -> String {
  strip_inline_comment_loop(string.to_graphemes(text), False, False, "")
}

fn strip_inline_comments_by_line(text: String) -> String {
  text
  |> string.split("\n")
  |> list.map(strip_inline_comment)
  |> string.join(with: "\n")
}

fn strip_value_comments(text: String) -> String {
  let trimmed = string.trim_start(text)
  case
    string.starts_with(trimmed, "\"\"\"") || string.starts_with(trimmed, "'''")
  {
    True -> strip_inline_comment(text)
    False -> strip_inline_comments_by_line(text)
  }
}

fn strip_inline_comment_loop(
  chars: List(String),
  in_basic: Bool,
  in_literal: Bool,
  acc: String,
) -> String {
  case chars {
    [] -> acc
    ["\\", escaped, ..rest] ->
      case in_basic {
        True ->
          strip_inline_comment_loop(
            rest,
            in_basic,
            in_literal,
            acc <> "\\" <> escaped,
          )
        False ->
          strip_inline_comment_loop(
            [escaped, ..rest],
            in_basic,
            in_literal,
            acc <> "\\",
          )
      }
    ["#", ..rest] ->
      case in_basic || in_literal {
        True ->
          strip_inline_comment_loop(rest, in_basic, in_literal, acc <> "#")
        False -> acc
      }
    ["\"", ..rest] ->
      case in_literal {
        True ->
          strip_inline_comment_loop(rest, in_basic, in_literal, acc <> "\"")
        False ->
          strip_inline_comment_loop(rest, !in_basic, in_literal, acc <> "\"")
      }
    ["'", ..rest] ->
      case in_basic {
        True ->
          strip_inline_comment_loop(rest, in_basic, in_literal, acc <> "'")
        False ->
          strip_inline_comment_loop(rest, in_basic, !in_literal, acc <> "'")
      }
    [char, ..rest] ->
      strip_inline_comment_loop(rest, in_basic, in_literal, acc <> char)
  }
}

fn parse_multiline_basic_string(text: String) -> Result(ast.Value, Nil) {
  case string.starts_with(text, "\"\"\"") && string.ends_with(text, "\"\"\"") {
    True -> {
      let inner =
        text
        |> string.drop_start(3)
        |> string.drop_end(3)

      case text != "\"\"\"" && multiline_basic_string_content_is_valid(inner) {
        True -> Ok(ast.String(inner, ast.MultiBasicString, text))
        False -> Error(Nil)
      }
    }
    False -> Error(Nil)
  }
}

fn parse_multiline_literal_string(text: String) -> Result(ast.Value, Nil) {
  case string.starts_with(text, "'''") && string.ends_with(text, "'''") {
    True -> {
      let inner =
        text
        |> string.drop_start(3)
        |> string.drop_end(3)

      case text != "'''" && multiline_literal_string_content_is_valid(inner) {
        True -> Ok(ast.String(inner, ast.MultiLiteralString, text))
        False -> Error(Nil)
      }
    }
    False -> Error(Nil)
  }
}

fn parse_basic_string(text: String) -> Result(ast.Value, Nil) {
  case string.starts_with(text, "\"") && string.ends_with(text, "\"") {
    True -> {
      let inner =
        text
        |> string.drop_start(1)
        |> string.drop_end(1)

      case basic_string_content_is_valid(inner) {
        True -> Ok(ast.String(inner, ast.BasicString, text))
        False -> Error(Nil)
      }
    }
    False -> Error(Nil)
  }
}

fn parse_literal_string(text: String) -> Result(ast.Value, Nil) {
  case string.starts_with(text, "'") && string.ends_with(text, "'") {
    True -> {
      let inner =
        text
        |> string.drop_start(1)
        |> string.drop_end(1)

      case literal_string_content_is_valid(inner) {
        True -> Ok(ast.String(inner, ast.LiteralString, text))
        False -> Error(Nil)
      }
    }
    False -> Error(Nil)
  }
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

fn multiline_basic_string_content_is_valid(text: String) -> Bool {
  multiline_basic_string_chars_are_valid(string.to_graphemes(text))
}

fn multiline_basic_string_chars_are_valid(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    ["\\"] -> False
    ["\\", ..rest] -> multiline_basic_escape_is_valid(rest)
    ["\"", "\"", "\"", ..] -> False
    [char, ..rest] ->
      case char_is_disallowed_control(char) {
        True -> False
        False -> multiline_basic_string_chars_are_valid(rest)
      }
  }
}

fn multiline_basic_escape_is_valid(chars: List(String)) -> Bool {
  case chars {
    [] -> False
    ["\n", ..rest] -> multiline_basic_string_chars_are_valid(rest)
    ["\r", "\n", ..rest] -> multiline_basic_string_chars_are_valid(rest)
    [" ", ..rest] -> multiline_basic_line_ending_escape_is_valid(rest)
    ["\t", ..rest] -> multiline_basic_line_ending_escape_is_valid(rest)
    [escaped, ..rest] ->
      case escaped {
        "b" | "t" | "n" | "f" | "r" | "\"" | "\\" ->
          multiline_basic_string_chars_are_valid(rest)
        "u" ->
          unicode_escape_is_valid_for(
            multiline_basic_string_chars_are_valid,
            rest,
            4,
          )
        "U" ->
          unicode_escape_is_valid_for(
            multiline_basic_string_chars_are_valid,
            rest,
            8,
          )
        _ -> False
      }
  }
}

fn multiline_basic_line_ending_escape_is_valid(chars: List(String)) -> Bool {
  case chars {
    [] -> False
    [" ", ..rest] -> multiline_basic_line_ending_escape_is_valid(rest)
    ["\t", ..rest] -> multiline_basic_line_ending_escape_is_valid(rest)
    ["\n", ..rest] -> multiline_basic_string_chars_are_valid(rest)
    ["\r", "\n", ..rest] -> multiline_basic_string_chars_are_valid(rest)
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

fn parse_date_like_value(text: String) -> Result(ast.Value, Nil) {
  case datetime_repr_is_valid(text) {
    True -> Ok(ast.DateTime(text))
    False ->
      case time_repr_is_valid(text) {
        True -> Ok(ast.Time(text))
        False ->
          case date_repr_is_valid(text) {
            True -> Ok(ast.Date(text))
            False -> Error(Nil)
          }
      }
  }
}

fn parse_int_value(text: String, offset: Int) -> Result(ast.Value, ParseError) {
  let normalized = string.replace(text, each: "_", with: "")
  case int_repr_is_valid(text) {
    True ->
      case int.parse(normalized) {
        Ok(value) -> Ok(ast.Int(value, text))
        Error(_) -> parse_based_int_value(normalized, text, offset)
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

fn basic_string_content_is_valid(text: String) -> Bool {
  basic_string_chars_are_valid(string.to_graphemes(text))
}

fn basic_string_chars_are_valid(chars: List(String)) -> Bool {
  case chars {
    [] -> True
    ["\\"] -> False
    ["\\", escaped, ..rest] ->
      case escaped {
        "b" | "t" | "n" | "f" | "r" | "\"" | "\\" ->
          basic_string_chars_are_valid(rest)
        "u" -> unicode_escape_is_valid(rest, 4)
        "U" -> unicode_escape_is_valid(rest, 8)
        _ -> False
      }
    ["\n", ..] -> False
    ["\"", ..] -> False
    [char, ..rest] ->
      case char_is_disallowed_control(char) {
        True -> False
        False -> basic_string_chars_are_valid(rest)
      }
  }
}

fn unicode_escape_is_valid(chars: List(String), count: Int) -> Bool {
  unicode_escape_is_valid_for(basic_string_chars_are_valid, chars, count)
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
        Error(_) -> False
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
  case separated_digits_are_valid(string.to_graphemes(text), char_is_digit) {
    True ->
      case string.replace(text, each: "_", with: "") {
        "" -> False
        digits ->
          case string.length(digits) > 1 && string.starts_with(digits, "0") {
            True -> False
            False -> True
          }
      }
    False -> False
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
  case
    string.length(text) == 10
    && string.slice(text, 4, 1) == "-"
    && string.slice(text, 7, 1) == "-"
  {
    True -> date_parts_are_valid(text)
    False -> False
  }
}

pub fn datetime_repr_is_valid(text: String) -> Bool {
  case string.split_once(text, "T") {
    Ok(#(date, time_offset)) ->
      date_repr_is_valid(date) && time_offset_repr_is_valid(time_offset)
    Error(Nil) ->
      case string.split_once(text, "t") {
        Ok(#(date, time_offset)) ->
          date_repr_is_valid(date) && time_offset_repr_is_valid(time_offset)
        Error(Nil) ->
          case string.split_once(text, " ") {
            Ok(#(date, time_offset)) ->
              date_repr_is_valid(date) && time_offset_repr_is_valid(time_offset)
            Error(Nil) -> False
          }
      }
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
  case
    string.length(text) == 6
    && { string.starts_with(text, "+") || string.starts_with(text, "-") }
    && string.slice(text, 3, 1) == ":"
  {
    True -> {
      let hour = string.slice(text, 1, 2)
      let minute = string.slice(text, 4, 2)
      two_digits_in_range(hour, 0, 23) && two_digits_in_range(minute, 0, 59)
    }
    False -> False
  }
}

pub fn time_repr_is_valid(text: String) -> Bool {
  case
    string.length(text) >= 8
    && string.slice(text, 2, 1) == ":"
    && string.slice(text, 5, 1) == ":"
  {
    True -> {
      let hour = string.slice(text, 0, 2)
      let minute = string.slice(text, 3, 2)
      let seconds = string.slice(text, 6, 2)
      let fraction = string.drop_start(text, 8)
      two_digits_in_range(hour, 0, 23)
      && two_digits_in_range(minute, 0, 59)
      && two_digits_in_range(seconds, 0, 59)
      && fraction_is_valid(fraction)
    }
    False -> False
  }
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
  case
    string.length(text) == 2
    && separated_digits_are_valid(string.to_graphemes(text), char_is_digit)
  {
    True ->
      case int.parse(text) {
        Ok(value) -> value >= minimum && value <= maximum
        Error(_) -> False
      }
    False -> False
  }
}

fn drop_sign(text: String) -> String {
  case string.starts_with(text, "+") || string.starts_with(text, "-") {
    True -> string.drop_start(text, 1)
    False -> text
  }
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

fn string_contains_disallowed_control(text: String) -> Bool {
  string_contains_disallowed_control_loop(string.to_graphemes(text))
}

fn string_contains_disallowed_control_loop(chars: List(String)) -> Bool {
  case chars {
    [] -> False
    [char, ..rest] ->
      char_is_disallowed_control(char)
      || string_contains_disallowed_control_loop(rest)
  }
}

fn string_contains_disallowed_unquoted_unicode(text: String) -> Bool {
  string_contains_disallowed_unquoted_unicode_loop(
    string.to_graphemes(text),
    False,
    False,
    False,
  )
}

fn string_contains_disallowed_unquoted_unicode_loop(
  chars: List(String),
  in_basic_string: Bool,
  in_literal_string: Bool,
  escaped: Bool,
) -> Bool {
  case chars {
    [] -> False
    ["#", ..] if !in_basic_string && !in_literal_string -> False
    ["\\", ..rest] if in_basic_string && !escaped ->
      string_contains_disallowed_unquoted_unicode_loop(
        rest,
        in_basic_string,
        in_literal_string,
        True,
      )
    ["\"", ..rest] if !in_literal_string && !escaped ->
      string_contains_disallowed_unquoted_unicode_loop(
        rest,
        !in_basic_string,
        in_literal_string,
        False,
      )
    ["'", ..rest] if !in_basic_string ->
      string_contains_disallowed_unquoted_unicode_loop(
        rest,
        in_basic_string,
        !in_literal_string,
        False,
      )
    [char, ..rest] -> {
      let disallowed =
        !in_basic_string
        && !in_literal_string
        && { char == "\u{3000}" || char == "\u{FEFF}" }

      disallowed
      || string_contains_disallowed_unquoted_unicode_loop(
        rest,
        in_basic_string,
        in_literal_string,
        False,
      )
    }
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
        Error(_) -> "\\u{" <> escape <> "}"
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
