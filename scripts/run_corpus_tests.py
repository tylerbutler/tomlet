#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


TOML_TEST_VERSION = "v2.2.0"
ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / ".toml-test"
TOML_TEST_REPO = CACHE / "toml-test"

MANIFEST_1_0 = "files-toml-1.0.0"
MANIFEST_1_1 = "files-toml-1.1.0"

VALID_GENERATED = ROOT / "test" / "tomlet" / "corpus_generated_test.gleam"
INVALID_GENERATED = ROOT / "test" / "tomlet" / "invalid_corpus_generated_test.gleam"
STRICT_GENERATED = ROOT / "test" / "tomlet" / "strict_1_0_generated_test.gleam"

# Valid TOML 1.1 corpus inputs that parse correctly but do not round-trip
# byte-for-byte. Each entry is a `valid/`-relative path (without the `.toml`
# suffix) and must include a comment explaining the formatting difference.
ROUNDTRIP_UNSUPPORTED = set()

# Fixtures listed in the TOML 1.1 valid manifest but not the TOML 1.0 valid
# manifest that nonetheless contain only TOML 1.0-compatible syntax (mostly the
# spec-1.1.0/* examples that simply renamed their spec-1.0.0/* predecessors).
# Strict TOML 1.0 mode correctly *accepts* these, so they belong in the strict
# accept suite rather than the strict reject suite. Entries are `valid/`-relative
# paths without the `.toml` suffix and are validated to be a subset of the
# 1.1-only valid set.
STRICT_1_0_COMPAT_IN_1_1 = {
    "spec-1.1.0/common-0",
    "spec-1.1.0/common-1",
    "spec-1.1.0/common-10",
    "spec-1.1.0/common-11",
    "spec-1.1.0/common-13",
    "spec-1.1.0/common-14",
    "spec-1.1.0/common-15",
    "spec-1.1.0/common-16",
    "spec-1.1.0/common-17",
    "spec-1.1.0/common-18",
    "spec-1.1.0/common-19",
    "spec-1.1.0/common-20",
    "spec-1.1.0/common-21",
    "spec-1.1.0/common-22",
    "spec-1.1.0/common-23",
    "spec-1.1.0/common-24",
    "spec-1.1.0/common-25",
    "spec-1.1.0/common-26",
    "spec-1.1.0/common-27",
    "spec-1.1.0/common-28",
    "spec-1.1.0/common-3",
    "spec-1.1.0/common-30",
    "spec-1.1.0/common-32",
    "spec-1.1.0/common-33",
    "spec-1.1.0/common-35",
    "spec-1.1.0/common-36",
    "spec-1.1.0/common-37",
    "spec-1.1.0/common-38",
    "spec-1.1.0/common-39",
    "spec-1.1.0/common-4",
    "spec-1.1.0/common-40",
    "spec-1.1.0/common-41",
    "spec-1.1.0/common-42",
    "spec-1.1.0/common-43",
    "spec-1.1.0/common-44",
    "spec-1.1.0/common-45",
    "spec-1.1.0/common-46",
    "spec-1.1.0/common-48",
    "spec-1.1.0/common-49",
    "spec-1.1.0/common-50",
    "spec-1.1.0/common-51",
    "spec-1.1.0/common-52",
    "spec-1.1.0/common-53",
    "spec-1.1.0/common-6",
    "spec-1.1.0/common-7",
    "spec-1.1.0/common-8",
    "spec-1.1.0/common-9",
}

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
        choices=["valid", "invalid", "strict", "all"],
        nargs="?",
        default="all",
        help="Corpus suite to run.",
    )
    parser.add_argument(
        "--target",
        choices=["erlang", "javascript", "all"],
        default="all",
        help="Gleam target(s) to run the corpus against.",
    )
    args = parser.parse_args()

    targets = ["erlang", "javascript"] if args.target == "all" else [args.target]

    # Run every requested suite even if an earlier one fails so the gate reports
    # the full picture in a single invocation. A non-zero exit is returned if any
    # suite failed on any target.
    ok = True
    if args.suite in {"valid", "all"}:
        ok = run_valid(targets) and ok
    if args.suite in {"invalid", "all"}:
        ok = run_invalid(targets) and ok
    if args.suite in {"strict", "all"}:
        ok = run_strict(targets) and ok
    return 0 if ok else 1


def run_valid(targets: list[str]) -> bool:
    repo = ensure_toml_test_repo()
    files = load_paths(repo, "valid", MANIFEST_1_1)
    write_valid_tests(repo, files, VALID_GENERATED)
    try:
        ok = run_gleam_targets(targets)
    finally:
        VALID_GENERATED.unlink(missing_ok=True)
    if ok:
        print(
            "toml-test TOML 1.1 valid corpus parse/round-trip checks succeeded from "
            f"{repo / 'tests' / 'valid'}"
        )
    else:
        print("toml-test TOML 1.1 valid corpus checks FAILED")
    return ok


def run_invalid(targets: list[str]) -> bool:
    repo = ensure_toml_test_repo()
    files = load_paths(repo, "invalid", MANIFEST_1_1)
    write_invalid_tests(repo, files, INVALID_GENERATED)
    try:
        ok = run_gleam_targets(targets)
    finally:
        INVALID_GENERATED.unlink(missing_ok=True)
    if ok:
        print(
            "toml-test TOML 1.1 invalid corpus checks succeeded from "
            f"{repo / 'tests' / 'invalid'}"
        )
    else:
        print("toml-test TOML 1.1 invalid corpus checks FAILED")
    return ok


