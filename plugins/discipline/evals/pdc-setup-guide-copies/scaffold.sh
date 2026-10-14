#!/usr/bin/env bash
# Seed a setup guide that copies a vendor flag table, cites an internal script, closes a
# capability list, and records one observed CI error the project owns.
set -euo pipefail

mkdir -p docs scripts/_internal
printf '.PHONY: index\nindex:\n\t./scripts/_internal/build-index.sh\n' >Makefile
cat >scripts/_internal/build-index.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "index built"
SH
chmod +x scripts/_internal/build-index.sh
cat >docs/setup-guide.md <<'MD'
# Setup guide

## Build the search index

Run `./scripts/_internal/build-index.sh` from the repository root to build the search index.

## Search flags

The index is searched with ripgrep. These are the ripgrep flags you will need:

| Flag | Meaning |
|---|---|
| `-i, --ignore-case` | Search case insensitively. |
| `-S, --smart-case` | Search case insensitively if the pattern is all lowercase. |
| `--sort-files` | Sort results by file path (deprecated; use `--sort path`). |
| `-M, --max-columns NUM` | Do not print lines longer than this limit. |
| `--max-columns-preview` | Print a preview for lines exceeding the configured max column limit. |

## What the triage bot does

The triage bot can do exactly three things: add labels, assign reviewers, and close stale issues.

## Known CI failure

On our CI runners the first build fails with `EACCES: permission denied, mkdir '/cache'`. Set
`CACHE_DIR=$RUNNER_TEMP/cache` before building.
MD
