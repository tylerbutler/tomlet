# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.1 - 2026-06-07


#### Fixed

##### Exercise the release pipeline end to end

A no-op changelog entry to force a patch release so the auto-tag, publish, and SBOM-attestation workflows can be validated after the release-machinery fixes. No code or behavior changes.


## v1.1.0 - 2026-06-07


#### Added

##### Value-level read accessors for decoding nested data

`as_string`, `as_int`, `as_bool`, `as_float`, `as_date`, `as_time`, and `as_datetime` read scalars from a `Value` already obtained via `get`, and `value_get` descends into table- and array-shaped values by key or non-negative numeric index — so nested data can be decoded without hand-walking the entry assoc lists or returning to the document root.

##### Indexed descent into arrays and arrays of tables in `get`

`get` now follows a non-negative decimal index past an array or array-of-tables segment, so paths like `get(doc, ["packages", "0", "name"])` resolve without first fetching the container and walking it by hand. Typed indexed reads compose with the value-level converters, e.g. `get(doc, path) |> result.try(as_string)`.

##### `table_keys` helper to enumerate a table's top-level keys

`table_keys(doc, path)` returns the top-level keys of a standard or inline table in source order, without pattern-matching the table value and unwrapping each entry's key path by hand. Dotted keys and subtables collapse to their first segment, deduplicated. Missing paths yield `KeyNotFound`; non-table values yield `WrongType`.


#### Security

##### Generate and attest a CycloneDX SBOM during release

The release workflow now runs `licence_audit sbom` to produce a reproducible CycloneDX 1.6 SBOM, signs a SBOM attestation for the release source archive via `actions/attest`, and uploads both the SBOM and source archive to the GitHub Release.


## v1.0.0 - 2026-05-30


#### MajorRelease

##### Initial 1.0.0 stable release

Tomlet is ready for its first stable release as a Gleam library for parsing, editing, and writing TOML while preserving comments, key order, and formatting.


#### Added

##### Round-tripping TOML parser and writer for Gleam

Tomlet parses TOML 1.0.0 into an opaque document and writes it back out with comments, key order, and surrounding formatting preserved. It validates input as UTF-8 and rejects spec-forbidden bytes, including misplaced byte-order marks and control characters in comments. Typed accessors read common value types, and checked edit helpers set string, integer, boolean, and float values, remove values, and insert standalone comments. Edits that cannot be applied safely — unsupported structural values or conflicting writes — are rejected rather than corrupting the document, and every operation reports stable, typed parse and edit errors.

##### Public `tomlet.get` API for reading any TOML value through `tomlet.Value`

##### Typed date, time, and date-time accessors

`get_date`, `get_time`, and `get_datetime` read the opaque `Date`, `Time`, and `DateTime` values, reporting failures through `GetError`.

##### Edit support for dates, times, arrays, inline tables, and arrays of tables

`date_from_string`, `time_from_string`, and `datetime_from_string` validate their input and produce the opaque `Date`, `Time`, and `DateTime` values, reporting invalid lexical forms as a `FormatError`. The setters `set_date`, `set_time`, `set_datetime`, `set_array`, and `set_inline_table` write these values at a key path, and `append_array_of_tables` appends a table to an array of tables, creating the array on first use.


