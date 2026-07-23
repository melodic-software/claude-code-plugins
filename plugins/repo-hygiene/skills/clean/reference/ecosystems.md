# Ecosystem Cleanup Definitions

Per-ecosystem teaching tables for the clean skill. Each entry includes command shape, cleanup tier, regeneration cost. Actual cleanup paths come from [cleanup-config.md](cleanup-config.md) ("Cleanup configuration" — `SKILL.md` references it too); this file is illustrative reference covering common ecosystem shapes.

**Important:** All `find` commands exclude `.venv/`, `node_modules/`, `vendor/` paths to avoid touching dependencies (see the protected-paths list in `cleanup-config.md`).

## .NET

| Target | Tier | Command | Safety | Regen cost |
|--------|------|---------|--------|-----------|
| bin/, obj/ | build | `find . \( -name .git -o -name node_modules -o -name .venv \) -prune -o -type d \( -name bin -o -name obj \) -print` then `rm -rf` each eligible path | Safe | `dotnet build` (~15s) |
| TestResults/ | build | `find . -type d -name TestResults -exec rm -rf {} +` | Safe | `dotnet test` |
| *.binlog | build | `find . -name '*.binlog' -delete` | Safe | Intentional capture only |
| App log dirs | build | Not swept generically (no portable path) — reclaim via the `tree` action | Safe | App sink creates on next run |
| `*.csproj.user` / `*.suo` | NEVER | — | Protected | VS / IDE debug profile preference |

No build-system clean driver runs (e.g. `dotnet clean`): the single pruned walk + `rm -rf` already removes every `bin/`/`obj/` output such a driver would, so invoking one first is pure overhead.

## Python

| Target | Tier | Command | Safety | Regen cost |
|--------|------|---------|--------|-----------|
| .pytest_cache/ | caches | `rm -rf .pytest_cache` | Safe | Next pytest run |
| .ruff_cache/ | caches | `rm -rf .ruff_cache` | Safe | Next ruff run |
| .mypy_cache/ | caches | `rm -rf .mypy_cache` | Safe | Next mypy run |
| `__pycache__/` | caches | `find . -type d -name __pycache__ -not -path '*/.git/*' -not -path '*/.venv/*' -not -path '*/node_modules/*' -exec rm -rf {} + 2>/dev/null` | Safe | Next Python import |
| .venv/ | NEVER | — | Protected | Runtime dependency |

## Node.js / TypeScript

| Target | Tier | Command | Safety | Regen cost |
|--------|------|---------|--------|-----------|
| .turbo/ | caches | `rm -rf .turbo` | Safe | Next turbo run |
| *.tsbuildinfo | caches | `find . -name '*.tsbuildinfo' -not -path '*/node_modules/*' -delete` | Safe | Next tsc --build |
| build/ , dist/ | build | Covered by the universal `bin/obj/build/dist/out/target` globs (see `cleanup-config.md` "build") | Safe | `npm run build` |
| node_modules/ | NEVER | — | Protected | Runtime dependency |

## IDE / Editor

| Target | Tier | Command | Safety | Regen cost |
|--------|------|---------|--------|-----------|
| .vs/ | caches | `rm -rf .vs` | Safe | VS regenerates on open |
| .vscode/ | NEVER | — | Protected | User config |
| .idea/ | NEVER | — | Protected | User config |

## Tool-specific

| Target | Tier | Command | Safety | Regen cost |
|--------|------|---------|--------|-----------|
| `.codex/logs/` | caches | `rm -rf .codex/logs` | Safe | Tool creates on next run |
| `.codex/config.toml` / `.codex/hooks.json` / `.codex/rules/` | NEVER | — | Protected | User config (in the protected-paths list) |

## Git

| Target | Tier | Command | Safety | Regen cost |
|--------|------|---------|--------|-----------|
| Stale worktree metadata | git | `git worktree prune` | Safe | None |
| Stale remote refs | git | `git remote prune origin` | Safe | None |
| Loose objects | git | `git gc --auto --quiet` | Safe | None |
| Branch audit + cleanup | git | the `git` action §4.2-4.7 | Audit default, deletion on confirmation | None |

## Protected (documented for scan reporting, never cleaned)

These appear in the scan report as "Protected" so user knows they exist but aren't cleanup candidates:

| Target | Why protected |
|--------|-------------|
| `.azure-cli/` / `.aws/` / `.gcloud/` | Cloud CLI credential bundles |
| `.env`, `.env.*`, `**/*.local.json`, `**/*.local.jsonc`, `**/*.local.md` | Environment secrets, local-only overrides |
| `node_modules/` | Runtime dependency |
| `.venv/` | Runtime dependency — Python |
| `vendor/` | Runtime dependency — Go modules / Ruby Bundler / PHP Composer |
| `.claude/skills/*/data/` | Hours of LLM synthesis work product (per-skill data convention) |
