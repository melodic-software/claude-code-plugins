#!/usr/bin/env bash
set -euo pipefail
# Seeds a CLI repo whose prose rules live in a contributor writing guide, with no STYLE.md.

mkdir -p docs/contributing src
cat >README.md <<'MD'
# tallyctl

tallyctl imports, syncs and exports household ledgers from the command line.

Install with `cargo install tallyctl`, then run `tallyctl --help`.
MD
cat >CONTRIBUTING.md <<'MD'
# Contributing to tallyctl

- Open an issue before a large change.
- Run `cargo test` before you push.
- Prose (README, docs, release notes) follows our writing guide: [docs/contributing/writing.md](docs/contributing/writing.md).
MD
cat >docs/contributing/writing.md <<'MD'
# Writing guide

These rules cover the README, everything under docs/, and release notes.

## General

- Address the reader as "you".
- Name commands and flags exactly as the CLI spells them, in code font.
- Use sentence case for headings.

## Release notes

- Group entries under these headings, in this order: `### Breaking changes`, `### New`, `### Fixed`.
  Leave out a heading that has no entries.
- Leave out commits that change only CI, tests, refactors, dependency versions, or docs.
- Start each entry with the command it affects, in code font.
- A breaking change says what to do instead, in the same entry.
MD
cat >src/main.rs <<'RS'
fn main() {
    println!("tallyctl");
}
RS
