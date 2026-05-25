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

# === STANDARD RECIPES ===

# Compile the project
build:
    gleam build

# Run tests
# Includes the upstream TOML corpus checks.
test:
    gleam test
    python3 scripts/run_corpus_tests.py

# Format code
format:
    gleam format src test

# Run linter
lint:
    gleam format --check src test

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

# Full validation workflow
ci: format lint test build

alias pr := ci
alias cl := change
