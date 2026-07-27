---
name: audit-encapsulation
description: "Audit and remediate skill-encapsulation violations — external citations reaching into private surfaces inside `.claude/skills/<X>/` beyond the slash invocation. Use when: 'audit encapsulation', 'find skill leaks', 'skill boundary violation', 'who is reaching into <skill>', 'check skill boundaries', 'public API drift', or before refactoring a skill."
argument-hint: "[detect|fix|file-issues]"
user-invocable: true
disable-model-invocation: false
metadata:
  cheatsheet-stage: anytime
  cheatsheet-summary: Find external citations reaching into a skill's private surfaces
---

## Why this skill exists

Skills have a public API and a private body — the contract is `context/public-surface-contract.md` (bundled with this skill). External consumers — rules, agents, other skills, prose docs — must cite the public surface only. Editing the private body must not break external consumers because no external consumer is allowed to depend on it.

Without enforcement, private bodies leak. A rule file cites a path inside `<skill>/<some-subdir>/` because the content is convenient. The skill author refactors that subdir and the citation breaks silently — nothing fails the build, nothing greps red. The skill cannot evolve without coordinating with every leaker.

This skill provides the detection + classification + remediation discipline that closes that gap. Distinct concern from `/extract-ssot` (which detects content duplication via Rule of Three). Encapsulation violations are **single-violation matters** — Rule of Three does not gate them.

## Public surface matrix

The **Skill** surface — public = frontmatter + documented actions + args/flags + `/skill-name` slash invocation + the `scripts/` entry surface; private = everything else inside `.claude/skills/<X>/` (any OTHER subdirectory, all `*.schema.json` at any depth, all heading anchors) — is defined by `context/public-surface-contract.md`, including the data-file and scripts/ entry-surface carve-outs and the rip-and-paste-portability rationale. This skill audits cites against two more authoring surfaces the contract file does not enumerate:

| Surface | Public (cite externally) | Private |
|---------|--------------------------|---------|
| **Rule file** (`.claude/rules/*.md`) | All H2/H3 headings (entire file is shared vocabulary) | n/a |
| **Scheduled-automation prompt** (e.g. `.claude/routines/*.md`, if the consumer repo keeps them) | Top-of-file orchestration prompt | Internal exclusion lists, escape conditions |

### CI / git-hook sharing — pick a technique, not an exception

Workflows and git hooks needing logic that ALSO lives in a skill must not reach into skill internals. Pick a sharing technique by logic size — scripts/ facade (the skill exposes a public `scripts/<name>.sh` entry delegating to a private backend; hooks/CI invoke it), intentional duplication, plugin packaging, or headless `claude -p '/skill <action>'` invocation — per `context/public-surface-contract.md` "CI / git-hook consumption — entry surface, not internals".

The choice is per-cite. The bundled detect script is this plugin's detector; any hard gate (pre-commit hook, CI job, drift comparison against a vendored copy) is whatever the consuming repo wires around it.

## Action router

| Argument | Action | Purpose |
|----------|--------|---------|
| *(empty)* / `detect` | Default | Run detection grep, classify legal vs illegal, output violation table |
| `fix <file>:<line>` | Targeted remediation | Interactive Path A (promote-out) vs Path B (route-via-`/<skill>`) for one hit |
| `file-issues` | Batch | File one tracking work item per illegal hit in the consumer's tracker (e.g. `gh issue create`); emit a checklist if no tracker is available |

One action per response.

## Detection

`bash "${CLAUDE_SKILL_DIR}/scripts/detect.sh"` (`--apply-filters` optional)

- Any path into a subdirectory under a skill (`<X>/<any-subdir>/...` — regardless of subdir name) **except `scripts/`** (entry-surface carve-out, see below)
- Heading-anchor cites into `SKILL.md` body structure (`<X>/SKILL.md#<anchor>`)
- Any `*.schema.json` file at any depth (`<X>/<file>.schema.json`)

Legal external cites: bare `<X>/SKILL.md` path (discouraged but legal — natural-language + slash invocation is canonical), `<X>/<file>.json` data files at skill root (data-file carve-out), and `<X>/scripts/<entry>` entry scripts (entry-surface carve-out below).

