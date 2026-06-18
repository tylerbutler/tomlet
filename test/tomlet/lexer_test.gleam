import gleam/list
import gleeunit
import tomlet/lexer

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn offsets_are_byte_accurate_test() -> Nil {
  // "ab = 1\n": bytes 0..6. First token BareKey("ab") at offset 0,
  // Whitespace at 2, Equal at 3, Whitespace at 4, Integer at 5, EndOfLine at 6.
  let spans = lexer.lex("ab = 1\n")
  let offsets = list.map(spans, fn(s) { s.offset })
  assert offsets == [0, 2, 3, 4, 5, 6]
}

pub fn offsets_count_utf8_bytes_not_codepoints_test() -> Nil {
  // "é" is two UTF-8 bytes, so "éa " spans bytes 0..4 and "=" lands at 4.
  let spans = lexer.lex("éa = 1\n")
  let assert [_key, _ws, equal, ..] = spans
  assert equal.offset == 4
}
