import gleeunit
import tomlet

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_with_strict_rejects_1_1_test() -> Nil {
  let options = tomlet.with_version(tomlet.default_options(), tomlet.Toml10)
  let assert Error(_) = tomlet.parse_with("t = { a = 1, }\n", options)
  Nil
}

pub fn parse_with_default_accepts_1_1_test() -> Nil {
  let assert Ok(_) =
    tomlet.parse_with("t = { a = 1, }\n", tomlet.default_options())
  Nil
}

pub fn parse_defaults_to_1_1_test() -> Nil {
  let assert Ok(_) = tomlet.parse("tm = 13:15\n")
  Nil
}

pub fn parse_bytes_with_strict_rejects_1_1_test() -> Nil {
  let options = tomlet.with_version(tomlet.default_options(), tomlet.Toml10)
  let assert Error(_) =
    tomlet.parse_bytes_with(<<"s = \"\\e\"\n":utf8>>, options)
  Nil
}

pub fn parse_bytes_with_default_accepts_1_1_test() -> Nil {
  let assert Ok(_) =
    tomlet.parse_bytes_with(<<"tm = 13:15\n":utf8>>, tomlet.default_options())
  Nil
}
