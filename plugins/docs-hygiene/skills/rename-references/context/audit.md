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

### Phase 2: Survey

Run all patterns from [patterns.md](patterns.md) in parallel via Grep tool. For each pattern:

- Substitute `<old>` with actual old token (escape regex metacharacters)
- Use `output_mode: "content"` with `-n` for line numbers and `-C 1` for one line of surrounding context
- Use `multiline: true` for Form 7 (frontmatter chain string)
- Apply auto-exclusions per `../SKILL.md` "Auto-exclusions" via `glob` filter or post-filter

Aggregate matches into a flat list of `{file, line, pattern_form, snippet}` tuples.

### Phase 3: Triage

Classify each match into one of three buckets per [triage.md](triage.md):

- **Certain** — high-precision form (slash-token, path, frontmatter glob)
- **Chain-context** — high-precision form when neighbors confirm context (chain prose with known skill names, numbered rows)
- **Ambiguous** — bare-token form when `<old>` is in English-verb blocklist, OR chain-form without confirming neighbors

### Phase 4: Report (audit-mode terminal step)

Present findings in this exact format:

```text
Rename audit: <old> → <new>
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

Next: invoke `/rename-references <old> to <new>` to apply, or `/rename-references preview <old> to <new>` to dry-run.
```

If `<new>` is undetermined (single-token reverse mode), omit the `→ <new>` and the "Next" line — instead suggest the user pick a target via `AskUserQuestion`.

## Output discipline

- Audit reports facts, not actions. NEVER call Edit/Write in audit mode
- If user implicitly authorizes edits ("yes apply") during audit, switch to apply mode (`/rename-references <old> to <new>`) — never silently start editing from within audit
- Audit is cheap to re-run; encourage iteration

## Special cases

- **Zero matches across all patterns** — report explicitly. Rename target either does not appear in codebase OR pattern library has a gap. If user expected matches, treat as Phase 6 pattern-library-evolution trigger
- **All matches in excluded paths** — report with breakdown showing why each was excluded. User may want to widen scope via the override flags (`--include-historical`, `--include-memory`, `--include-plan-docs`)
- **Ambiguous bucket is empty AND `<old>` is in English-verb blocklist** — unusual. Re-run Form 2 without blocklist filter to verify; the blocklist demotes, not excludes
- **Audit invoked while another `/rename-references` apply is in progress** — abort. In-flight edits and rename-documenting plan docs would be misclassified mid-apply

## Hand-off

After audit completes, suggest the next action based on counts:

| Result | Suggestion |
|---|---|
| 0 matches | "No stragglers found. Safe to proceed." If post-rename context, suggest running the consuming repository's verification workflow |
| Only Certain bucket non-zero | Suggest `/rename-references <old> to <new>` — auto-apply will likely succeed cleanly |
| Chain-context or Ambiguous non-zero | Suggest `/rename-references preview <old> to <new>` first — user reviews planned edits before committing |
| NEW form discovered (no pattern matched but user reports a stale ref) | Phase 6 evolution — extend `context/patterns.md`, re-audit |
