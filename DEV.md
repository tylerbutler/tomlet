# Development

This guide is for people contributing to Tomlet. For library usage, see
[`README.md`](./README.md).

## Requirements

- Gleam
- Python 3, for TOML corpus test generation
- [`just`](https://github.com/casey/just), for common project tasks
- [`trellis`](https://trellis.tylerbutler.com/), for changelog fragments and releases
  (pinned in `.mise.toml`)

## Common tasks

Run `just` to list available recipes.

```sh
just build              # compile the package
just test               # run unit tests and TOML corpus checks
just format             # format src/ and test/
just lint               # check formatting
just ci                 # run the full validation workflow
```

Short aliases are also available: `just b`, `just t`, `just f`, `just l`,
`just c`, and `just pr`.

## Testing

`just test` runs `gleam test` and then the TOML corpus checks.

The corpus runner lives at `scripts/run_corpus_tests.py`. It clones the
upstream `toml-test` fixtures into `.toml-test/`, generates temporary Gleam test
modules, runs them on the supported Gleam targets, and removes the generated
files afterwards.

Useful targeted commands:

```sh
gleam test
gleam test --target javascript
python3 scripts/run_corpus_tests.py valid
python3 scripts/run_corpus_tests.py invalid
python3 scripts/run_corpus_tests.py
```

Valid TOML 1.0 corpus fixtures are expected to round-trip byte-for-byte unless a
fixture is explicitly listed in `ROUNDTRIP_UNSUPPORTED`. Invalid fixtures should
be rejected either by `tomlet.parse` or, for invalid byte encodings, by
`tomlet.parse_bytes`.

## Public API boundary

The supported public API is the top-level `tomlet` module. The modules listed in
`gleam.toml` under `internal_modules` are implementation details:

- `tomlet/ast`
- `tomlet/parser`
- `tomlet/path`
- `tomlet/lexer`

`tomlet/parser` is token-driven: `tomlet/lexer` wraps the `william` TOML lexer to
produce byte-offset-annotated tokens, and the parser assembles the AST from that
token stream while reusing the source-preserving value validators. TOML 1.1
features are gated by an internal `parser.Version`, threaded from the public
`tomlet.TomlVersion`.

Avoid documenting, depending on, or expanding internal modules as public API
unless the release intentionally changes that boundary.

When reviewing API changes, preserve this contract:

- Keep all user-facing additions in the top-level `tomlet` module.
- Keep implementation modules in `internal_modules` unless intentionally
  promoting them to public API.
- Public variant types are stable and matchable. Adding, removing, or renaming
  variants is treated as a breaking change.

## Changelog entries

User-facing changes should include a trellis changelog fragment:

```sh
just change Fixed "Reject dates with a zero month"
# or: trellis changelog new --kind Fixed --body "..."
```

Fragments are TOML files in `.changes/unreleased/`. Use one of the trellis
default kinds (`Breaking`, `Removed`, `Added`, `Changed`, `Deprecated`, `Fixed`,
`Performance`, `Security`, `Dependencies`). The kind sets the version bump. Write
entries for users of the package rather than for maintainers reading the diff.

Preview the next version with:

```sh
just changelog-preview
```

`CHANGELOG.md` is generated from the version sections in `.changes/tomlet/`. Do
not edit it directly.

## Releases

Releases are automated with trellis:

1. On each push to `main`, `trellis release pr` opens or updates a
   `release/pending` PR that bumps the version and updates `CHANGELOG.md`.
2. When that PR merges, `trellis tag create --github-release` creates the
   `vX.Y.Z` tag and GitHub Release.
3. The tag push runs `trellis publish --tag`, which publishes to Hex, and
   attaches an SBOM to the Release.

## Before opening a PR

Run:

```sh
just ci
```

Also check that user-facing documentation reflects any public API or behavior
changes. Keep development-only details in this file so `README.md` stays focused
on package users.
