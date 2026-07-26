# Audit Mode — Read-Only Rename Sweep

Audit mode runs the full pattern library + triage classifier against the codebase but performs NO Edit calls. Output is a findings report. Use when:

- Pre-rename impact analysis ("how big is the blast radius if I rename X?")
- Verifying a just-completed rename has zero stragglers (post-rename gate)
- Investigating a suspected stale reference reported elsewhere
- User wants to think about the rename before committing to edits

## Inputs

| Form | Behavior |
|---|---|
| `/rename-references audit` (no args) | Smart default detection per `../SKILL.md` "Smart default" — pick rename pair from conversation/git/staged |
| `/rename-references audit <old>` | Single-token reverse mode — find references, ask user what `<new>` would be |
| `/rename-references audit <old> to <new>` | Explicit pair — sweep for `<old>` references and report what would change to `<new>` |

## Workflow (Phases 1–3 only)

### Phase 1: Detect

Resolve the rename pair `(old, new)`:

1. If args supplied with separator (`to`/`→`/`->`/`into`), parse per `../SKILL.md` "Natural-language parser"
2. If single-token arg, pair is `(arg, undetermined)` — ask via `AskUserQuestion` what new name would be (so triage can show "would change X to Y" diffs)
3. If no args, run Smart default detection. If multiple candidates, present via `AskUserQuestion`. If zero, abort with helpful message

Then resolve the **rename MODE** — container vs identifier — per [patterns.md](patterns.md)
"Phase 0b" and its selection ladder (explicit override → filesystem → manifest → invocation
shape → ask). The pair alone does not determine it, and the mode changes how the bare-token
residue is bucketed, so resolve it here rather than letting a default apply silently.

Only the explicit override short-circuits. **Collect the filesystem, manifest and invocation-shape
evidence in full and compare their verdicts** — they can disagree in a monorepo where an
identifier shares a name with an unrelated package, and taking the earliest would silently pick
container mode and suppress the identifier's actionable references. On disagreement, ASK rather
than resolve. Carry the resolved mode and every rule that fired into the Phase 4 report.

### Phase 2: Survey

Run all patterns from [patterns.md](patterns.md) in parallel via Grep tool. For each pattern:

- Substitute `<old>` with actual old token (escape regex metacharacters)
- Use `output_mode: "content"` with `-n` for line numbers and `-C 1` for one line of surrounding context
- Use `multiline: true` for **Form 7** (frontmatter chain string) **and Form 14's Setext-title
  alternative** — both patterns contain a literal `\n`, which ripgrep's single-line default
  REJECTS outright (`the literal "\n" is not allowed in a regex`). Without it the Setext pattern
  errors rather than under-matching, so the survey silently loses the form and a container's
  landing-page title survives as Form-2 residue that container mode excludes
- Apply auto-exclusions per `../SKILL.md` "Auto-exclusions" via `glob` filter or post-filter

**Collect per-OCCURRENCE records, not per-line ones.** `output_mode: "content"` returns matching
LINES, and `--column` reports only the first match on a line — so a line-shaped record gives the
span rule below nothing to compare and silently degrades it back to line-keyed dedup, restoring
the false completion eval 14 exists to prevent. For every returned match, re-scan it locally for
ALL occurrences of the form's pattern and emit one record per occurrence:
`{file, line, start, end, pattern_form, snippet}`. A line with two `<old>` occurrences produces
two records.

**Enumerate every `<old>` span INSIDE each match — do not rely on repeated whole-pattern
matching.** Some forms match a span far wider than the token: Form 7's
`description:\s*"[^"]*\b<old>\b[^"]*"` swallows the entire field, and its greedy prefix binds the
captured group to just ONE occurrence. On `description: "first <old> and then <old>"` the pattern
yields a single match for two references, and no amount of cursor advancing recovers the other —
re-matching from inside the field cannot reproduce the `description:` prefix the pattern requires.
So for each match, scan its text for every occurrence of `<old>` and emit one record per
occurrence, all attributed to the matching form. The whole-pattern match establishes THAT the form
applies and to what extent; the token spans inside it are the references. Under container mode a
lost occurrence becomes suppressed Form 2 residue, so this drops silently and the rename can
falsely complete.

