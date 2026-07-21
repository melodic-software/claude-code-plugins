---
name: audit-automation-gaps
description: "Audit a repo's Claude Code automation landscape (hooks, MCP servers, skills, subagents, scheduled tasks) against the enforcement hierarchy, producing PASS/REJECT/CONDITIONAL verdicts backed by evidence — the default verdict is REJECT because most gaps are already covered by compiler/analyzer/build-time checks. Use when: 'audit automations', 'what automations should we add', 'are we missing any hooks', 'hook gap analysis', 'should I add an MCP server for X'; pass --implement to apply approved items, or filter by category (hooks|mcp|skills|subagents|scheduled)."
argument-hint: "[--recommend-only] [--implement] [category] — category: hooks|mcp|skills|subagents|scheduled|all (default: all)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Automation inventory: !`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/scripts/inventory.sh" 2>/dev/null || echo "inventory unavailable"`

## Purpose

Audit the repo's automation landscape and identify genuine gaps — not surface-level "you don't have X"
observations, but evidence-backed gaps where no mechanism in the enforcement hierarchy covers the
concern.

**Design principle**: most "missing automation" gaps are already covered by higher enforcement levels
(compiler, analyzers, build-time checks, architecture tests, behavioral rules). This skill's job is to
prove a gap exists before recommending a solution — the default verdict is REJECT, not PASS.

**The enforcement hierarchy** (strongest first): compiler settings → static analyzers/linters →
architecture tests → unit/integration tests → git hooks → Claude Code hooks → code review →
documentation/behavioral rules. A consuming repo that documents its own hierarchy in `CLAUDE.md` or
rules files overrides this default ordering — read and use theirs.

## Adapting to your environment (graceful degrade)

This skill is self-contained. Where a phase names an adjacent capability — a research skill, an
implementation-planning skill, a work-item tracker, an outcome verifier — treat it as optional: if
your setup provides an equivalent, use it; otherwise follow the inline guidance, which stands on its
own. Adjacent skills cover neighboring questions: the sibling `audit` skill (are the config FILES
correct?) and the `audit` skill in the `claude-memory` plugin (is the instruction layer healthy?).

## Arguments

Parse `$ARGUMENTS` for:

- **`--recommend-only`**: Run evaluation phases only — skip implementation. Default behavior
- **`--implement`**: After presenting validated recommendations, implement user-chosen items sequentially
- **Category filter** (`hooks`, `mcp`, `skills`, `subagents`, `scheduled`): Limit to a specific automation type. Default: `all`

## Track progress

For any deep-dive run (Phases 1-4), keep a phase checklist and tick each phase + every anti-noise
doctrine check as it completes — either in-response or by copying
`${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/templates/checklist.md` into wherever the consuming
repo keeps working task notes. Phase 4 is SKIPPED in default `--recommend-only` mode.

## Phase 1: Discover Candidates (Self-Generated)

Analyze the current automation landscape directly — no external recommender dependency.

### 1.1 Inventory Current State

Run `bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-automation-gaps/scripts/inventory.sh"`, then read:

| What | Source |
|------|--------|
| Hooks | `settings.json` → `hooks` section + hook script paths |
| MCP servers | `.mcp.json` + `settings.json` → `disabledMcpjsonServers` |
| Permissions | `settings.json` → `permissions` (deny/ask/allow) |
| Enforcement | Ecosystem-specific build config (`<root-build-config>` — e.g. `Directory.Build.props` for .NET, `pyproject.toml` for Python, `package.json` for TS/JS), `.editorconfig` (top 20 lines), any enforcement-hierarchy section in the repo's own instruction files |
| Codebase shape | File counts per language: `find . -name "*.cs" \| wc -l`, same for `.py`, `.ts`, `.sh`, `.ps1` |
| Incident history | `git log --oneline \| wc -l` for baseline, `git log --oneline -50` for recent activity |

### 1.2 Gap Analysis

For each automation category, systematically check for gaps using the category-specific checklists in
[context/gap-analysis.md](context/gap-analysis.md) — Hooks (formatter exists? fast enough? higher
enforcement already covers?), MCP Servers (configured? CLI equivalent? service in use yet?), Skills
(skill exists? frequency? simpler mechanism?), Subagents (value over hook/skill? isolation help?
plugin exists?), Scheduled (tracked in the repo's work-item tracker? Dependabot/CI covers? right
durability model?).

### 1.3 Generate Candidate List

Produce a numbered list of candidates with category and one-line rationale. Target **5-10 candidates**
— cast a wide net, the quality gates will filter. Include borderline items; it's better to evaluate
and reject with evidence than to silently exclude.

## Phase 2: Deep-Dive Each Candidate

For each candidate, execute the evaluation workflow. **Batch the Explore phase** (read all configs
once), then evaluate candidates sequentially.

### 2.1 Explore (Local Codebase)

For each candidate:

- **Read the relevant config/code** — the specific files that would be affected
- **Check the enforcement hierarchy** — walk up from the weakest level (docs) to the strongest (compiler). Stop when you find coverage. Document which level covers it
- **Check incident history** — `git log --grep` for related problems. Count incidents vs total commits for frequency
- **Measure performance** — if the candidate involves a CLI tool as a hook, time it:

```bash
time <tool-command> 2>&1 | tail -5
```

PostToolUse hooks must complete in <15-30s. Tools exceeding this are unsuitable for per-edit hooks.

### 2.2 Research (Targeted, Parallel)

Launch **parallel research agents** for candidates that survive initial Explore (weren't immediately
disqualified by performance or existing enforcement). Group related queries to minimize agent count.

**Per-candidate research questions by type:**

| Type | Research Questions |
|------|-------------------|
| **Hook** | Tool per-file performance? Ecosystem standard formatter? Known hook compatibility issues? |
| **MCP Server** | Server stability? Auth requirements? CLI equivalent comparison? Known issues? |
| **Skill** | Existing solutions? Frequency justification? Similar skills in marketplaces? |
| **Subagent** | Can a hook/skill do this more deterministically? Is context isolation needed? |
| **Scheduled** | Platform requirements (CLI vs Desktop vs cloud)? Durability model? Existing coverage via Dependabot/CI/work items? |

Verify Claude Code mechanisms against official docs
([code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks),
[code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp)); use web search for tool
performance and community practices. Prefer direct research in main context over agent delegation
when capacity allows.

### 2.3 Vet / Validate (Quality Gates)

A candidate **fails** if ANY gate triggers:

| Gate | Condition | Evidence Required |
|------|-----------|-------------------|
| **Already enforced** | A higher enforcement hierarchy level covers it | Name the level and mechanism |
| **Too slow** | Tool exceeds 30s for a PostToolUse hook | Timing measurement |
| **Not scriptable** | The mechanism can't be automated with available tools | Specific limitation cited |
| **Zero incidents** | Git history shows the problem has never occurred | Incident count + total commit count |
| **Already exists** | A skill, behavioral rule, or convention already handles it | File path and line |
| **YAGNI** | Low frequency (<5% of commits) AND low severity | Frequency calculation |
| **Platform mismatch** | Requires infrastructure the user doesn't have | Platform requirement cited |
| **Premature** | Depends on unfinished work (planned database, future CI) | What's missing cited |

These gates answer *should* we mechanize. Whether a candidate *can* be — and how far up the hierarchy
it climbs — is a separate enforceability question: the **Not scriptable** gate maps to reasoning-only
concerns, **Already enforced** to a deterministic finding already escalated.

Produce a verdict per candidate:

- **PASS** — clears all gates, provides genuine value
- **CONDITIONAL PASS** — value exists but only under specific conditions (document the condition)
- **REJECT** — fails one or more gates (cite which gates and evidence)

## Phase 3: Present Results

### Summary Table

```markdown
| # | Candidate | Category | Verdict | Key Evidence |
|---|-----------|----------|---------|--------------|
| 1 | ... | Hook | REJECT | [gate]: [evidence] |
| 2 | ... | Skill | PASS | No existing coverage, [frequency]% of commits |
```

### Detailed Verdicts

For each candidate, provide:

- **Verdict** with gate results
- **Evidence** (timing data, git history counts, enforcement mechanisms found)
- **For PASS/CONDITIONAL PASS**: implementation plan (files to change, effort estimate, test strategy)

**Order by value/impact** — highest value first. Value = frequency × severity × ease of implementation.

### Maturity Assessment

End with a one-paragraph assessment of the repo's automation maturity: what's well-covered, what the
genuine gaps are (if any), and whether the current automation investment level is appropriate for the
project stage.

If items pass: "Which items would you like to implement? I'll work through them sequentially."

If no items pass: State that clearly — a clean bill of health is a valid outcome.

## Phase 4: Implement (if `--implement` or user requests)

For each user-selected item:

1. **Explore** — re-read current state (may have changed since evaluation)
2. **Research + Validate** — verify the implementation approach against current docs
3. **Plan** — detailed implementation steps
4. **Implement** — execute with incremental validation and commit checkpoints
5. **Test** — verify the automation works (run hooks, test skills, etc.)
6. **Review** — self-review for consistency with existing patterns
7. **Verify** — build/test the repo if code changed, confirm no regressions

Route steps 2-7 through the consuming environment's own workflow skills when it has them; the inline
steps stand on their own otherwise.

## Quality Principles

Lessons from evaluation sessions:

1. **The enforcement hierarchy is your first check.** Most "gaps" are covered by the compiler-through-git-hooks levels
2. **Measure, don't assume.** Time every tool before recommending it as a hook. A formatter looks perfect until you measure 15+ seconds per file
3. **Check incident history.** Zero incidents across 100+ commits is strong evidence the problem doesn't exist in practice
4. **Behavioral rules are valid enforcement.** A rule in CLAUDE.md is legitimate coverage — not everything needs a hook or script
5. **YAGNI is a quality gate, not laziness.** Automation for a task at 4% frequency is premature
6. **Premature is worse than missing.** Adding a database MCP before a database exists, or scheduling before CI exists, creates maintenance burden for zero value
7. **A clean bill of health is a valid outcome.** Not finding gaps means the automation is mature — don't manufacture recommendations to justify the audit
