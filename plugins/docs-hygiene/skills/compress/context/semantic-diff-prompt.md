# Semantic-diff subagent dispatch template

Agent tool prompt body + return-format contract for the default action. Loaded by `/compress` when dispatching the comparison pass; private implementation surface — do NOT cite this file from outside the skill (external consumers invoke `/compress`).

## Dispatch shape

Spawn one subagent per target file via `Agent` tool. Subagent type: `general-purpose`. Pass two file paths (original snapshot + condensed candidate) plus the prompt body below verbatim. Subagent returns categorized findings; main session decides revert vs ship.

## Prompt body (paste into Agent tool `prompt` field verbatim, with `{ORIG}` / `{COND}` substituted)

```text
Compare two markdown files and classify every textual difference. ORIGINAL is the snapshot; CONDENSED is the candidate produced by a compression pass that intends to drop FLAVOR (filler, hedging, articles, pleasantries, redundant restatement) while preserving CONTENT (directives, qualifiers, examples, thresholds, exceptions, cross-references, identifiers).

ORIGINAL: {ORIG}
CONDENSED: {COND}

For every difference, classify as exactly one of:

  SEMANTIC LOSS    — content removed/altered that changes what a reader must do, infer, or rely on. Includes: dropped directive ("must" → silence), narrowed qualifier ("ONLY X" → "X"), removed anti-example, removed threshold, removed exception clause, removed identifier, removed cross-reference, removed inline-code token.

  AMBIGUITY        — content removed/altered such that two readers could now infer different applicability. Includes: collapsed rule-unique rationale, dropped "why" that constrained scope, removed enumeration item where order mattered, merged distinct clauses that had different scopes.

  FALSE POSITIVE   — pure flavor cut, no content delta. Includes: article drop ("the X" → "X"), filler drop ("just", "really", "basically"), hedging drop ("perhaps", "might"), pleasantry drop, verbose-verb collapse ("make use of" → "use"), restatement removed.

Output schema (one block per finding, in CONDENSED line order):

  FINDING N: <SEMANTIC LOSS | AMBIGUITY | FALSE POSITIVE>
  ORIGINAL: "<verbatim quote from ORIGINAL, with surrounding sentence for context>"
  CONDENSED: "<verbatim quote from CONDENSED, OR (removed) when fully cut>"
  RATIONALE: <one sentence naming what changed AND why this classification>
  CITATION: <one of the four allowed tokens — see below>

Allowed CITATION tokens (verify primary source THIS turn before quoting):

  [<file>:<line>]              file read this turn (e.g. [README.md:142])
  [<bin> --help:<line N>]      CLI help output captured this turn
  [<URL>]                      doc URL fetched this turn (paste full URL)
  [TBD — <reason>]             cannot verify primary source; flag the gap

Forbidden CITATION tokens (training-recall markers, treat as unverified):

  [known], [from memory], [context], [obvious], [standard], [usual]

If a finding cannot be classified into exactly one of the three categories, emit "FINDING N: UNCERTAIN" with rationale; main session treats UNCERTAIN as AMBIGUITY for revert purposes.

End with a summary line:
  TOTAL: <N>; SEMANTIC LOSS: <K>; AMBIGUITY: <M>; FALSE POSITIVE: <P>; UNCERTAIN: <U>

Do NOT propose revisions. Do NOT score quality. Classify only.
```

## Required-pattern checklist (sanity-check grep targets)

The prompt body above contains all four allowed citation token patterns and all six forbidden tokens. When editing this file, drift-detect from the skill root via:

```bash
grep -F '[<file>:<line>]' context/semantic-diff-prompt.md
grep -F '[<bin> --help:<line N>]' context/semantic-diff-prompt.md
grep -F '[<URL>]' context/semantic-diff-prompt.md
grep -F '[TBD — <reason>]' context/semantic-diff-prompt.md
```

All four MUST match.

## Return-format contract

Main session parses the subagent return for the `TOTAL:` summary line; counts feed the output schema (`compression_pct`, `semantic_loss`, `ambiguity`, `false_positive`). Per-finding blocks drive the revert pass — every SEMANTIC LOSS + AMBIGUITY (+ UNCERTAIN) finding's CONDENSED quote reverts to its ORIGINAL form.

## Failure modes

- **Subagent returns prose without the FINDING N: blocks** — treat as dispatch failure; surface error + revert entire candidate. Do NOT ship a partially-classified diff.
- **Subagent uses forbidden citation token** — treat ALL findings from that dispatch as unverified training recall; revert the entire candidate.
- **Subagent returns 0 findings** — verify with `diff -u {ORIG} {COND}` that files actually differ; 0 findings on a non-zero diff = dispatch failure (revert).

## Cross-references

- `../SKILL.md` "Hard rules" — semantic-diff dispatch mandatory for default action; forbidden-token list restated there as a hard rule
- `context/flavor-vs-content-matrix.md` — the FLAVOR / CONTENT taxonomy this template operationalizes
