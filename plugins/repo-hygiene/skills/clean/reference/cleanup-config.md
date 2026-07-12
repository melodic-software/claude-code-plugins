# clean cleanup configuration

Concrete per-tier cleanup targets and the protected-paths list. The Workflow (§1–§5 in `SKILL.md`) iterates these lists; `reference/ecosystems.md` carries the per-ecosystem teaching tables. Targets are generic across ecosystems and detected at runtime — no repo-specific layout is baked in.

Any file tracked by git (`git ls-files`) is off-limits regardless of glob match. Universal `find` exclusions for every scan/clean step: `-not -path '*/.git/*' -not -path '*/.venv/*' -not -path '*/node_modules/*'`.

## Cleanup targets (per tier)

Keyed by tier — `caches`, `build`, `git`. Each tier lists the paths/commands its workflow step acts on.

### caches — tool / linter caches (regenerate on next run)

- `.pytest_cache/`
- `.ruff_cache/`
- `.mypy_cache/`
- `**/__pycache__/`
- `.turbo/`
- `**/*.tsbuildinfo`
- `.vs/` — regenerable Visual Studio cache (distinct from protected `.vscode/`)
- `.codex/logs/` — Codex CLI log output (its `config.toml` / `hooks.json` / `rules/` stay protected — see below)

### build — build artifacts + compiled output + logs (includes caches)

Universal artifact directory globs:

- `**/bin/`, `**/obj/`, `**/build/`, `**/dist/`, `**/out/`, `**/target/`, `**/TestResults/`, `**/*.binlog`

Build-system clean driver (run before the glob removal in Workflow §3):

- .NET: `clean-build.sh` detects a `*.slnx` or `*.sln` at the repo root at runtime and runs `dotnet clean <solution> -v q`. If `dotnet` is unavailable or no solution is present, the driver is skipped; the universal globs still remove `bin/`/`obj/` directly.

App-specific runtime output (application logs written outside the universal artifact dirs) is **not** swept generically — no portable path exists. A consumer whose app writes logs to a non-artifact directory reclaims them through the `tree` tier (they are untracked/ignored) or their own gitignore + tooling.

### git — stale-state hygiene (write-safe)

Prune ops (safe mutations):

- `git worktree prune`
- `git remote prune origin`
- `git gc --auto --quiet`

Report-only (no mutation):

- `git branch --merged origin/<default-branch>` — default branch resolved at runtime (see `context/git-branch-cleanup.md` §4.2)

### tree — working-tree realignment (destructive; never in `all`)

Script: `git-tree-reset.sh`. Operations:

- `git fetch origin` (when `origin` remote exists)
- `git reset --hard <upstream>`
- `git clean -fdx` **with default-preserve excludes** (SSOT: `CLEAN_TREE_PRESERVE_*` in `scripts/lib/cleanup-paths.sh`, built into `-e` args by `clean_tree_preserve_args`)

Removes ignored and untracked **artifacts** while preserving the same three protected classes the selective tiers honor (below) by default:

- **Secrets / local config** (`.env*`, `*.local.json` / `.jsonc` / `.md`, IDE + cloud-cred + codex config) — removed only with `--include-secrets` (UNRECOVERABLE; extra confirmation).
- **Runtime deps** (`node_modules/`, `.venv/`, `vendor/`) — removed only with `--include-deps` (rebuildable).
- **Skill data** (`.claude/skills/*/data/`) — always preserved; no flag removes it.

**Why deps preserve by default — junction-proofing.** `git clean -fdx` traverses directory reparse points into tracked source. npm-workspace links live under `node_modules/`, so excluding `node_modules/` keeps git from ever descending into them — the default path cannot reach the link, let alone follow it. A post-clean restore guard (`clean_restore_tracked_deletions`) recovers any tracked file deleted this way as a backstop (safe because `reset --hard` ran first).

Gates: blocks on default branch unless `--force-default-branch`; aborts (exit 4) when HEAD is ahead of upstream unless `--allow-unpushed` (prevents silent loss of unpushed commits). Always dry-run before `--apply`. Files git could not delete (locked / in use) are reported (`Unremovable:`), not silently left.

## Protected paths — NEVER cleaned (any tier)

Three classes:

### Secrets / config / user data

- `.azure-cli/`, `.aws/`, `.gcloud/` — cloud / CLI credential bundles
- `.env`, `.env.*`, `**/*.local.json`, `**/*.local.jsonc`, `**/*.local.md` — local-only env / config overrides (gitignored by convention; `.env.example` IS tracked)
- `.vscode/`, `.idea/` — IDE user config (the regenerable `.vs/` cache IS cleanable — see caches tier)
- `**/*.csproj.user`, `**/*.suo` — .NET IDE user state (VS debug profile, sln docstates)
- `.codex/config.toml`, `.codex/hooks.json`, `.codex/rules/` — Codex CLI config (only `.codex/logs/` is cleanable — see caches tier)

### Runtime dependencies (deleting breaks running tools / MCP servers / skills)

- `**/node_modules/`
- `**/.venv/`
- `**/vendor/` — Go modules / Ruby Bundler / PHP Composer

### Skill-owned data directories

- `.claude/skills/*/data/` — user-generated synthesis (transcripts, summaries, accumulated LLM outputs). NEVER cleaned. Folder name MAY vary; the owning skill documents its data convention.

## Extending the protected set

The protected-path list above is enforced by the bash scripts, which do **not** read `CLAUDE.md` or `.claude/rules` (only a plugin's skill/agent components see those in model context). A consumer that needs to protect an additional path from the selective tiers relies on the git-tracked guarantee (any tracked file is never cleaned) or the `tree` tier's default-preserve classes. A declared per-consumer override for the script-enforced list is a known extension point, not yet exposed as configuration.
