# Development

This guide is for people contributing to Tomlet. For library usage, see
[`README.md`](./README.md).

## Setup

Install [mise](https://mise.jdx.dev/), then run:

```sh
mise install
mise exec -- just deps
```

`.mise.toml` defines the project tool versions. Use mise only to install tools
and set up the shell environment. Use [`just`](https://github.com/casey/just)
to run tasks and download Gleam package dependencies. With mise
[shell activation](https://mise.jdx.dev/getting-started.html#activate-mise),
run `just` directly; otherwise, use `mise exec -- just <recipe>`.

The shared setup action installs all tools from `.mise.toml` once per job in
CI and Publish. Each job has a separate runner. The test matrices override
Erlang and Node versions with `MISE_ERLANG_VERSION` and `MISE_NODE_VERSION`.
CI tests OTP 27 and 28; Gleam 1.18.1 emits Erlang syntax that OTP 26 cannot
compile. The local default is OTP 27.

## Common tasks

Run `just` to list available recipes.

```sh
just build              # compile the package
just test               # run unit tests and TOML corpus checks
just format             # format all Gleam files, including examples
just format-check       # check formatting without changing files
just lint               # check formatting and run glinter
just audit              # check dependency licences and vulnerabilities
just ci                 # run the full validation workflow
```

Short aliases are also available: `just b`, `just t`, `just f`, `just l`,
`just c`, and `just pr`.

CI uses `just format-check`. These formatting tasks cover the full tree,
including examples, to match the check that Trellis runs before publication.

## Dependency audits

`just audit` runs `licence_audit check --checks=all` with the pinned
`1.0.0-rc.3` release candidate. `just ci` and the CI dependency audit job run
the same command. The audit includes production and development dependencies.

The policy in `[tools.licence_audit]` in `gleam.toml` allows Apache-2.0, MIT,
BSD-2-Clause, BSD-3-Clause, and ISC. The gate blocks high, critical, and
unknown-severity advisories. It reads licence declarations from locked,
checksum-verified Hex archives and queries OSV for vulnerabilities.
Network or metadata errors fail the gate. Review findings before changing
the policy or adding an exception.

`mise install` selects the self-contained licence_audit binary for your
platform. It bundles its own Erlang runtime, so the audit does not depend on
the project's OTP version. If you installed this version as an escript
before, replace it with `mise install --force github:tylerbutler/licence_audit`.

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
   attaches an SBOM and source archive to the Release. The workflow creates
   an SBOM attestation for the archive and build-provenance attestations for
   the archive and SBOM document. These attestations cover the uploaded
   source artifacts, not the Hex package bytes.

## Before opening a PR

Run:

```sh
just ci
```

Also check that user-facing documentation reflects any public API or behavior
changes. Keep development-only details in this file so `README.md` stays focused
on package users.
