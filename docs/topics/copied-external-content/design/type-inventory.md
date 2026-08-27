# Type inventory — copied-external-content plugin

Contracts and shapes the implementation binds to. Working plugin name: `provenance` (thread T1;
`<name>` reads as the final pick). Field names are the contract; JSON shown is illustrative.

## Enumerations

### Evidence tier (`tier`)

| Value | Evidence gate | Reaches relay | Fix-eligible |
|---|---|---|---|
| `fingerprint-confirmed` | Matched span above the separation rule against an identity-checked fetched source | Yes | Yes |
| `source-fetched-similar` | Source fetched; below the deterministic rule; unanimous judge verdict STANDS | No (human report) | No |
| `llm-suspected` | No lexical evidence possible (paraphrase, summary) | No (human report) | No |
| `not-found` | Budgets exhausted without a source; every searched surface named | No (human report) | No |

Tiers are evidence-gated and discrete, never verbalized probabilities. The mapping is fixed at
contract time; a run never invents or reassigns a tier from prose.

### Finding class (`class`)

`verbatim` | `near-verbatim` | `paraphrase` | `summary`. The first two can reach
`fingerprint-confirmed`; the last two are permanently `llm-suspected` (blindspot card 6).

### Disposition (`disposition`)

`convert-to-pointer` | `trim-to-citation` | `condense-to-stamped-record` | `leave-with-reason`
| `neutral-not-found`. Only the first three are edits, and only `fix`/`sweep` apply them.
Offline-load-bearing surfaces never take `convert-to-pointer` bare removal; they condense.

### Rubric criteria (ids used in grades and evals)

`C1-span-correspondence` | `C2-beyond-common-idiom` | `C3-attribution-adequacy` |
`C4-transformative-use`. Binary, each graded with a quoted-evidence field. Verdict rule:
all four must hold for STANDS (S3 showed criterion votes can split while the verdict stays
stable). Carve-outs are evaluated before any criterion.

## Finding record (machine-parseable report sidecar)

One JSON object per finding, in the memory-tier report sidecar. The relay file and the human
report are both projections of this record.

```json
{
  "id": "f-0042",
  "rule": "<name>/audit/rule-verbatim-copy",
  "file": "docs/topics/example/README.md",
  "span": { "start_line": 41, "end_line": 58 },
  "class": "verbatim",
  "tier": "fingerprint-confirmed",
  "source": {
    "url": "https://code.claude.com/docs/en/skills.md",
    "fetched": "2026-08-27",
    "route": "rung-1",
    "identity": { "checked": true, "first_heading": "# Extend Claude with skills" }
  },
  "fingerprint": {
    "k": 5, "containment": 0.42, "longest_span_words": 27,
    "matched_spans": [ { "local_lines": [44, 51], "words": 27 } ]
  },
  "rubric": {
    "samples": 3, "unanimous": true, "verdict": "STANDS",
    "grades": { "C1-span-correspondence": { "pass": true, "evidence": "..." } }
  },
  "disposition": null,
  "budget": { "searches": 0, "fetches": 1, "breadcrumb": "sibling:docs/topics/example/NOTES.md:12" }
}
```

Nulls are honest: `fingerprint` is null when nothing was fetched; `rubric` is null for
carve-out declines (which are counts, not findings). `span` from nomination is approximate for
report-only tiers; for `fingerprint-confirmed` it is replaced by the module's exact matched
span, which is what makes fix edits fenceable.

## Script contracts

All scripts: stdout is the product (JSON unless stated), stderr is diagnostics, exit 0 on
clean run with findings or none, non-zero only on operational failure. Each ships a paired
test (`.test.sh` for bash, `.test.mjs` for the Node module, autonomy-plugin precedent).

### `list-corpus.sh [target] [--paths-file F] [--show-config]`

Tracked markdown under target (default repo), minus built-in categorical exclusions and config
`excluded_paths`. Output: file list plus a declined block `{path_pattern, count, reason}`.
The eval-fixture tree is excluded unconditionally.

### `extract-breadcrumbs.sh --dir D | --files F...`

Per file: `{urls: [{url, line}], fences: [{source_url, date, start_line, end_line}],
stamp_lines: [{line, text}]}`, emitted per directory so sibling breadcrumbs travel together.

### `check-stamps.sh [--expiry-days N] [--trigger-less] [--show-config]`

Expiry findings with fired values `{file, line, stamp_date, window_days, days_over}`. Declined
block counts unparsed candidate stamp forms with reasons. `--trigger-less` (config-gated,
default off) additionally flags dated stamps whose surface states no recheck trigger.

### `fingerprint.mjs compare --local FILE --source FILE [--json]`

The pure module plus a thin CLI. Preprocessing inside the module: strip code fences,
blockquotes, and inline-quoted spans (straight and curly quotes) from the LOCAL text before
shingling. Then word 5-shingles, containment, Jaccard, longest matched span. Output:
`{containment, jaccard, longest_span_words, matched_spans: [{local_lines, source_lines,
words}], separation: {rule: "containment>=0.3||span>=15", fired: true}}`. Constants are
named placeholders read from config; plan time tunes them (Q10/Q16).

### `emit-findings.sh --report SIDECAR`

Projects relay-eligible findings (`fingerprint-confirmed` copies, stamp rules) into a
conforming findings file per the detector-findings contract: fetches the contract at run time,
refuses to write when unreachable (report-only outcome, stated), resolves the destination
through the topic-docs binding's rung order with the non-interactive collapse, applies the
cell-escaping rule, leads every Finding cell with the qualified rule id and fired condition.