**Then advance the rescan cursor to the end of the LAST enumerated `<old>` span, not the end of
the match.**
Several forms deliberately CONSUME a trailing delimiter instead of using a lookahead, because
ripgrep's default engine rejects look-around — Forms 3, 13, 15 and both delimiter-anchored Form 14
alternatives all do. That consumed delimiter is frequently the LEADING delimiter the next
occurrence needs, so a rescan that resumes after the whole match eats the boundary and emits only
the first of two adjacent references. Verified: on `{"name":"<old>","id":"<old>"}` a global
`rg -o` returns ONE match, `{"name":"<old>",`, because the first match consumed the comma the `id`
member needed; resuming at the end of the captured token instead returns both. Insert
`"version":"1"` between them and both appear either way — the collision is specifically
ADJACENCY, which is exactly what a compact manifest produces. Form 2 still finds the lost token,
but under container mode that is suppressed residue, so the sweep can report completion with the
second declaration stale.

Two details that make the cursor rule correct rather than merely different:

- **Advance a cursor; do not slice the string.** Re-running the pattern against a substring makes
  `^` match at the cursor, which would admit a member with no delimiter in front of it. Keep `^`
  bound to the real start of line or block.
- **The cursor is the last enumerated token's end, not the match's start + 1.** Advancing by one
  character re-finds the same occurrence through a different alternative and doubles the record;
  the captured span is the unit of identity everywhere else in this pipeline, so it is the unit
  here too. Advancing past the whole match is the adjacency bug above; advancing past only the
  FIRST token in a wide match re-emits the ones already enumerated.

**Rescan the returned BLOCK, not a line, for the multiline forms.** For Form 7 and Form 14's
Setext alternative the unit Grep returns is a multi-line block, and the pattern only matches
against that whole block — feeding it one line at a time reproduces NOTHING, so the rescan emits
no record and the reference vanishes between the survey and triage, silently, on exactly the two
forms that were added because their references were being missed. Keep the matched block intact,
run the form's pattern against the block, locate the captured `<old>` span within it, and convert
that block offset to `(line, start, end)` using the block's own first-line number. Line-by-line
rescanning is correct for every single-line form and wrong for these two; branch on whether the
form needs `multiline: true`, which is the same two forms listed above.

With those records, apply BOTH rules from `patterns.md`, in this order:

1. **Precedence** ("Phase 0") — deduplicate by OCCURRENCE SPAN `(file, line, start, end)`, never
   by whole line: a weaker match is suppressed only when its span is COVERED BY a more-specific
   match's span, so a second reference elsewhere on the same line survives. Coverage also collapses
   COEQUAL matches — two alternatives of one form hitting the same occurrence keep one, widest span
   first — or the count doubles and the second targeted Edit fails on an already-rewritten token.
   A match by Forms 13–15 is attributed to that form and its weaker Form 2 / chain-form duplicates
   are dropped. Carry the dropped count into the report's "superseded" row.
2. **Container-rename mode** ("Phase 0b") — when the renamed thing is a container, apply the
   Certain-eligibility ALLOWLIST to every remaining match, not only to the bare-token ones. Forms
   1, 3 and 13–15 are the whole eligible set: Form 2's residue leaves Certain and is reported as
   one aggregate count, and **every other form's matches — Forms 4 through 12 — are demoted to
   Ambiguous**, including Forms 8 and 12, which are Certain by default and would otherwise stay
   on the auto-apply path and rewrite an unrelated dotted key or glob entry. Precedence alone
   leaves all of them at their identifier-mode ratings; the mode rule is what removes them.

Both run BEFORE Phase 3, or triage will bucket the same reference twice and re-admit the
residue the mode rule excluded.

### Phase 3: Triage

Classify each match into one of three buckets per [triage.md](triage.md):

- **Certain** — high-precision form (slash-token, path, frontmatter glob, and the
  container-position Forms 13–15 **when their own scope rules do not demote them**). **Under
  container-rename mode the eligible set is narrower** — Forms 1, 3 and 13–15 only, so the
  frontmatter glob (Form 8) and the dot-form (Form 12) are not Certain there
