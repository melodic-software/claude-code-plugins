# Audit Sub-Modes — Blast / Half-Rename / Orphans

`/rename-references audit` supports three sub-modes sharing the survey + triage pipeline from [audit.md](audit.md) but differing in input requirements, algorithm, and output format. Bare `/rename-references audit` (no sub-mode) defaults to **Blast** for backward compatibility.

| Sub-mode | Charter | Pair required? | Output |
|---|---|---|---|
| `audit blast` | Pre-rename impact: counts + per-file + bucket distribution | Optional (smart-default if absent) | Inline report (no file artifact) |
| `audit half-rename` | Find files containing BOTH old AND new (incomplete-rename hygiene) | Required | Inline table grouped by file |
| `audit orphans` | Refs at old name OR vanished path AFTER rename | Required (single-token rejected) | Two sub-tables: orphan + stale-but-functional |

Override flags `--include-historical`, `--include-memory`, `--include-plan-docs` apply to all three sub-modes; `--include-bare-token` applies to Blast, Half-rename, and the base audit path, but **not to Orphans** (see the table's note — Orphans sweeps only Forms 1 and 3, so it has no bare-token residue). `--include-plan-docs` and `--include-bare-token` are **audit-mode only** — apply mode rejects both with an explicit error. The mode-override flags `--container` / `--identifier` apply to every sub-mode and to apply mode, and are mutually exclusive.

---

## Audit Blast

**Purpose:** pre-rename impact preview. Inform go/no-go before committing edits. Cheaper than `preview` mode (no Edit-phase planning) — surfaces counts, bucket distribution, top-affected files.

**When to invoke:**

- User asks "how big is this rename?"
- Pre-rename impact analysis on uncertain blast radius
- After `git mv` to size the post-move sweep

**Inputs:**

| Form | Behavior |
|---|---|
| `/rename-references audit blast` (no args) | Smart-default detection per `SKILL.md` (conversation / git R-lines / paired D+??) |
| `/rename-references audit blast <old>` | Single-token reverse mode — sweep without `<new>`; report still useful for pre-rename radius |
| `/rename-references audit blast <old> to <new>` | Explicit pair |

**Algorithm:** run the full pattern library from [patterns.md](patterns.md) via the Grep tool for match facts, then apply triage from [triage.md](triage.md). Phases 1–3 (Detect → Survey → Triage) follow [audit.md](audit.md). NO Edit phase. NO file artifact.

**Output format:** identical to audit.md "Phase 4: Report". Counts table + top-5 affected files + pattern-form breakdown. Inline only.

**Defaults / aliasing:** bare `/rename-references audit` (no sub-mode keyword) routes to blast — Blast preserves the original audit behavior verbatim.

**Why no file artifact:** Beck (Tidy First, 2024) and Fowler (Refactoring, 2nd ed.) explicitly reject upfront-analysis artifacts in favor of inline IDE Find Usages. Inline is the right primitive; a plan-file artifact is deferred until cross-team review demand surfaces.

---

## Audit Half-Rename

**Purpose:** detect incomplete rename state — files mentioning BOTH old AND new identifier. Common after partial PR work or interrupted `/rename-references` apply runs. di Penta et al. (IEEE TSE 2020): ~80% of code smells (incl. half-renames) persist indefinitely once introduced — early detection prevents calcification.

**When to invoke:**

- After a partial rename PR was merged but left stragglers
- Mid-rename pause: "did I miss anything?"
- Pre-PR safety check post `/rename-references <old> to <new>` apply mode

**Inputs:**

| Form | Behavior |
|---|---|
| `/rename-references audit half-rename <old> to <new>` | Required — both names needed for intersection algorithm |
| `/rename-references audit half-rename` (no pair) | Smart-default per SKILL.md; if zero candidates, error: "audit half-rename requires a rename pair (old → new)" |

**Algorithm:**

1. Sweep for `<old>` and `<new>` separately with the pattern library from [patterns.md](patterns.md) via the Grep tool; intersect per file — files with hits for BOTH tokens are in half-rename state
2. **English-verb blocklist filter** (judgment): if either token is in the blocklist (per [triage.md](triage.md)), elevate matches to ambiguous bucket — bare `confirm` + bare `verify` co-occurrence in prose is NOT half-rename evidence. Require at least one high-signal match per token (e.g. slash-token `/confirm` AND slash-token `/verify`)
3. Report files in descending order of total hits (old + new)

**Output format:**

```text
Half-rename audit: <old> ⇆ <new>
Files containing BOTH (incomplete rename state):

| File                                    | Old hits | New hits | Sample                                       |
|-----------------------------------------|----------|----------|----------------------------------------------|
| skills/foo/SKILL.md                      | 3        | 2        | "...→ <old> →..." (line 12)                 |
| docs/conventions.md                      | 1        | 4        | "use <new> instead of <old>" (line 45)      |

<N> files in half-rename state. Run /rename-references <old> to <new> to complete.
```

**Edge cases:**

- **Zero half-rename hits:** report "No half-rename state detected — clean." Positive signal, not error. Common when prior rename was thorough
- **Self-reference (plan docs):** the active plan/work-notes document mentions BOTH names by design (documenting the rename). Auto-excluded by default; `--include-plan-docs` opts in (read-only — apply mode block applies)
- **Documentation references:** memory files often describe historical renames — both old + new appear by design. Memory paths auto-excluded by default

**No Edits.** Half-rename is an audit — once findings reported, user invokes `/rename-references <old> to <new>` apply mode if they want to fix.

---

## Audit Orphans

**Purpose:** find references THIS rename would orphan. NOT a general dead-ref check — that belongs to a repo-wide codebase-audit or link-check workflow. Scope is strictly post-rename hygiene.

**When to invoke:**

- After `/rename-references <old> to <new>` apply phase, double-check no file paths went stale
- After `git mv <old-path> <new-path>`, sweep for `[text](<old-path>)` markdown links and similar
- Before declaring rename done: orphan check is final safety net beyond apply.md Phase 6 re-sweep

**Inputs:**

| Form | Behavior |
|---|---|
| `/rename-references audit orphans <old> to <new>` | Required pair |
| `/rename-references audit orphans <old>` (single token) | **REJECTED** with error: "audit orphans requires a rename pair (old → new). Charter is post-rename orphan check, not general dead-ref scan. For a repo-wide dead-reference check, use a codebase-audit workflow or documentation link checker." |

**Algorithm:**

1. Sweep for `<old>` references using Form 1 (slash-token `\B/<old>\b`) and Form 3 (path `context/<old>.md`, `skills/<old>/`, `plugins/<old>`) from [patterns.md](patterns.md)
2. For each match, classify:
   - **Orphan (broken):** path-form match where path does not exist on disk after rename. Verify via Glob/Read. E.g. `[text](context/old.md)` matched but `context/old.md` was renamed to `context/new.md` — link now broken
   - **Slash-token orphan:** `/<old>` matched but no skill/command named `<old>` exists any more (skill renamed/removed)
   - **Stale-but-functional:** `<old>` matched, file still exists at old path. Rename was started but old artifact wasn't deleted. User decision: complete the rename or revert
3. Build two sub-reports

**Output format:**

```text
Orphans audit: <old> → <new>

Orphan (broken — refs point at vanished path/skill):
| Reference                              | File:Line                  | Reason                          |
|----------------------------------------|----------------------------|----------------------------------|
| [text](context/old.md)                 | docs/guide.md:42           | path does not exist             |
| /old-skill                             | CLAUDE.md:128              | skills/old-skill/ gone          |

Stale-but-functional (refs at old name, file still exists):
| Reference                              | File:Line                  | Note                             |
|----------------------------------------|----------------------------|----------------------------------|
| skills/old/SKILL.md                    | docs/index.md:7            | rename incomplete; old still on disk |

<N> orphans, <M> stale-but-functional.
Suggest: /rename-references <old> to <new> to apply, OR git rm <old-path> to complete cleanup.
```

**Charter (strict):**

- Orphans audit is PAIR-DRIVEN — what THIS rename orphaned
- NOT general dead-ref check. Dead `/skill-that-was-never-created` references belong to a repo-wide codebase-audit workflow
- NOT general dead-link check. Broken `[text](unrelated-path)` = doc lint territory
- Charter boundary preserves single responsibility — adding a general scan would conflate rename hygiene with codebase auditing

**Edge cases:**

- **Both old and new paths exist:** rename was duplicative (file COPIED not MOVED). Report as stale-but-functional with note "duplicate — old + new both present"
- **Slash-token in conversation logs:** memory paths auto-excluded by default; `--include-memory` overrides

**No Edits.** Orphans audit reports findings; user fixes via `/rename-references <old> to <new>` apply mode or `git rm`.

---

## Override flags

Six flags: four widen the sweep, two force the rename mode. The first three widening flags apply to ALL audit sub-modes (Blast / Half-rename / Orphans) and the
base audit.md path; `--include-bare-token` applies to every sub-mode except Orphans (see its row):

| Flag | Effect | Apply-mode availability |
|---|---|---|
| `--include-historical` | Sweep archived/completed work notes and frozen records of past work | Available |
| `--include-memory` | Sweep `~/.claude/projects/*/memory/*.md` and `MEMORY.md` indices | Available |
| `--include-plan-docs` | Sweep the active plan/work-notes documents that document THIS rename | **AUDIT-MODE ONLY** |
| `--include-bare-token` | Surface the bare-token residue that container-rename mode ([patterns.md](patterns.md) "Phase 0b") otherwise reports only as an aggregate count. Always lands **Ambiguous**, never Certain — the mode excluded it because bare-token position carries no signal for a container rename, and widening the report does not change that. **Not applicable to Orphans**, which sweeps only Forms 1 and 3 and so produces no bare-token residue to surface; passing it there is accepted and reported as not-applicable rather than silently returning the default result | **AUDIT-MODE ONLY** |
| `--container` | Force container-rename mode — rule 1 of the [patterns.md](patterns.md) "Phase 0b" ladder, skipping the evidence checks below it | Available |
| `--identifier` | Force identifier-rename mode. Mutually exclusive with `--container`; passing both is an error, not a precedence question | Available |

**Hardcoded apply-mode block on `--include-plan-docs`:** if action is `<old> to <new>` (apply) AND `--include-plan-docs` is in args, halt with error:

```text
Error: --include-plan-docs cannot be used in apply mode.
The active plan document records the rename — both old and new
names appear by design. Editing it would break the documentation
narrative. Use audit modes (audit blast / half-rename / orphans)
to inspect, then update the plan document by hand if needed.
```

**Why hardcoded, not warning:** the self-edit footgun is severe enough to block, not advise. Mitigation: AUDIT MODE remains available for inspection (read-only).

**Defaults preserved:** without any flag, auto-exclusions match the default behavior (plan docs, frozen historical notes, memory all skipped).

**Flag parsing:**

- Long-form only (no short aliases — clarity beats brevity for safety-critical flags)
- Position-agnostic: accepted before/after action keyword and before/after rename pair
- Multiple flags compose: `/rename-references audit blast /old to /new --include-historical --include-memory` is valid
- Unknown flags: error with usage hint, never silently ignore

**Cross-references:**

- Auto-exclusion source-of-truth: `../SKILL.md` "Auto-exclusions" + `triage.md` "Special case" sections
- Frozen-historical detection: use the consuming repository's work-notes status conventions (frontmatter status fields, archive directories) when present; otherwise treat clearly-archived paths as frozen
- Memory paths: `~/.claude/projects/*/memory/*.md` (cross-platform — POSIX path on Git Bash, Windows path elsewhere)

---

## Hand-off

After any audit sub-mode completes:

| Result | Suggestion |
|---|---|
| Blast: 0 matches | "No stragglers found. Safe to proceed (or rename target absent)." |
| Blast: matches found | Suggest `/rename-references <old> to <new>` (apply) or `/rename-references preview <old> to <new>` (dry-run) |
| Half-rename: 0 files | "No half-rename state — clean." |
| Half-rename: ≥1 file | Suggest `/rename-references <old> to <new>` to complete |
| Orphans: 0 orphans + 0 stale | "No orphans — rename is clean." |
| Orphans: orphans found | Suggest `/rename-references <old> to <new>` apply OR `git rm <stale-old-path>` per case |

Do NOT git add/commit/push automatically — report status; the user decides (the consuming repository's own commit policy governs).
