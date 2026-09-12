---
outcome: early-exit
tier: B
reason: two new files with one localized contract each (a validator CLI and two userConfig keys); no new module boundary, no package topology change, no data model beyond the upstream case format the CLI already owns
---

# Design resolution: plugin-evals

Tier B. The upstream case format (`prompt.md` frontmatter, `graders/*.md`, `case.yaml`) is a contract
Claude Code owns; this work introduces no types of its own beyond the three sketches below.

## Type sketch

### Static case validator (script, no model call)

```text
validate-cases <eval-dir> [--json]
  exit 0  no FAIL findings (WARN allowed)
  exit 1  at least one FAIL finding
  exit 2  usage error or unreadable eval dir
  stdout  one finding per line: <FAIL|WARN> <case>/<file>: <message>
```

FAIL tier mirrors what the binary itself rejects: unknown `prompt.md` frontmatter key, unknown grader
option, no grader, duplicate grader name, non-positive `weight`, `runs` outside 1-50, `max_turns` over 200,
`timeout_seconds` over 3600, `env` key not matching `EVAL_[A-Z0-9_]*`. WARN tier carries the documented
common mistakes (`target: files` when contents were meant, inline `(?i)`, an `llm` grader where a
deterministic type would do, a gated tool in `allowed_tools`, `file_exists` in a read-only suite).
Implemented in Python 3.8+ standard library with a bounded YAML-subset parser (scalars, flow lists and
mappings, block lists including lists of mappings, block mappings three deep). Anything outside the
subset is `FAIL <file>: frontmatter not parsed (<construct>); simplify or run the CLI`: the validator
fails closed rather than green-lighting what it did not read.

### Plugin user config (two keys, `plugins/evals/.claude-plugin/plugin.json`)

```json
"max_cost_usd":      { "type": "number",  "default": 5, "min": 0 }
"unlimited_cost":    { "type": "boolean", "default": false }
```

`unlimited_cost: true` drops `--max-cost-usd` from the invocation; the estimate is still shown and the run
starts without a confirmation prompt.

### Preflight report (the guide skill prints before any spend)

| Field | Values |
|---|---|
| `cli_version` / `floor_met` | `claude --version` output; true at 2.1.269 or later |
| `platform` / `sandbox_backend` | native Windows → absent; WSL2, Linux with bubblewrap plus socat, macOS → present; else unknown |
| `target_type` | `plugin`, `wrapped-skill`, `wrapped-agent`, `rules` (refused, routed to `claude-config:unhobble`) |
| `suite_tools` | `read-only` or the list of gated tools the cases request |
| `estimate_usd` | cases × runs × arms, plus 3 judge calls per paid grader per run, carried as "roughly" |
| `ceiling` | the user-config number, or `unlimited` |

### Pilot case (read-only)

```text
plugins/evals/evals/<case>/prompt.md      allowed_tools: [Read, Glob, Grep, Skill]; max_turns ≤ 10
plugins/evals/evals/<case>/graders/*.md   one outcome grader (regex or llm, arm: both) + one path grader
                                          (tool_used on Skill, excluded from scoring by design)
```