**scripts/ entry-surface carve-out:** a skill's `scripts/` is its declared ENTRY surface per `context/public-surface-contract.md`. Harness / CI / hooks / workflow registries MAY path-cite a skill's entry scripts directly, so this inbound audit treats `<X>/scripts/...` cites as legal (like data files and bare `SKILL.md`) and never flags them. The skill-to-skill half of the asymmetry — a sibling SKILL.md citing another skill's `scripts/` stays slash-only — is out of this inbound audit's scope; a consuming repo that wants it enforced wires its own outbound gate.

The script scans the consumer repo it runs in: every `.claude/` child directory except `skills/` (self-citation domain; opt in via `--include-skills` for skill-maintenance review) and `worktrees/`, plus `.github/`, `docs/`, `.lefthook/`, root instruction/config files (`AGENTS.md`, `CLAUDE.md`, `README.md`, `CONTRIBUTING.md`, `lefthook.yml`), and `.claude/` top-level files — each filtered to what exists.

Or invoke the skill (the agent applies the filter taxonomy below):

```text
/audit-encapsulation detect
```

## Filter taxonomy — legal hits

`detect.sh` output is broad without `--apply-filters`. Use the filter taxonomy below for KIND-1/2/3; `--apply-filters` drops self-citation, plugin cache, and worktree paths.

