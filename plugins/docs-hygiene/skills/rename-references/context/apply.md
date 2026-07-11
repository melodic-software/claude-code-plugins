# Apply Mode — Full Rename Workflow

Apply mode performs the complete rename: sweep → triage → user confirmation → Edit → re-sweep → handoff. Primary workflow when the user has decided to rename and wants the audit + edit done in one invocation.

Preview mode is the same workflow with the Edit phase replaced by "report planned edits." Use preview when the user wants to see exactly what would change before committing.

## Inputs

| Form | Behavior |
|---|---|
| `/rename-references <old> to <new>` | Apply mode — full pipeline through Edit + re-sweep |
| `/rename-references preview <old> to <new>` | Preview mode — same pipeline, planned edits reported instead of applied |

The natural-language parser per `SKILL.md` accepts `to`/`→`/`->`/`into` separators. Multi-word old/new is fine. Path renames (`a/old.md` to `a/new.md`) trigger extra path-form patterns.

## Workflow (7 phases)

### Phase 1: Detect

Parse the rename pair `(old, new)` from arguments. If parse fails, abort with parser examples from `SKILL.md`. Validate:

- `old` and `new` are non-empty
- `old != new`
- Path forms have matching extensions (warn if `a/old.md` to `a/new.txt`)

### Phase 2: Survey

Identical to audit-mode Phase 2 — run all patterns from [patterns.md](patterns.md) in parallel, aggregate into match list, apply auto-exclusions.

### Phase 3: Triage

Classify per [triage.md](triage.md) into Certain / Chain-context / Ambiguous / Excluded buckets.

### Phase 4: Confirm

Present bucket counts via the report template from [triage.md](triage.md) "Reporting bucket counts." Then gate the proceed/abort decision via `AskUserQuestion`.

Per-bucket confirmation flow:

**Certain bucket:**

- Show count + 1-2 example matches
- `AskUserQuestion`: "Auto-apply N matches?" — options: "auto-apply", "review one-by-one"
- Default: auto-apply (these forms have empirically near-zero false-positive rate)

**Chain-context bucket:**

- Show count + matches grouped in batches of up to 10 with 2-line context per match
- `AskUserQuestion`: "Apply N chain-context matches?" — options: "auto-apply all", "review one-by-one", "skip bucket"
- Default: review one-by-one (chain prose drift in user-facing docs is loud and embarrassing)

**Ambiguous bucket:**

- Show each match individually with 3 lines of surrounding context
- `AskUserQuestion` per match: "Rename this?" — options: "rename this", "skip this", "skip remaining ambiguous"
- ALWAYS one-by-one — batched confirmation defeats the safety purpose

If user picks "abort" at any prompt, halt and report partial state (no matches edited yet — Edit phase not started).

### Phase 5: Apply

For each accepted match (from Phase 4 user confirmations):

- Use Edit tool with exact old/new substitution
- For matches where the form requires partial replacement (e.g., chain prose `→ confirm →` becomes `→ verify →`), construct precise old_string and new_string
- Idempotency: running twice MUST be safe. Edit tool's `replace_all: false` (default) ensures only one instance changes per call; re-sweep catches anything missed

**Edit ordering for overlapping renames:**

If `old` is a substring of `new` (e.g., `test` to `test e2e`), apply most-specific match first to prevent double-edit. Track edited ranges per file to avoid re-matching.

**Path renames (Form 3):**

If args were path forms (`a/old.md` to `a/new.md`), the actual file rename is OUT OF SCOPE for this skill — that's `git mv`. This skill only updates *references* to paths in other files. Report clearly so the user runs `git mv` separately if needed.

**Preview mode:** instead of calling Edit, render the planned diff per file:

```text
File: <path>
- <line N>: <old line content>
+ <line N>: <new line content>
```

Then exit. Do not proceed to Phase 6.

### Phase 6: Re-sweep

Re-run Phase 2 (survey) with the same pattern library and `<old>`. Three possible outcomes:

**Outcome A — count == 0:** rename complete. Proceed to Phase 7.

**Outcome B — count > 0, all in already-triaged buckets:** Phase 4 user choices missed some matches. Re-present bucket counts and re-confirm. Loop back to Phase 4.

**Outcome C — count > 0, NEW pattern form not in library:** Phase 6 pattern-library-evolution trigger. STOP — do not silently apply.

Pattern evolution protocol:

1. Report the new form to user with example match
2. Document the pattern in [patterns.md](patterns.md) with all 5 fields (form name, regex, triage default, example, false-positives)
3. Re-run sweep with extended pattern library (back to Phase 2)

Ask user before automatic re-iteration — they may want to inspect manually first.

### Phase 7: Hand off

When Phase 6 reports count == 0:

1. Summarize what changed:

   ```text
   Rename complete: <old> → <new>

   Edits applied:
   - <file>: <count> changes
   - <file>: <count> changes

   Total: <N> matches across <M> files.
   Excluded: <K> plan-doc/historical/memory paths (preserved).
   ```

2. Suggest follow-up per `../SKILL.md` "Skill chaining":

   - Always: run the consuming repository's verification workflow (build + test + lint) to confirm no semantic regression
   - If user is mid-implementation under another skill or plan: return control to that flow
   - Do NOT `git add`/`commit`/`push` automatically. Report status only — the consuming repository's own commit policy governs.

## Special cases

### Self-reference exclusion

The active plan/work-notes document records the rename — both `<old>` and `<new>` appear in scope tables, success criteria, and decision logs. Auto-excluded. Apply mode rejects `--include-plan-docs` with an explicit error (see [audit-modes.md](audit-modes.md) "Override flags"); inspect via audit modes instead.

### Idempotency under partial completion

If Edit phase is interrupted (user cancels mid-flow, tool error), partial edits remain in the working tree. Re-invoke `/rename-references <old> to <new>` to resume — the survey will find only remaining matches, and re-applying succeeds because each Edit is targeted.

### Concurrent session conflicts

Edit tool's read-before-write guard catches files modified by another session. If guard fails, abort and report the conflicting file. User resolves manually before re-invoking.

### Word-boundary trap

Bare-token Form 2 uses `\b<old>\b` — `confirm` does NOT match in `confirmation`. Slash-token Form 1 uses `\B/<old>\b` — `/confirm` matches but not `path/confirm` (slash is path separator, not skill prefix).

### Frontmatter multi-line

Form 7 (frontmatter chain string) uses `multiline: true` on the Grep tool because YAML description strings can span lines:

```yaml
description: "Long description with → confirm →
  chain on second line"
```

Without multiline, this would be missed.

### Empty Certain bucket but full Chain-context

Common pattern when rename is purely conceptual (chain ordering changed but no token rename happened). Verify with user that the rename pair is correct — Chain-context-only matches often signal the user actually wants a semantic refactor, not a text rename.

## Hand-off summary

Default handoff after success:

```text
Rename `<old>` → `<new>` complete.
- Phase 5 applied <N> edits across <M> files
- Phase 6 re-sweep: 0 stragglers
- Excluded <K> plan-doc/historical/memory paths (preserved by design)

Next: run your verification workflow (build + test + lint) to confirm no semantic regression.
```

User decides whether to commit immediately or continue work first (the consuming repository's own commit policy governs).
