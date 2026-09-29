# Precompute injection sweep status (#3544)

Audit date: 2026-09-28 (main @ post-#4774). The 2026-08-31 fleet audit asked to inject
unconditional dependency probes into the `*:setup` family and perform five injection
consolidations.

## Verdict

**Already landed on main** for the sweep table and consolidations named in #3544:

| Target area | Status on main |
|---|---|
| `claude-config:setup`, `bash-format:setup`, `context-budget:setup`, `repo-hygiene:setup` (ghq only; git stays body-probed per #1619) | Pre-computed `command -v` rows present |
| `actionlint` / `typos-format` / `go-format` / `eol-normalizer` / `ai-briefing:setup` | Pre-computed probes present |
| `guardrails` / `context-guard` / `rate-limit-guard` / `ruff-format` / `biome-format` / `powershell-format` / `markdown-format:setup` | `jq` probe injected |
| `playwright:setup`, `firecrawl:setup` | CLI probes injected |
| `verification` / `discovery` / `planning:setup` | `.claude/topic-docs.yaml` pre-read injected |
| `knowledge:video-digest`, `knowledge:course-digest` | Homogeneous dependency block in one ` ```! ` fence |
| `claude-memory:audit` | `audit-spine.sh` single multi-stat call |
| `claude-ops:observability`, `claude-ops:lanes` | Merged probe lines per CHANGELOG |

## Intentional exclusions (unchanged)

- Git-bearing compound probes in setup skills (#1619 harness / worktree isolation).
- `$`-expansion in injected commands (#1687).
- Conditional or network probes (`plugin-quality` `gh auth`, `mutation-testing` rev-parse targets, `disk-hygiene` python resolution).

No further code changes required for #3544 unless a new setup skill ships without precompute.
