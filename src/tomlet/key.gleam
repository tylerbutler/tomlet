//// Internal key/path helpers -- not part of Tomlet's public API.

import gleam/list
import gleam/string
import tomlet/ast

pub fn to_strings(key: ast.Key) -> List(String) {
  let ast.Key(segments) = key
  list.map(segments, fn(segment) {
    case segment {
      ast.BareKeySegment(text) -> text
      ast.QuotedKeySegment(value, source_text: _) -> value
    }
  })
}

pub fn starts_with(path: List(String), prefix: List(String)) -> Bool {
  case path, prefix {
    _, [] -> True
    [value, ..rest_values], [prefix_value, ..rest_prefix] ->
      value == prefix_value && starts_with(rest_values, rest_prefix)
    _, _ -> False
  }
}

pub fn conflicts(existing: List(String), target: List(String)) -> Bool {
  starts_with(target, existing) || starts_with(existing, target)
}

pub fn is_bare_key(segment: String) -> Bool {
  string.length(segment) > 0
  && all_bare_key_codepoints(string.to_utf_codepoints(segment))
}

pub fn is_bare_key_codepoint(codepoint: Int) -> Bool {
  { codepoint >= 65 && codepoint <= 90 }
  || { codepoint >= 97 && codepoint <= 122 }
  || { codepoint >= 48 && codepoint <= 57 }
  || codepoint == 45
  || codepoint == 95
}

fn all_bare_key_codepoints(codepoints: List(UtfCodepoint)) -> Bool {
  case codepoints {
    [] -> True
    [codepoint, ..rest] ->
      is_bare_key_codepoint(string.utf_codepoint_to_int(codepoint))
      && all_bare_key_codepoints(rest)
  }
}