| Filter | Hit shape | Why legal |
|--------|-----------|-----------|
| **Self-citation** | `.claude/skills/<X>/SKILL.md` cites `.claude/skills/<X>/<private-path>` | Intra-skill progressive disclosure (per `context/public-surface-contract.md`) |
| **KIND-1 meta-prose** | A rule or doc describing the encapsulation contract itself, OR documenting skill internals as a worked example / historical narrative / empirically-verified quirk | Self-referential explanatory prose, not citation |
| **KIND-2 forced-cite** | Another tool's semantics structurally require a verbatim path (a path-scoped rule trigger, a watch-glob, a drift-gate comparing against a vendored copy) | Citation IS the structural contract |
| **KIND-3 self-test** | This skill's / a hook's own regression fixtures embed literal violation strings | Exercise the filter; not real citations |
| **Mirror-automation** | A scheduled-automation prompt (e.g. `.claude/routines/<name>.md`) cites `.claude/skills/<name>/<private-path>` when its basename matches the skill name | Such prompts are cron arms of slash skills; mirror cites are part of the skill contract per the Public surface matrix |
| **Glob-config** | Skill-internal path used as a glob/filter in an exclusion list, hooks allowlist, or `.gitignore` — not a content `Read` cite | Path is structural filter syntax, not progressive-disclosure content (overlaps KIND-2; named separately for grading) |
| **Plugin cache** | `~/.claude/plugins/cache/<plugin>/...` | Upstream territory; foreign contract |
| **Worktree path** | `<worktree-root>/<n>/.claude/skills/<X>/...` (per the repo's worktree convention — e.g. `.worktrees/`, `.claude/worktrees/`, `.git/worktrees/`) | Worktrees share the tracked tree; same rules apply at the root path |

Hits that survive ALL filters = illegal. Report.

## Remediation paths

### Path A — Promote content out (caller wants the data)

Use when: the caller needs data the private file contains, and the data is genuinely shared vocabulary or constraint.

1. Apply `/extract-ssot verify` (the 6-gate refuse-fast check) to the private file's content
2. If it passes: extract the content into a shared rule or convention doc outside the skill (e.g. `.claude/rules/<topic>.md`, or extend an existing one)
3. Migrate the violator AND the original skill body to cite the new doc by heading
4. Delete or shrink the private file
5. Run `/rename-references` to sweep all syntactic forms

### Path B — Route via `/skill-name` invocation (caller wants the behavior)

Use when: the caller wants the skill's behavior, not the data. A reference into the private body is a workaround because the skill has no public action covering the use case.

1. Identify which skill action would deliver the desired behavior
2. If the action exists: rewrite the caller to invoke `/<skill-name> <action> <args>`
3. If the action does NOT exist:
   - Surface the gap to the user as a side note
   - File a tracking work item in the consumer's tracker for the missing public action
   - Leave the violation in place with a `# TODO(audit-encapsulation): missing /<skill> <action>` marker
   - Do NOT silently inline a workaround that makes the violation harder to find later

## Refactor pass discipline

When invoked from another skill's execute pass (e.g. `/extract-ssot execute`):

| Step | Action |
|------|--------|
| 1 | Run the detection grep against the caller list (or repo-wide) |
| 2 | Classify each match via the filter taxonomy: legal hit vs violation |
| 3 | For each violation, choose Path A (promote) or Path B (route via `/name`) |
| 4 | DO NOT preserve a violation because "it works today" — broken-window pattern |
| 5 | If Path B is needed but the action is missing, file a tracking work item and STOP — don't ship a partial fix |
| 6 | Run a `/rename-references` sweep after edits |

A surfaced violation is never silently ignored: fix it, capture it as a side note to the user, or file a tracking work item.

## Output shape (detect mode)

```markdown
# Encapsulation audit — N violations

## Violations
| File | Line | Cite | Suggested path |
|------|------|------|----------------|
| ... | ... | `<skill>/<dir>/<file>` | A or B |

## Filtered (legal — sample for verification)
| File | Line | Filter applied |
|------|------|----------------|

## Summary
- Total raw hits: M
- Filtered legal: M-N
- Illegal violations: N
- Path A candidates: a
- Path B candidates: b
- Missing public action (Path B blocked): c

## Recommended next step
`/audit-encapsulation fix <file>:<line>` for one-by-one OR `/audit-encapsulation file-issues` for batch work-item filing
```

## Anti-patterns guarded

- **Single-violation tolerance** — "it's only one place, no big deal." Encapsulation rot accumulates one violation at a time. Each is a binary contract break, not a Rule of Three threshold.
- **Silent workaround** — the caller inlines the data instead of routing through the skill, hiding the violation from future audits. Mitigated by the `# TODO(audit-encapsulation)` marker requirement.
- **Filter laziness** — flagging every grep hit without applying the filter taxonomy. False positives erode trust in the audit; users stop running it.
- **Wrong-direction Path A** — promoting skill-internal content to a shared doc when the caller actually wanted skill behavior. Mitigated by the "data vs behavior" classification step in Path A vs Path B selection.

## Sanity checks

| When | Check | Evidence |
|------|-------|----------|
| Pre-detection | `git ls-files` enumerable in scope | Bash output |
| Post-detection | Each raw hit classified per filter taxonomy OR illegal | Diff against filter table |
| Pre-fix | Path A vs Path B chosen with explicit data-vs-behavior reasoning | Session notes or plan artifact |
| Post-fix | Detection grep re-run; violation count decreased | Bash output |
| Post-fix | `/rename-references` sweep ran | Tool output |

## What this skill does NOT do

- Detect content duplication / Rule of Three clusters → `/extract-ssot`
- Enforce code-side public/private (TypeScript `export`, .NET `internal`, Python `_prefix`) → language-level tooling (compiler, lint)
- Refactor skill bodies that ARE legitimately self-contained (no external violations) → general refactoring, out of scope
- File work items without classification — Path A vs Path B must be picked first
- Auto-fix without user review — each Path B route changes call-site invocation; the user inspects the diff

## Cross-references

- `context/public-surface-contract.md` — canonical definition of what's public vs private, both carve-outs, the violation-shape table, and the CI / git-hook consumption techniques
- `/extract-ssot verify` — 6-gate refuse-fast check for Path A "promote out" decisions
- `/extract-ssot execute` — writes the SSOT and sweeps citations after a Path A migration
- `/extract-ssot` — duplication-skill counterpart; an encapsulation violation is one of its failure modes (cross-cite)
- `/rename-references` — load-bearing multi-pattern sweep after any heading change

## Recheck triggers

| Condition | Action |
|-----------|--------|
| `context/public-surface-contract.md` changes | Re-sync the Public surface matrix here and the pattern comments in `scripts/detect.sh` |
| A new CI workflow or git hook needs skill logic | Pick a technique from `context/public-surface-contract.md` "CI / git-hook consumption — entry surface, not internals"; prefer a skill `scripts/` facade the hook invokes — no vendored copy |
| Violations recur across audits | Promote the `detect` action to a scheduled cadence in the consumer repo (e.g. `/loop` or `/schedule`) |
| Anthropic ships a native skill-boundary linter | Demote this skill to advisory or sunset it |
