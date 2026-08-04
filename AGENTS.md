# AGENTS.md

Orientation for a coding agent working in this repository. It complements the
repository's own `README.md`: the README is written for people (what the
project is, how to build and run it, who owns it), while this file is the
agent-facing companion. Read the README first for repository shape and the
commands that validate a change.

## Synced standards are overwritten, not edited here

This repository's lint, formatting, and repository-hygiene configuration is
synchronized from `melodic-software/standards`. Any file that standards marks
as `managed` for this repository is replaced on the next sync, so a local edit
to such a file is silently lost. When one of them is wrong, fix the cause
upstream in `melodic-software/standards` and let the sync carry the correction
back — never patch the materialized copy here.

## Stage explicit paths

Stage the specific files a change touches. Never `git add -A` or `git add .`:
a blanket stage can sweep in synced, generated, or unrelated files you did not
mean to commit.

## Pull requests

- Title pull requests with [Conventional Commits](https://www.conventionalcommits.org/).
- Resolve every review thread before merging; an unresolved thread marks a
  finding that has not yet been addressed.

## Cursor Cloud specific instructions

This repo is a Claude Code plugin marketplace, not a long-running service: the
"applications" are the CI validation scripts, the plugin contract tests, and the
one bundled Node MCP server under `plugins/miro`. There is no server to keep
running. The toolchain, the exact lint/test/validate/build commands, and the CI
tool inventory are already documented — read `README.md`,
[`docs/MIGRATION-PLAYBOOK.md`](docs/MIGRATION-PLAYBOOK.md) ("Local development
loop"), [`docs/CLOUD-SESSIONS.md`](docs/CLOUD-SESSIONS.md), and
[`.github/workflows/ci.yml`](.github/workflows/ci.yml). Notes below cover only
the non-obvious VM caveats a fresh Cursor Cloud agent needs.

- **Node version / PATH shadowing (non-obvious).** The repo pins Node via
  `.node-version` (24.18.0), installed through `nvm`. The exec-daemon prepends
  `/exec-daemon` (Node 22) to `PATH` *after* `~/.bashrc` runs, so it shadows
  `nvm`. The fix is a trailing `PATH` prepend in `~/.bashrc` (already applied and
  baked into the VM snapshot) that puts the pinned Node bin — plus
  `/workspace/node_modules/.bin` (the `claude` CLI and Biome) and `~/.local/bin`
  (CI hygiene binaries) — ahead of `/exec-daemon`. If a fresh VM ever reverts to
  Node 22, re-run the version-pin activation via `nvm install "$(cat
  .node-version)" && nvm alias default "$(cat .node-version)"`.
- **`FORCE_COLOR=0` breaks output-parsing tests (non-obvious).** The daemon sets
  `FORCE_COLOR=0`, which the Rust `anstream` crate (used by `ruff`, hence the
  `ruff-format` plugin) treats as "force color ON", overriding `NO_COLOR=1` and
  injecting ANSI codes that make color-sensitive contract tests fail. `~/.bashrc`
  `unset FORCE_COLOR`s to fix this; keep that unset when running tests.
- **`awk` must be GNU awk (non-obvious).** `plugins/skill-quality`'s
  `check-skill.sh` check 21 uses interval regexes (`{0,3}`) that make the VM's
  default `mawk 1.3.4` panic (`REcompile() - panic`), silently skipping the check
  and failing its contract test. `gawk` is installed and set as the default `awk`
  (via update-alternatives); do not switch `awk` back to `mawk`.
- **Full CI toolchain provisioning.** `.claude/hooks/session-start.sh` is the
  repo's own idempotent bootstrap that installs the pinned CI tool inventory
  (`ruff`, `shellcheck`, `shfmt`, `actionlint`, `typos`, `editorconfig-checker`,
  `gitleaks`, `markdownlint-cli2`, `check-jsonschema`) into `~/.local/bin`. It is
  guarded by `CLAUDE_CODE_REMOTE`; to (re)provision those tools on this VM run
  `CLAUDE_CODE_REMOTE=true bash .claude/hooks/session-start.sh`. Its
  `$CLAUDE_ENV_FILE` PATH step is a no-op here (that var is Claude-Code-only), so
  PATH is handled by `~/.bashrc` instead.
- **Running things.** Tests: `scripts/run-plugin-tests.sh` (plugin contract
  suites; individual suites SKIP when an optional tool such as `duckdb`/`goimports`
  is absent), the shared `lib/*.test.sh` suites, and `scripts/*.test.sh`. Manifest
  and catalog validation (the marketplace "build") runs via
  `scripts/validate-plugins.sh` (needs `claude` on PATH). The bundled MCP server:
  `cd plugins/miro`, then
  `npm ci` once, and `npm run typecheck|lint|test|verify-bundle`; smoke-run the
  built bundle over stdio with `MIRO_API_TOKEN=... node dist/index.min.js`.
