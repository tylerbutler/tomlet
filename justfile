# Tomlet Gleam parser and corpus test tasks

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias l := lint
alias c := clean

# Default recipe
default:
    @just --list

# === DEPENDENCIES ===

# Download project dependencies
deps:
    gleam deps download

# === STANDARD RECIPES ===

# Compile the project (Erlang target)
build:
    gleam build

# Build with warnings as errors (Erlang target)
build-strict:
    gleam build --warnings-as-errors

# Build with warnings as errors (JavaScript target)
build-strict-js:
    gleam build --target javascript --warnings-as-errors

# Run tests on all targets
# Includes the upstream TOML corpus checks.
test: test-erlang test-js

# Run unit + corpus tests on the Erlang target
test-erlang:
    python3 scripts/run_corpus_tests.py --target erlang

# Run unit + corpus tests on the JavaScript target
test-js:
    python3 scripts/run_corpus_tests.py --target javascript

# Format code
format:
    gleam format src test

# Check formatting without making changes
format-check:
    gleam format --check src test

# Type check without building
check:
    gleam check

# Run the glinter linter
glint:
    gleam run -m glinter

# Run linters (formatting + glinter)
lint: format-check glint

# Remove build artifacts
clean:
    gleam clean

# === CHANGELOG ===

# Create a new changelog entry
change:
    changie new

# Preview unreleased changelog
changelog-preview:
    changie batch auto --dry-run

# Generate CHANGELOG.md
changelog:
    changie merge

# === DOCUMENTATION ===

# Build generated documentation
docs:
    gleam docs build

# === CI ===

# Full validation workflow
ci: format-check glint check test build-strict build-strict-js docs

alias pr := ci
alias cl := change
