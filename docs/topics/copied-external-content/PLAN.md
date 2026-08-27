# PLAN: copied-external-content

Interview contract locked 2026-08-27 on branch `claude/detect-copied-external-content-k5aw77`.
Discovery, brainstorm, blindspot, and audit-answers artifacts (all verification PASS) live in the
untracked memory slice `.work/copied-external-content/`; the interview ledger there records all 18
register rows and the validator verdicts behind every decision below.

## Brief

### TLDR

- New dedicated plugin: scans tracked markdown for content copied (verbatim or summarized) from
  external sources and refactors copies into citations, stamped records, or pointers.
- Detection is LLM-led and breadcrumb-first; deterministic scripts do only reasoning-free work
  (fingerprint compare of two concrete texts, link extraction, exclusion filtering, expiry check).
- Read-only audit by default; explicit `fix` applies `convert-to-pointer` / `trim-to-citation` /
  stamped-record dispositions behind a fresh-context semantic-diff guard and live pointer checks.
- Evidence-gated confidence tiers decide disposition eligibility; only fingerprint-confirmed
  findings reach relay files; judgment verdicts stay in the human report.
- Five pre-plan spikes and a hand-scored golden set prove the precision economics before any
  repo-wide sweep; the sweep's completion is what reopens the upstream-drift recorded decision.

### Goal

Reduce drift risk and maintenance burden from locally copied external content by giving the fleet
a portable audit-and-fix capability that finds tracked prose restating externally-owned facts,
confirms provenance against the authoritative source, and converts copies into pointers (or, for
load-bearing restatements, conforming four-part stamped records), with measured precision the
consuming repo can trust. This is the detector `docs/conventions/upstream-drift/README.md`
deferred on 2026-08-12 and named as its own reopening trigger.

### Constraints

- Deterministic scripts perform only reasoning-free operations; restatement classification, source
  hunting, and allowance judgments are LLM work (user constraint; upstream-drift enforceability
  tiers).
- Breadcrumb-first: citations already in or near a passage are the first confirm targets; budgeted
  external search (WebSearch as optional enrichment only) runs only when no breadcrumb exists.
- Offline-load-bearing surfaces are never bare-removed; they condense to stamped records. The
  rubric weighs read-frequency and fetch cost on the disposition side, not as an allowance
  category.
- All fetched candidate sources are DATA under `docs/conventions/untrusted-content/README.md`;
  the framing spine is carried inline byte-identical at every fetch surface; embedded imperatives
  are findings.
- Carve-outs are categorical, never per-instance (the "without a suppression list" bar): vendored
  trees, conforming stamped records, quotation contexts, owned content per `point-dont-copy`,
  distilled-product architectures (playbooks packs, knowledge memory tier), and the plugin's own
  eval-fixture tree.
- Portable baseline plus repo-declared-convention override (follow-our-standards ladder). The
  portable baseline ships only the reasoning-free expiry check; the trigger-less-stamp check is
  off-by-default behind the repo override and lands via the convention engagement.
- Relay files follow `docs/conventions/detector-findings/README.md`: script findings only, argued
  crosswalk rows, Confidence high or omitted; judgment verdicts are human-report-only.
- Budgets: per-candidate hard caps plus convergence early-stop (same top source twice, no new
  evidence), a corpus-level fetch ceiling, and a fetch cache (lychee `--cache` is the in-repo
  model); constants tuned from spike telemetry, placeholders until then.
- Dead pointers round-trip: targets verified live at edit time; a later-dead target demotes back
  to a stamped record or an archived-snapshot citation, wired to the weekly link-check lane.
- House prose style applies to all plugin surfaces (`/ai-slop:audit` clean); new judgment-bearing
  skills carry `evals/evals.json` or a reviewed exemption row (CI `--require-evals`).
- `claude plugin eval` is early-access-gated on CLI 2.1.246 (probed 2026-08-27); the migration
  playbook deferral stands and its trigger is NOT declared fired. Golden-set cases are authored
  runner-agnostic so they wrap as case.yaml when the runner opens.