## Crosswalk rows (draft; land in the detector-findings registry at implementation)

| Rule id | Fires on | Tier argument (severity.md walk) | Tier | Auto-applicable |
|---|---|---|---|---|
| `<name>/audit/rule-verbatim-copy` | A fingerprint-confirmed matched span (fired values: containment, span words, source URL, identity check) | CRITICAL fails every limb: copied prose computes nothing, so no input, caller, or subsequent change produces a wrong result. IMPORTANT matches twice over: the stated-rule limb (the org standard `documentation-and-citations.md` says prefer citing and fetching at read time over storing a snapshot, so a retained copy violates a rule the org already adopted in writing) and the degradation limb with a named trigger (the upstream page's next content change strands the local copy; the first reader trusting the stale copy acts on drifted facts under this repo's authority). SUGGESTION is never reached. | IMPORTANT | No, remediated by `/<name>:audit fix` (dispositions, semantic-diff guard, and pointer-liveness discipline are producer-owned) |
| `<name>/audit/rule-stamp-expired` | A four-part record whose as-of date exceeds the configured window (fired values: date, window, days over) | CRITICAL fails identically. IMPORTANT's degradation limb matches with a named trigger: the record's currency ceiling has lapsed, and the first reader acting on the stamped claim without the re-fetch the convention requires acts on an assertion nobody has re-derived. | IMPORTANT | No — the repair is re-deriving the record against its live basis, a judgment the relay surfaces, never applies |
| `<name>/audit/rule-trigger-less-stamp` | Repo-override only: a dated stamp whose surface states no recheck trigger | The stated-rule limb directly: the consuming repo that enables this check has adopted the upstream-drift required parts, and a trigger-less stamp violates part 4. Portable default stays off because the fleet's stamp forms are not uniformly greppable and a guessing gate converts signal to noise. | IMPORTANT | No — writing the missing trigger is a judgment about what observable event guards the claim |

Judgment verdicts (`source-fetched-similar`, `llm-suspected`, split rubric outcomes) have NO
rows: they never reach the relay (the ai-slop V1 boundary, restated in the Brief). The
fail-safe direction holds structurally: the deterministic rules have no withholding verdicts,
and every LLM uncertainty falls toward a report-only tier, never toward silence; each tier is
visible on the one human surface plus the sidecar, so one candidate carries one disposition on
every surface the producer emits to.

## Config schema (`.claude/<name>.json`, config-cascade)

```json
{
  "excluded_paths": ["docs/legacy/**"],
  "budgets": {
    "searches_per_candidate": 3,
    "fetches_per_candidate": 5,
    "corpus_fetch_ceiling": 200
  },
  "separation": { "min_containment": 0.3, "min_span_words": 15 },
  "stamp_expiry_days": 180,
  "trigger_less_stamp_check": false,
  "judge_samples": 3,
  "gates": {
    "fix_precision_bar": 0.95,
    "report_recall_floor": 0.8,
    "min_n_per_class": 10
  },
  "accuracy": {
    "nomination_passes": 2,
    "judge_lens_diversity": true,
    "review_agents": 1,
    "deep_research_on_exhaustion": false
  }
}
```

Amended 2026-08-27 at plan time: the user resolved Q16 as an accuracy-first, all-tunable
posture (spend tokens rather than miss copies), which added the `gates` and `accuracy` blocks
and set the numeric defaults; PLAN.md's Q16/Q10 resolutions section is the record. Gates bind
fix-mode eligibility and release readiness only; report surfaces are never filtered by them.

## Golden-set case shape (runner-agnostic)

One directory per case: `case.md` (the fixture document), `expected.json`
(`{findings: [{class, tier, span, rule?}], negatives: true|false, notes}`), and where the case
needs a source, `source.md` (the synthetic upstream page, served to the fingerprint module
directly so cases run offline). Authored so a future `case.yaml` wrapper for `claude plugin
eval` is a projection, not a rewrite. Positives are shape-preserving rewrites of real history
cases; hard negatives include paraphrase-styled-never-copied distractors and
quoted-and-cited excerpts. The tree sits under `skills/audit/evals/fixtures/golden/` and is
categorically excluded from every scan corpus.

## Terminology table

| Term | Meaning here | Rejected synonyms, with reasons |
|---|---|---|
| breadcrumb | A citation, URL, fence, or stamp already in or near a passage (sibling files included) that names a candidate source | "hint" (vague), "reference" (overloaded with the pointer end-state) |
| pointer | The end-state link that replaces a copy | "reference" (overloaded), "citation" (reserved for trim-to-citation's quoted form) |
| stamped record | The upstream-drift four-part fallback (claim, basis, as-of date, recheck trigger) | "snapshot" (implies stored page bytes) |
| carve-out | A categorical allowance evaluated before criteria; never per-instance | "suppression" (reserved for operator-judged keeps per finding-suppression), "whitelist" |
| separation rule | The fingerprint module's fired condition (containment OR span threshold, after quote-stripping) | "threshold" alone (two constants, one rule) |
| neutral disposition | "source not identified (budget exhausted; searched: ...)" | "failure", "unknown" (it is a first-class, named outcome) |
| nomination | The recall-biased LLM pass that proposes suspect passages and candidate sources | "detection" (detection is the whole pipeline, not the first pass) |