- **Chain-context** — high-precision form when neighbors confirm context (chain prose with known skill names, numbered rows)
- **Ambiguous** — bare-token form when `<old>` is in English-verb blocklist, OR chain-form without confirming neighbors

### Phase 4: Report (audit-mode terminal step)

Present findings in this exact format:

```text
Rename audit: <old> → <new>
Mode: <container|identifier> (resolved by: <rule that fired>)
Sweep across <N> tracked files (excluded: <K> plan-doc/historical/memory paths).

| Bucket          | Count | Sample location |
|-----------------|-------|-----------------|
| Certain         | <X>   | <file>:<line>   |
| Chain-context   | <Y>   | <file>:<line>   |
| Ambiguous       | <Z>   | <file>:<line>   |
| Excluded        | <W>   | (skipped)       |

Top 5 affected files:
- <file>:<count> matches
- <file>:<count> matches
...

Pattern-form breakdown:
- Form 1 (slash-token):     <count>
- Form 2 (bare-token):      <count>
- Form 3 (path):            <count>
- Form 4 (chain forward):   <count>
- Form 5 (chain backward):  <count>
- Form 6 (numbered row):    <count>
- Form 7 (frontmatter):     <count>
- Form 8 (glob set):        <count>
- Form 9 (PascalCase list): <count>
- Form 10 (cross-skill):    <count>
- Form 11 (line-number-citation): <count>
- Form 12 (dot-form sub-identifier): <count>
- Form 13 (command-argument):  <count>
- Form 14 (document title):    <count>
- Form 15 (possessive/appositive): <count>
- Form-2 hits superseded by container-position matches: <count>
- Bare-token occurrences outside container position (container-rename mode; NOT proposed): <count>
- Forms 4–12 demoted to Ambiguous by the container-mode allowlist: <count>

Next: invoke `/rename-references <old> to <new>` to apply, or `/rename-references preview <old> to <new>` to dry-run.
```

If `<new>` is undetermined (single-token reverse mode), omit the `→ <new>` and the "Next" line — instead suggest the user pick a target via `AskUserQuestion`.

## Output discipline

- Audit reports facts, not actions. NEVER call Edit/Write in audit mode
- If user implicitly authorizes edits ("yes apply") during audit, switch to apply mode (`/rename-references <old> to <new>`) — never silently start editing from within audit
- Audit is cheap to re-run; encourage iteration

## Special cases

- **Zero matches across all patterns** — report explicitly. Rename target either does not appear in codebase OR pattern library has a gap. If user expected matches, treat as Phase 6 pattern-library-evolution trigger
- **All matches in excluded paths** — report with breakdown showing why each was excluded. User may want to widen scope via the override flags (`--include-historical`, `--include-memory`, `--include-plan-docs`, `--include-bare-token`)
- **Ambiguous bucket is empty AND `<old>` is in English-verb blocklist** — unusual for an
  identifier rename. Re-run Form 2 without blocklist filter to verify; the blocklist demotes, not
  excludes. **Expected, not unusual, under container-rename mode** — there the bare-token residue
  is excluded from the buckets entirely and reported as an aggregate, so an empty Ambiguous
  bucket is the designed outcome rather than a signal to re-run
- **Audit invoked while another `/rename-references` apply is in progress** — abort. In-flight edits and rename-documenting plan docs would be misclassified mid-apply

## Hand-off

After audit completes, suggest the next action based on counts:

| Result | Suggestion |
|---|---|
| 0 matches | "No stragglers found. Safe to proceed." If post-rename context, suggest running the consuming repository's verification workflow |
| Only Certain bucket non-zero | Suggest `/rename-references <old> to <new>` — auto-apply will likely succeed cleanly |
| Chain-context or Ambiguous non-zero | Suggest `/rename-references preview <old> to <new>` first — user reviews planned edits before committing |
| NEW form discovered (no pattern matched but user reports a stale ref) | Phase 6 evolution — extend `context/patterns.md`, re-audit |
