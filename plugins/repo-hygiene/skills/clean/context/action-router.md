# clean action router — menu, aliases, smart default

SKILL.md carries the action table headline; this file carries alias resolution, the bare-invocation menu, and confirmation gates.

## Canonical actions (sentence-oriented)

| Action | Say it as… | Removes / does | Risk | `--apply` without user OK? |
| --- | --- | --- | --- | --- |
| `scan` | "Show what's reclaimable" | Read-only inventory | Safe | N/A (no mutation) |
| `caches` | "Clear tool and linter caches" | `.pytest_cache/`, `.ruff_cache/`, `__pycache__/`, … | Low | **Never** |
| `build` | "Clear build output and logs" | `bin/`, `obj/`, `dist/`, dotnet clean driver, … | Low | **Never** |
| `git` | "Prune stale git metadata" | `worktree prune`, `remote prune`, `gc`, branch audit | Low | Prune/gc only after user OK; branch delete always opt-in |
| `tree` | "Reset working tree like a fresh pull" | `fetch` + `reset --hard` upstream + `clean -fdx` (default-preserve secrets/deps/skill-data; `--include-deps` / `--include-secrets` to widen) | **Destructive** | **Never** |
| `tree-batch` | "Reset all my repos like a fresh pull" | `tree` across a repo set behind one gate; separator-agnostic skip list; dirty/unpushed skipped unless `--include-dirty` | **Destructive** | **Never** |
| `all` | "Sweep caches, build artifacts, and git hygiene" | `build` + `git` (not `tree`) | Medium | **Never** |

**Neither `tree` nor `tree-batch` is part of `all`.** One mistaken sweep must not run a `reset --hard`. (`tree` itself now preserves `.env`, `node_modules/`, `.venv/` by default — see `reference/cleanup-config.md` "tree".)

## Token resolution (script)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/resolve-clean-action.sh <tokens...>
```

Emits `Action: <canonical|menu>`. Single-token aliases:

| Tokens → | Action |
| --- | --- |
| `scan`, `inventory`, `space`, `audit`, `report`, `show` | `scan` |
| `cache`, `caches`, `linter-caches`, `linter` | `caches` |
| `build`, `artifacts`, `artifact`, `bin`, `obj`, `output` | `build` |
| `git`, `branches`, `branch`, `prune`, `gc` | `git` |
| `tree`, `fresh`, `fresh-pull`, `fresh-pull-state`, `pristine`, `reset-tree`, `working-tree` | `tree` |
| `tree-batch`, `batch`, `fleet`, `multi-repo`, `reset-all` | `tree-batch` |
| `all`, `sweep`, `everything` | `all` |

Multi-token phrase heuristics (when no single token matches): `reset all`, `all my repos`, `every repo`, `across repos`, `ghq list` → `tree-batch`; `fresh pull`, `fresh clone`, `reset to origin`, `wipe ignored` → `tree`; disk-space phrases → `scan`; stale/merged branch phrases → `git`.

Conflicting tokens → `menu`.

## Bare invocation (empty `$ARGUMENTS`)

1. **Survey** — conversation triggers, `git status --porcelain`, pre-computed context block.
2. **Resolve** — `resolve-clean-action.sh` on `$ARGUMENTS`; if empty, infer from conversation phrases above.
3. **Route:**
   - **High-confidence match** → run that action starting with dry-run / scan (never jump straight to `--apply`).
   - **No match** → present the action table (this file § "Canonical actions") and `AskUserQuestion` with one option per row plus "Cancel".

Default when still unsure after one question: **`scan`** (safest).

## Confirmation matrix (agent-owned verdict)

| Action | Pre-mutation step | User gate |
| --- | --- | --- |
| `scan` | Run `scan.sh` | None |
| `caches`, `build`, `all` | `preflight.sh` + tier scripts `--dry-run` (writes a manifest; emits `Manifest:` + `Summary: planned=N bytes=K`) | `AskUserQuestion` when preflight non-empty OR before `--apply` — surface the `bytes` reclaimable total; apply the same manifest (`--apply --manifest <path>`), which emits `Summary: removed=N failed=M bytes=K` and exits non-zero on failure |
| `git` | `git-prune.sh --dry-run`, `git-branch-audit.sh` | Before `--apply` prune; before any branch deletion |
| `tree` | `git-tree-reset.sh --dry-run` (always) | **Mandatory** `AskUserQuestion` before `--apply` (surface `PreserveDeps`/`PreserveSecrets`/`AheadCount`); a non-zero `AheadCount` or exit 4 needs explicit unpushed-loss confirmation before `--allow-unpushed`; `--include-secrets` is UNRECOVERABLE — confirm separately; never autonomous |
| `tree-batch` | `git-tree-reset-batch.sh --dry-run` (always) | **Mandatory** single batch-wide `AskUserQuestion` before `--apply` (surface the per-repo `Outcome`/`Reason`, `Summary`, and `UnmatchedSkip:`); one gate for the whole batch, never per repo; `--include-dirty` re-enables the data-loss vector — confirm separately naming the dirty repos, like `--include-secrets`; never autonomous. Detail: [git-tree-reset-batch.md](git-tree-reset-batch.md) |

Autonomous sessions (`CLAUDE_CODE_REMOTE`, `/loop`, `/schedule`): destructive tiers (`tree`, `tree-batch`, and `--apply` on caches/build/all) **abort** — same rule as preflight §1.5.

## Post-`tree` steps (emit, do not auto-run)

After a tree reset that removed dependencies, suggest reinstalling them with the project's own bootstrap/setup command, and re-validating the environment with whatever tooling the project uses, when MCP or build deps fail after the wipe.