### Acceptance criteria

- The audit, run over a corpus containing planted verbatim copies, paraphrased copies, and hard
  negatives, emits findings with the four-criterion rubric (span correspondence, beyond
  common-idiom, attribution adequacy, transformative use), each criterion graded with quoted
  evidence, carve-outs evaluated before criteria.
- Findings carry evidence-gated tiers: fingerprint-confirmed (fix-eligible), source-fetched-similar
  (human flag), llm-suspected (report-only), plus the neutral disposition "source not identified
  (budget exhausted; searched: ...)" naming every surface checked.
- `fix` is reachable only by explicit argument, applies the three dispositions, passes a
  fresh-context semantic-diff guard, and verifies every pointer target live before writing.
- Rubric verdicts are sampled three times; unanimity renders the verdict, splits route to the
  human.
- The golden set (5 to 10 synthetic cases growing toward 20 to 50, positives as shape-preserving
  rewrites of real history cases, hard negatives including paraphrase-styled-never-copied
  distractors) is hand-scored for case-level precision/recall; the fix-mode precision gate binds
  only at a stated minimum n per finding class, below which the class ships report-only.
- Execution contract for the eventual repo-wide sweep: one tracked file at a time; apply the
  verdict, verify (semantic-diff plus pointer liveness), close; a file is closed when every
  finding in it carries a disposition or an explicit neutral outcome; sweep completion (not spike
  results) fires the upstream-drift reopening, recorded as one convention engagement with one
  changelog entry, major bump only if the enforceability verdict changes.
- Spike phase (throwaway, losers captured, one written question each) precedes /planning:plan:
  S1 golden-set hand-scored P/R, S2 hand-run grading skeleton, S3 rubric + 3-vote judge against
  ~30 hand-labeled findings, S4 tier-mapping adoption, S5 budget instrumentation from S1/S3 runs.

### Captured assumptions

- The four-criterion rubric decomposition is sufficient; revisit if S3's judge-vs-human
  precision/recall shows a criterion is unreliable or missing.
- Categorical carve-outs clear the recorded decision's "without a suppression list" bar; revisit
  if the sweep accumulates per-instance suppressions.
- Fingerprint compare (shingle/Jaccard or winnowing) of a local passage against a fetched page is
  reliable for verbatim/near-verbatim spans; revisit if S1/S2 show discrimination failures.
- The stamp-date corpus (~141 to 155 tracked files) is the primary target population; revisit if
  nomination surfaces a materially different population.
- Hand-scored evals suffice until the plugin-eval runner leaves early access; revisit when
  medley#1418 moves or a `claude plugin eval` invocation succeeds.

### Out-of-scope

- Code comments (v1 non-goal; route-out note toward `code-tidying:audit-comment-residue`).
- A per-source hash store (deferred; scanner telemetry feeds the convention's designed-issue
  trigger, expected to fire at the first sweep).
- In-repo duplication (owned by `extract-ssot` and `reference-dont-duplicate`), doc-vs-code drift
  (doc-drift-detector, codebase-health), doc-level worth (audit-derivability), in-flight
  discipline (point-dont-copy).
- Declaring the migration playbook's plugin-eval deferral trigger fired.
- Standing search-API integrations (Bing/Google CSE class); WebSearch enrichment only.

### Deferred questions

- Q19 - Plugin and skill naming (working candidate: `provenance`) - defer until the design phase;
  resolve via /planning:design with /naming:name-it-better; **arbiter: /planning:plan**
- Q16 - Numeric values of the fix-mode precision bar, report-mode recall floor, and minimum n per
  finding class - defer until plan time with S1/S3 measurements in hand; **arbiter:
  USER-RESERVED**
- Q10 - Budget constants (N searches, M fetches per candidate; corpus-level ceiling) - defer until
  S5 telemetry exists; **arbiter: /planning:plan**

## Plan

<!-- populated by /planning:plan -->