def run_strict(targets: list[str]) -> bool:
    repo = ensure_toml_test_repo()
    valid_1_0 = load_paths(repo, "valid", MANIFEST_1_0)
    valid_1_1 = load_paths(repo, "valid", MANIFEST_1_1)
    only_1_1 = sorted(set(valid_1_1) - set(valid_1_0))
    write_strict_tests(repo, valid_1_0, only_1_1, STRICT_GENERATED)
    try:
        ok = run_gleam_targets(targets)
    finally:
        STRICT_GENERATED.unlink(missing_ok=True)
    if ok:
        print(
            "toml-test strict TOML 1.0 accept/reject checks succeeded from "
            f"{repo / 'tests' / 'valid'}"
        )
    else:
        print("toml-test strict TOML 1.0 accept/reject checks FAILED")
    return ok


def ensure_toml_test_repo() -> Path:
    expected_1_0 = TOML_TEST_REPO / "tests" / MANIFEST_1_0
    expected_1_1 = TOML_TEST_REPO / "tests" / MANIFEST_1_1
    if TOML_TEST_REPO.is_dir() and expected_1_0.is_file() and expected_1_1.is_file():
        return TOML_TEST_REPO

    if TOML_TEST_REPO.exists():
        shutil.rmtree(TOML_TEST_REPO)

    CACHE.mkdir(parents=True, exist_ok=True)
    try:
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
    except subprocess.CalledProcessError:
        if TOML_TEST_REPO.exists():
            shutil.rmtree(TOML_TEST_REPO)
        raise

    if not expected_1_0.is_file() or not expected_1_1.is_file():
        shutil.rmtree(TOML_TEST_REPO)
        raise SystemExit(
            f"toml-test checkout is missing {MANIFEST_1_0} or {MANIFEST_1_1}; "
            "remove .toml-test and rerun corpus tests"
        )

    return TOML_TEST_REPO


def load_paths(repo: Path, kind: str, manifest_filename: str) -> list[Path]:
    prefix = f"{kind}/"
    files = []
    file_list = repo / "tests" / manifest_filename
    if not file_list.is_file():
        raise SystemExit(f"missing corpus file list: {file_list}")
    for raw in file_list.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if raw.startswith(prefix) and raw.endswith(".toml"):
            files.append(Path(raw))
    return sorted(files)


def write_valid_tests(repo: Path, files: list[Path], generated: Path) -> None:
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
        f"generated {len(files)} TOML 1.1 valid corpus tests at {generated} "
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
        f"generated {len(files)} TOML 1.1 invalid corpus tests at {generated} "
        f"({rejected_count} string reject assertions, "
        f"{byte_rejected_count} byte reject assertions)"
    )


def write_strict_tests(
    repo: Path,
    valid_1_0: list[Path],
    only_1_1: list[Path],
    generated: Path,
) -> None:
    only_1_1_paths = {
        path.with_suffix("").relative_to("valid").as_posix() for path in only_1_1
    }
    assert_known_paths(
        "STRICT_1_0_COMPAT_IN_1_1", STRICT_1_0_COMPAT_IN_1_1, only_1_1_paths
    )

    # Fixtures that strict TOML 1.0 must accept: every valid 1.0 fixture, plus
    # those 1.1-listed fixtures whose content is still valid 1.0.
    accept = list(valid_1_0)
    accept.extend(
        path
        for path in only_1_1
        if path.with_suffix("").relative_to("valid").as_posix()
        in STRICT_1_0_COMPAT_IN_1_1
    )
    accept.sort()

    # Fixtures that strict TOML 1.0 must reject: the genuinely 1.1-only syntax.
    reject = [
        path
        for path in only_1_1
        if path.with_suffix("").relative_to("valid").as_posix()
        not in STRICT_1_0_COMPAT_IN_1_1
    ]

    generated.parent.mkdir(parents=True, exist_ok=True)
    with generated.open("w", encoding="utf-8") as out:
        write_gleam_prelude(out)
        for rel_path in accept:
            rel = rel_path.with_suffix("").relative_to("valid").as_posix()
            data = read_text_preserving_newlines(repo / "tests" / rel_path)
            out.write(f"pub fn {gleam_test_name('strict10valid', rel)}() {{\n")
            out.write(f"  let input = from_codepoints({gleam_codepoints(data)})\n")
            out.write(
                "  let assert Ok(_) = "
                "tomlet.parse_with(input, tomlet.Toml10)\n"
            )
            out.write("}\n\n")
        for rel_path in reject:
            rel = rel_path.with_suffix("").relative_to("valid").as_posix()
            data = read_text_preserving_newlines(repo / "tests" / rel_path)
            out.write(f"pub fn {gleam_test_name('strict10reject', rel)}() {{\n")
            out.write(f"  let input = from_codepoints({gleam_codepoints(data)})\n")
            out.write(
                "  let assert Error(_) = "
                "tomlet.parse_with(input, tomlet.Toml10)\n"
            )
            out.write("}\n\n")

    print(
        f"generated {len(accept) + len(reject)} strict TOML 1.0 tests at {generated} "
        f"({len(accept)} accept assertions, {len(reject)} reject assertions)"
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


def run_gleam_targets(targets: list[str]) -> bool:
    ok = True
    for target in targets:
        result = subprocess.run(["gleam", "test", "--target", target], cwd=ROOT)
        if result.returncode != 0:
            ok = False
    return ok


if __name__ == "__main__":
    sys.exit(main())
