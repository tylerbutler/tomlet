#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


TOML_TEST_VERSION = "v2.2.0"
ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".toml-test"
TOML_TEST_REPO = CACHE / "toml-test"

VALID_GENERATED = ROOT / "test" / "tomlet" / "corpus_generated_test.gleam"
INVALID_GENERATED = ROOT / "test" / "tomlet" / "invalid_corpus_generated_test.gleam"

# Every valid TOML 1.0 corpus input must round-trip byte-for-byte.
ROUNDTRIP_UNSUPPORTED = set()

INVALID_BYTE_FIXTURES = {
    # These fixtures contain invalid UTF-8/UTF-16 bytes or misplaced UTF-8 BOM
    # bytes, so exercise the byte-oriented API instead of String input.
    "encoding/bad-codepoint",
    "encoding/bad-utf8-at-end",
    "encoding/bad-utf8-in-array",
    "encoding/bad-utf8-in-comment",
    "encoding/bad-utf8-in-multiline",
    "encoding/bad-utf8-in-multiline-literal",
    "encoding/bad-utf8-in-string",
    "encoding/bad-utf8-in-string-literal",
    "encoding/bom-not-at-start-01",
    "encoding/bom-not-at-start-02",
    "encoding/utf16-bom",
    "encoding/utf16-comment",
    "encoding/utf16-key",
}


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate and run Tomlet corpus checks without shell wrappers."
    )
    parser.add_argument(
        "suite",
        choices=["valid", "invalid", "all"],
        nargs="?",
        default="all",
        help="Corpus suite to run.",
    )
    args = parser.parse_args()

    if args.suite in {"valid", "all"}:
        run_valid()
    if args.suite in {"invalid", "all"}:
        run_invalid()
    return 0


def run_valid() -> None:
    repo = ensure_toml_test_repo()
    files = load_toml_1_0_paths(repo, "valid")
    write_valid_tests(repo, files, VALID_GENERATED)
    try:
        run_gleam_targets()
    finally:
        VALID_GENERATED.unlink(missing_ok=True)
    print(
        "toml-test valid corpus parse/round-trip checks succeeded from "
        f"{repo / 'tests' / 'valid'}"
    )


def run_invalid() -> None:
    repo = ensure_toml_test_repo()
    files = load_toml_1_0_paths(repo, "invalid")
    write_invalid_tests(repo, files, INVALID_GENERATED)
    try:
        run_gleam_targets()
    finally:
        INVALID_GENERATED.unlink(missing_ok=True)
    print(f"toml-test invalid corpus checks succeeded from {repo / 'tests' / 'invalid'}")


def ensure_toml_test_repo() -> Path:
    if not TOML_TEST_REPO.is_dir():
        CACHE.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                "git",
                "clone",
                "--depth",
                "1",
                "--branch",
                TOML_TEST_VERSION,
                "https://github.com/toml-lang/toml-test",
                str(TOML_TEST_REPO),
            ],
            cwd=ROOT,
            check=True,
        )
    return TOML_TEST_REPO


def load_toml_1_0_paths(repo: Path, kind: str) -> list[Path]:
    prefix = f"{kind}/"
    files = []
    file_list = repo / "tests" / "files-toml-1.0.0"
    for raw in file_list.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if raw.startswith(prefix) and raw.endswith(".toml"):
            files.append(Path(raw))
    return sorted(files)


def write_valid_tests(repo: Path, files: list[Path], generated: Path) -> None:
    valid_root = repo / "tests" / "valid"
    known_paths = {path.with_suffix("").relative_to("valid").as_posix() for path in files}
    assert_known_paths("ROUNDTRIP_UNSUPPORTED", ROUNDTRIP_UNSUPPORTED, known_paths)

    generated.parent.mkdir(parents=True, exist_ok=True)
    roundtrip_count = 0
    parse_only_count = 0
    with generated.open("w", encoding="utf-8") as out:
        write_gleam_prelude(out)
        for rel_path in files:
            rel = rel_path.with_suffix("").relative_to("valid").as_posix()
            data = read_text_preserving_newlines(repo / "tests" / rel_path)
            out.write(f"pub fn {gleam_test_name('valid', rel)}() {{\n")
            out.write(f"  let input = from_codepoints({gleam_codepoints(data)})\n")
            if rel in ROUNDTRIP_UNSUPPORTED:
                parse_only_count += 1
                out.write(
                    "  // Known parse-only corpus case; see "
                    "ROUNDTRIP_UNSUPPORTED in scripts/run_corpus_tests.py.\n"
                )
                out.write("  let assert Ok(_) = tomlet.parse(input)\n")
            else:
                roundtrip_count += 1
                out.write("  let assert Ok(doc) = tomlet.parse(input)\n")
                out.write("  assert tomlet.to_string(doc) == input\n")
            out.write("}\n\n")

    print(
        f"generated {len(files)} valid corpus tests at {generated} "
        f"({roundtrip_count} round-trip, {parse_only_count} parse-only)"
    )


