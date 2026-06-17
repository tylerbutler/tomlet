//// Internal module -- not part of Tomlet's public API.
////
//// Wraps the `william` TOML lexer and annotates every token with the byte
//// offset at which it begins, so the parser can report byte-accurate errors.

import gleam/list
import gleam/string
import william.{type Token}

pub type Spanned {
  Spanned(token: Token, offset: Int)
}

/// Tokenise TOML source into spanned tokens carrying byte offsets.
pub fn lex(input: String) -> List(Spanned) {
  let tokens = william.tokenise(william.new(), input)
  annotate(tokens, 0, [])
}

fn annotate(
  tokens: List(Token),
  offset: Int,
  acc: List(Spanned),
) -> List(Spanned) {
  case tokens {
    [] -> list.reverse(acc)
    [token, ..rest] -> {
      let width = string.byte_size(william.to_source([token]))
      annotate(rest, offset + width, [
        Spanned(token: token, offset: offset),
        ..acc
      ])
    }
  }
}
