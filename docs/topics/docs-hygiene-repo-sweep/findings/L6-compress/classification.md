# L6-compress — classification

Full SKIP / COMPRESS / UNCERTAIN classification of the 1302-file corpus, produced by
`plugins/docs-hygiene/skills/compress/scripts/audit-scan.sh` (the skill's six-signal mechanical
classifier) followed by a per-file adjudication of every non-SKIP row.

The raw unadjudicated scan output, one row per file with the signal values inlined, is
`scan-raw.md` in this directory. This file records the adjudicated verdicts.

## Method

Two stages.

**Stage 1, mechanical.** `audit-scan.sh` over all 1302 manifest paths in one invocation. The six
signals are defined in `plugins/docs-hygiene/skills/compress/context/target-types.md`:

1. author-time-disciplined path glob (`.claude/rules/**`, `AGENTS.md`, `CLAUDE.md`, `**/SKILL.md`)
2. inline-code-token density per kilo-word
3. cross-reference density per kilo-word
4. explicit `Prose compression discipline` cite
5. default fallback
6. flavor-token density per kilo-word

**Stage 2, adjudication.** Every COMPRESS and UNCERTAIN row read in context against
`context/flavor-vs-content-matrix.md`. The matrix decides; the scan only nominates.

Stage 2 also ran a corpus-wide targeted sweep for the verbose forms the matrix names explicitly
(`in order to`, `due to the fact that`, `it is important to note that`, `it is worth noting that`,
`it should be noted that`, `make use of`, `in the event that`, `for the purpose of`,
`at this point in time`, `has the ability to`, `is able to`, `in terms of`, `a number of`,
`the fact that`, and the stacked-hedge and redundant-pair lists). The scan's signal-6 token list is
narrow by design and misses these. The sweep is what produced the single actionable cluster below.

## Aggregate

| Class | Mechanical scan | After adjudication |
|---|---|---|
| SKIP | 1280 | 1267 |
| COMPRESS | 10 | 35 |
| UNCERTAIN | 12 | 0 |

Mechanical SKIP breakdown: 239 by signal 1 (instruction-file path), 2 by signal 4 (explicit
discipline cite), 1039 by signal 6 (flavor-token density below 5 per kilo-word). No file failed to
resolve; the `reason=missing` count is 0.

The adjudicated COMPRESS count is larger than the mechanical one and shares no members with it.
All 10 mechanical COMPRESS rows were overturned to SKIP; all 12 UNCERTAIN rows resolved to
SKIP; and 35 files the scan marked SKIP were promoted to COMPRESS by the stage-2 verbose-form
sweep. The scan and the matrix disagree in both directions, which is expected: the scan's token
list omits multiword verbose forms, and it cannot see whether a token sits inside a quotation.

## COMPRESS — the list wave 3 consumes

35 files, two findings.

### Finding C1 — generated plugin-options block, `in order to` (34 files)

One identical cut in each of 34 plugin READMEs. The per-file spec with verbatim before and after
is in the per-group files in this directory.

**This cut must NOT be applied to the markdown.** All 34 spans sit inside the
`<!-- BEGIN GENERATED: plugin options ... -->` / `<!-- END GENERATED: plugin options -->` block
emitted by `scripts/sync-plugin-options-docs.py`. That script's docstring states CI runs
`--check` and rejects drift. Hand-editing the READMEs fails CI and is reverted on the next sync.

The remediation is two string-literal edits in the generator plus one regeneration run. See
`README.md` in this directory, "Finding C1 remediation", for the exact procedure.

| Group | Files |
|---|---|
| `A-doc-quality` | 2 |
| `B-cc-config-ops` | 5 |
| `C-vcs-repo` | 4 |
| `D-work-planning` | 2 |
| `E-session-behavior` | 3 |
| `F-quality-verify` | 1 |
| `H-knowledge-research` | 6 |
| `J-toolchain-platform` | 11 |

### Finding C2 — stacked hedge (1 file)

| Path | Group | Tier |
|---|---|---|
| `plugins/overengineering/skills/delta/context/recurring-wiring.md:83` | `G-code-design` | T3 |

Spec in `G-code-design.md`.

## UNCERTAIN — none

Every mechanically-UNCERTAIN row resolved on reading. The reasons are recorded below under
"Overturned rows" rather than left open, because each resolved on a fact the scan cannot see (a
quotation boundary, a contrastive pair, a technical term) rather than on a judgment call.

The brief flagged `docs/specs/d1-model-already-knows-measurement.md` and its verdict on cue-based
judgment classes. The applicable lesson here is that a cue firing without the surrounding text read
is not a verdict. This lane's stage 2 is that discipline: no verdict in this file rests on a token
count without the line read.

## Overturned rows

Every mechanical COMPRESS and UNCERTAIN row, with the fact that overturned it.

### Mechanical COMPRESS, overturned to SKIP (10)

