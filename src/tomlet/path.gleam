//// Internal module -- not part of Tomlet's public API.
////
//// This module may change without notice. Use the top-level `tomlet` module
//// for supported parsing, reading, editing, and writing APIs.

import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import tomlet/ast
import tomlet/key as key_utils

pub fn get(table: ast.Table, path: List(String)) -> Result(ast.Value, Nil) {
  let ast.Table(entries: entries, header: _) = table
  case collect_array_tables(entries, path) {
    [] -> scan_entries(entries, [], path)
    tables -> Ok(ast.ArrayOfTables(tables))
  }
}

fn scan_entries(
  entries: List(ast.Entry),
  active_table: List(String),
  target: List(String),
) -> Result(ast.Value, Nil) {
  case entries {
    [] -> Error(Nil)
    [entry, ..rest] ->
      case entry {
        ast.TableHeader(ast.Header(key: key, kind: ast.StandardTable, trivia: _)) ->
          scan_entries(rest, key_utils.to_strings(key), target)
        ast.TableHeader(ast.Header(
          key: key,
          kind: ast.ArrayOfTablesHeader,
          trivia: _,
        )) -> scan_entries(rest, key_utils.to_strings(key), target)
        ast.KeyValue(key: key, value: value, ..) ->
          scan_key_value(key, value, rest, active_table, target)
        _ -> scan_entries(rest, active_table, target)
      }
  }
}

fn scan_key_value(
  key: ast.Key,
  value: ast.Value,
  rest: List(ast.Entry),
  active_table: List(String),
  target: List(String),
) -> Result(ast.Value, Nil) {
  let full_key = list.append(active_table, key_utils.to_strings(key))
  use <- bool.guard(when: full_key == target, return: Ok(value))
  case value {
    ast.InlineTable(inline_entries, source_text: _) ->
      case scan_inline_entries(inline_entries, full_key, target) {
        Ok(found) -> Ok(found)
        Error(Nil) -> scan_entries(rest, active_table, target)
      }
    _ -> scan_entries(rest, active_table, target)
  }
}

fn scan_inline_entries(
  entries: List(ast.InlineTableEntry),
  active_path: List(String),
  target: List(String),
) -> Result(ast.Value, Nil) {
  case entries {
    [] -> Error(Nil)
    [ast.InlineTableEntry(key: key, value: value, ..), ..rest] ->
      scan_inline_entry(key, value, rest, active_path, target)
  }
}

fn scan_inline_entry(
  key: ast.Key,
  value: ast.Value,
  rest: List(ast.InlineTableEntry),
  active_path: List(String),
  target: List(String),
) -> Result(ast.Value, Nil) {
  let full_key = list.append(active_path, key_utils.to_strings(key))
  use <- bool.guard(when: full_key == target, return: Ok(value))
  case value {
    ast.InlineTable(nested_entries, source_text: _) ->
      case scan_inline_entries(nested_entries, full_key, target) {
        Ok(found) -> Ok(found)
        Error(Nil) -> scan_inline_entries(rest, active_path, target)
      }
    _ -> scan_inline_entries(rest, active_path, target)
  }
}

fn collect_array_tables(
  entries: List(ast.Entry),
  target: List(String),
) -> List(ast.Table) {
  collect_array_tables_loop(entries, target, None, [], [])
}

fn collect_array_tables_loop(
  entries: List(ast.Entry),
  target: List(String),
  current_header: Option(ast.Header),
  current_entries: List(ast.Entry),
  tables: List(ast.Table),
) -> List(ast.Table) {
  case entries {
    [] ->
      list.reverse(finish_array_table(current_header, current_entries, tables))
    [entry, ..rest] ->
      case entry {
        ast.TableHeader(header) -> {
          let next_tables =
            finish_array_table(current_header, current_entries, tables)
          collect_array_table_header(header, rest, target, next_tables)
        }
        _ ->
          case current_header {
            Some(_) ->
              collect_array_tables_loop(
                rest,
                target,
                current_header,
                [entry, ..current_entries],
                tables,
              )
            None ->
              collect_array_tables_loop(
                rest,
                target,
                current_header,
                current_entries,
                tables,
              )
          }
      }
  }
}

fn collect_array_table_header(
  header: ast.Header,
  rest: List(ast.Entry),
  target: List(String),
  next_tables: List(ast.Table),
) -> List(ast.Table) {
  case header {
    ast.Header(key: key, kind: ast.ArrayOfTablesHeader, trivia: _) -> {
      let next_header = case key_utils.to_strings(key) == target {
        True -> Some(header)
        False -> None
      }
      collect_array_tables_loop(rest, target, next_header, [], next_tables)
    }
    _ -> collect_array_tables_loop(rest, target, None, [], next_tables)
  }
}

fn finish_array_table(
  current_header: Option(ast.Header),
  current_entries: List(ast.Entry),
  tables: List(ast.Table),
) -> List(ast.Table) {
  case current_header {
    Some(header) -> [
      ast.Table(entries: list.reverse(current_entries), header: Some(header)),
      ..tables
    ]
    None -> tables
  }
}