def write_invalid_tests(repo: Path, files: list[Path], generated: Path) -> None:
    known_paths = {path.with_suffix("").relative_to("invalid").as_posix() for path in files}
    assert_known_paths("INVALID_BYTE_FIXTURES", INVALID_BYTE_FIXTURES, known_paths)

    generated.parent.mkdir(parents=True, exist_ok=True)
    byte_rejected_count = 0
    rejected_count = 0
    with generated.open("w", encoding="utf-8") as out:
        write_gleam_prelude(out)
        for rel_path in files:
            rel = rel_path.with_suffix("").relative_to("invalid").as_posix()
            out.write(f"pub fn {gleam_test_name('invalid', rel)}() {{\n")
            if rel in INVALID_BYTE_FIXTURES:
                byte_rejected_count += 1
                data = (repo / "tests" / rel_path).read_bytes()
                out.write(f"  let input = {gleam_bytes(data)}\n")
                out.write("  let assert Error(_) = tomlet.parse_bytes(input)\n")
            else:
                rejected_count += 1
                data = read_text_preserving_newlines(repo / "tests" / rel_path)
                out.write(f"  let input = from_codepoints({gleam_codepoints(data)})\n")
                out.write("  let assert Error(_) = tomlet.parse(input)\n")
            out.write("}\n\n")

    print(
        f"generated {len(files)} invalid corpus tests at {generated} "
        f"({rejected_count} string reject assertions, "
        f"{byte_rejected_count} byte reject assertions)"
    )


def assert_known_paths(name: str, configured: set[str], known_paths: set[str]) -> None:
    missing = configured - known_paths
    if missing:
        raise SystemExit(
            f"{name} contains unknown corpus paths: " + ", ".join(sorted(missing))
        )


def read_text_preserving_newlines(path: Path) -> str:
    with path.open("r", encoding="utf-8", newline="") as file:
        return file.read()


def write_gleam_prelude(out) -> None:
    out.write("import gleam/list\nimport gleam/string\nimport gleeunit\nimport tomlet\n\n")
    out.write("pub fn main() -> Nil {\n  gleeunit.main()\n}\n\n")
    out.write("fn from_codepoints(codepoints: List(Int)) -> String {\n")
    out.write("  codepoints_to_string(codepoints, [])\n")
    out.write("}\n\n")
    out.write(
        "fn codepoints_to_string(codepoints: List(Int), "
        "acc: List(UtfCodepoint)) -> String {\n"
    )
    out.write("  case codepoints {\n")
    out.write("    [] -> string.from_utf_codepoints(list.reverse(acc))\n")
    out.write("    [codepoint, ..rest] -> {\n")
    out.write("      let assert Ok(utf_codepoint) = string.utf_codepoint(codepoint)\n")
    out.write("      codepoints_to_string(rest, [utf_codepoint, ..acc])\n")
    out.write("    }\n")
    out.write("  }\n")
    out.write("}\n\n")


def gleam_codepoints(value: str) -> str:
    return "[" + ", ".join(str(ord(char)) for char in value) + "]"


def gleam_bytes(value: bytes) -> str:
    return "<<" + ", ".join(str(byte) for byte in value) + ">>"


def gleam_test_name(prefix: str, rel: str) -> str:
    suffix = "".join(ch.lower() if ch.isalnum() else "_" for ch in rel)
    return f"{prefix}_{suffix}_test"


def run_gleam_targets() -> None:
    subprocess.run(["gleam", "test", "--target", "erlang"], cwd=ROOT, check=True)
    subprocess.run(["gleam", "test", "--target", "javascript"], cwd=ROOT, check=True)


if __name__ == "__main__":
    sys.exit(main())