| Path | Overturned because |
|---|---|
| `docs/topics/fable-field-guide-audit/source-article.md` | Verbatim external capture. Its own header states "body text verbatim" and names the raw capture at `raw-capture.txt`. Compressing it falsifies an evidence record and breaks the S1-S14 audit-unit correspondence the file exists to serve. |
| `plugins/ai-briefing/skills/generate/evals/fixtures/candidate-items-sample.md` | Eval fixture. `context/target-types.md` "Target validation" gate 5 excludes `evals/fixtures/` from any target set the user did not name file by file: fixture verbosity is deliberate test input. |
| `plugins/ai-slop/skills/audit/evals/fixtures/fix-guarded-rewrite.md` | Eval fixture, same gate. |
| `plugins/docs-hygiene/skills/compress/evals/fixtures/audit-fixture-dir/verbose.md` | Eval fixture, same gate. This is the compress skill's own deliberately-verbose fixture; `target-types.md` names it as the exact case the gate was added for. |
| `plugins/docs-hygiene/skills/compress/evals/fixtures/verbose-onboarding-snippet.md` | Eval fixture, same gate. |
| `plugins/ai-slop/skills/audit/reference/rewrite-guide.md` | All 9 flavor hits are quoted catalog examples or load-bearing. Lines 112-113 and 116 quote the filler and hedging forms as the things to remove: matrix content class (b), concrete prohibited-pattern example with a literal token. Lines 16 and 129 use "just" in the "merely / equally" sense. This file is also the repo's own house style guide, named as such by `.claude/rules/vendor-docs-are-not-style.md`. |
| `plugins/claude-config/skills/audit-pass/reference/terms.md` | Small-file density artifact. 188 words, 1 hit, density exactly 5 per kilo-word, one token above the threshold. That token is line 15 "the harness actually loads it for that target", contrasting with "never inferred from a filesystem walk alone" in the same sentence: matrix content class (d), qualifier narrowing scope. |
| `plugins/playbooks/skills/boris/reference/automation.md` | All 3 hits are contrastive: line 19 "not just you", line 23 "what people actually mean by loops", line 27 "no longer just lint rules". Matrix content class (c), both halves of an "X not Y" pair. |
| `plugins/songwriting/context/pat-pattison/research/box-model.md` | 36 hits, of which 22 sit inside block quotes from *Writing Better Lyrics* and 13 more inside example lyrics and ASCII box diagrams (the title idea "I'd just like to know" is the worked sketch's subject). The one editorial hit, line 562 "The test Pat actually applies", is contrastive. |
| `plugins/tdd/skills/principles/reference/methodology-beck.md` | All 8 hits sit inside verbatim Beck and Fowler quotations, including line 14, which is Beck's own phrasing of the Red step. Compressing a quotation misattributes it. |

### Mechanical UNCERTAIN, resolved to SKIP (12)

| Path | Resolved because |
|---|---|
| `.claude/source-control.md` | Both "actually" tokens contrast a documented list against what the merge gate runs. Matrix (d). |
| `plugins/ai-slop/skills/audit/evals/fixtures/report-only.md` | Eval fixture, gate 5. |
| `plugins/claude-config/skills/audit-automation-gaps/context/gap-analysis.md` | Both "actually" tokens carry the interrogative's whole point: "Is the service actually in use yet", "Does context isolation actually help". Matrix (d). |
| `plugins/codebase-health/skills/audit/reference/audit-checklist.md` | 6 hits, all load-bearing. "not just some", "not just the first", "don't just spot-check" are matrix (c) pairs; "actually exists" and "actually done" carry the audit's core claim-versus-reality contrast, matrix (d). |
| `plugins/docs-hygiene/skills/compress/context/fan-out-orchestration.md` | The hits are this skill's own flavor-token taxonomy, listed as data. Matrix (b). |
| `plugins/docs-hygiene/skills/compress/context/flavor-vs-content-matrix.md` | Same: the canonical flavor list itself. Matrix (b). |
| `plugins/docs-hygiene/skills/compress/context/semantic-diff-prompt.md` | Same: the dispatch template's worked examples of a flavor cut. Matrix (b). |
| `plugins/docs-hygiene/skills/compress/evals/fixtures/audit-fixture-dir/mixed.md` | Eval fixture, gate 5. |
| `plugins/plugin-quality/README.md` | Line 4 "or you just want to know" is the second of two stated entry motivations, contrasting with "something felt off"; dropping it collapses the pair. Lines 5 and 34 are claim-versus-reality contrasts. |
| `plugins/plugin-quality/skills/audit/references/component-types/hook.md` | Line 23 "not just one" is a matrix (c) pair. Line 32 "should match but might not" states a real possibility, not a hedge on a factually-direct statement. |
| `plugins/plugin-quality/skills/audit/references/recurring-concerns.md` | All 4 hits are claim-versus-reality or "X not Y" contrasts. |
| `plugins/songwriting/context/pat-pattison/research/section-building.md` | 19 hits, every one inside a verbatim Pattison quotation, including the table at lines 408-414 whose column heading reads "Pat's verdict, verbatim". |

The eight non-fixture rows here are the case `target-types.md` "Recheck triggers" already
anticipates: "files at 5-9/kw whose flavor tokens sit inside protected quoted text also reverted".
This run adds a second recurring shape the scan cannot see, **contrastive "actually" and "just"**,
which read as filler token-wise but carry matrix (c) or (d) content. Both shapes are recorded in
`README.md` under "Recheck-trigger evidence".
