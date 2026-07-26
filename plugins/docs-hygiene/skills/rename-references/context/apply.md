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

Then resolve the **rename MODE** per [patterns.md](patterns.md) "Phase 0b" and its selection
ladder. Apply mode must resolve it BEFORE Phase 2 — it decides both how residue is bucketed and
what Phase 6's actionable count means, so an unresolved mode makes the completion check
undefined.

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

**Record every decline as a confirmed skip, keyed by `(file, line, start, end)`.** "skip bucket",
"skip this" and "skip remaining ambiguous" each produce skip records for the matches they cover.
Phase 6 subtracts those spans from the actionable count — without the record the same declined
match re-enters Outcome B on every re-sweep and the loop cannot terminate. See Phase 6.

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

Re-run Phase 2 (survey) with the same pattern library and `<old>`.

**"Count" here means the ACTIONABLE count** — the survey result after applying both
[patterns.md](patterns.md) "Phase 0" precedence and "Phase 0b" container-rename mode. Under a
container rename the bare-token residue is deliberately left unrenamed (it is ordinary use of
the word, not a reference), so those lines still match `<old>` forever. Counting them raw
means the completion check can never reach zero and Outcome B loops indefinitely. Residue does
not count toward completion; report it in the Phase 7 summary as the same aggregate the audit
reports.

**A DELIBERATE SKIP is not actionable either — track skips and subtract them.** Residue is not
the only category the sweep leaves matching forever. Every Phase 4 "skip this" / "skip bucket"
answer leaves a real match in place on purpose, and container mode makes that routine rather
than rare: it demotes Forms 4–12 to Ambiguous, so an unrelated `context.timeout` reaches the
user as a per-match prompt and the correct answer is to skip it. Counting a confirmed skip as
actionable re-presents the same match at Outcome B forever, and the only exits are rewriting a
known false positive or aborting with a partial result — the identical non-terminating loop the
residue rule closes, reached through the other door.

So Phase 4 must RECORD each skip as `(file, line, start, end)` — the same occurrence key
precedence and dedup use — and Phase 6 subtracts those spans from the actionable count. Two
constraints on the record:

- **Key it by span, not by file or by form.** Skipping one occurrence is not consent to skip a
  second one on the same line, and the user answered about a specific reference.
- **REMAP the stored spans as Phase 5 applies edits — a span recorded pre-edit does not survive
  the edit.** `<old>` and `<new>` are different lengths in the general case, so applying an
  accepted occurrence shifts every LATER occurrence on that same line by
  `len(<new>) - len(<old>)`. On `/plugin configure <old>; use <old>.timeout` the accepted Form 13
  match moves the skipped Form 12 match's columns, the Phase 6 rescan reports different
  `(start, end)`, the stored span fails to subtract, and the user is prompted for the deliberate
  skip again — the same non-terminating loop, now defeated by the bookkeeping meant to close it.
  After each Edit at `(line, start, end)`, add the delta to the `start` and `end` of every stored
  skip span on that line whose `start` is greater than the edited `start`. Spans on other lines
  and earlier spans on the same line are unaffected, because a rename replaces in place and adds
  no lines. Carry the matched snippet alongside the span and treat a snippet mismatch after
  remapping as a bug to report, not a skip to silently drop.
- **A skip is scoped to the sweep that asked.** If Phase 6 discovers a NEW form (Outcome C) and
  the library is extended, re-ask rather than carrying the old skip across a changed question.

Report skips in the Phase 7 summary as intentionally preserved — never fold them into the
residue aggregate, which is a different thing: residue was never proposed, a skip was proposed
and declined.

Three possible outcomes:

**Outcome A — actionable count == 0:** rename complete. Proceed to Phase 7. Deliberate skips and
residue may both be non-zero here; that is completion, not a partial result.

**Outcome B — actionable count > 0, all in already-triaged buckets:** Phase 4 user choices missed some matches. Re-present bucket counts and re-confirm. Loop back to Phase 4. **Confirmed skips are excluded before this test**, so a match the user declined never re-enters the loop.

**Outcome C — actionable count > 0, NEW pattern form not in library:** Phase 6 pattern-library-evolution trigger. STOP — do not silently apply.

Pattern evolution protocol:

1. Report the new form to user with example match
2. Document the pattern in [patterns.md](patterns.md) with all 5 fields (form name, regex, triage default, example, false-positives)
3. Re-run sweep with extended pattern library (back to Phase 2)

Ask user before automatic re-iteration — they may want to inspect manually first.

### Phase 7: Hand off

When Phase 6 reports an actionable count of 0:

1. Summarize what changed:

   ```text
   Rename complete: <old> → <new>

   Edits applied:
   - <file>: <count> changes
   - <file>: <count> changes

   Total: <N> matches across <M> files.
   Excluded: <K> plan-doc/historical/memory paths (preserved).
   Bare-token occurrences left as ordinary use (container-rename mode): <R>.
   Skipped at your confirmation: <S>.
   ```

   Emit the `<R>` line only under container-rename mode, and only when `<R>` is non-zero —
   it is what keeps completion from reading as a raw-zero sweep when residue was deliberately
   preserved. Omit it entirely for an identifier rename, which has no residue concept.

   Emit the `<S>` line whenever `<S>` is non-zero, in either mode, and keep it SEPARATE from
   `<R>`. They are different facts: residue was never proposed, a skip was proposed and
   declined. Collapsing them hides that the user made a decision, and a reader checking why a
   surviving `<old>` was left alone needs to know which of the two it was.

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

Bare-token Form 2 uses `\b<old>\b` — `confirm` does NOT match in `confirmation`. Slash-token Form 1 uses `\B/<old>([^\w-]|$)` — `/confirm` matches but not `path/confirm` (slash is path separator, not skill prefix).

**A word boundary is NOT enough on the trailing side.** `\b` treats a hyphen as a boundary, so `\B/<old>\b` matched `/confirm-changes` as well as `/confirm` — and Form 1 auto-applies. Slash-command and container names are kebab-case, so this fires constantly in practice; the consumed `([^\w-]|$)` terminator is what rules it out. Forms 3, 13, 14 and 15 exclude an adjacent hyphen for exactly the same reason.

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
- Phase 6 re-sweep: 0 actionable stragglers
- Excluded <K> plan-doc/historical/memory paths (preserved by design)
- Left <R> bare-token occurrences as ordinary use of the word (container-rename mode; omit this
  line for an identifier rename or when <R> is 0)
- Skipped <S> matches at your confirmation (omit when <S> is 0)

Next: run your verification workflow (build + test + lint) to confirm no semantic regression.
```

The `<S>` line is not optional formatting. "0 actionable stragglers" is true after a skip and
still misleading on its own — the run preserved stale occurrences BY REQUEST, and a reader who
sees only the zero has no way to tell that from a sweep that found nothing. Same reason `<R>`
exists, different fact: residue was never proposed, a skip was proposed and declined, so the two
stay on separate lines in both this template and the Phase 7 summary.

User decides whether to commit immediately or continue work first (the consuming repository's own commit policy governs).
