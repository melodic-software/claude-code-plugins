# ai-slop: model-era custom additions section

## Brief

### TLDR

- New repo-owned "Model-era additions" section in the ai-slop tell catalog, holding the
  2025-2026 Claude-ism vocabulary layer (load-bearing, seam, the ranked-punchline
  construction, and the researched roster), editable as models progress.
- One new per-occurrence script rule for distinctive multiword phrases; high-FP metaphor
  words join the existing rubric tell's word cues; Tier-C frequency words admitted per-word
  only behind the measured-narrowing gate (most land `recorded-only` or as `vocab_add`
  suggestions).
- Per-entry era, model-attribution, and evidence-grade fields; demotion path to Historical
  indicators; dated model-era record block for maintenance.
- New `phrase_add` config key so consumer repos extend the phrase rule without forking the
  catalog; prerequisite fix for the `rule_allowed()` unquoted-glob bug.
- This repo does not self-exempt: shipped defaults stay neutral and the local backlog is
  worked down via explicit `fix` passes.

### Goal

`/ai-slop:audit` detects and `fix` removes the current-generation (2025-2026, Claude
Opus 5 / Fable era) model-vocabulary tells that Wikipedia's source page and Cursor's unslop
skill have not yet absorbed, from an evidence-graded, dated, repo-owned catalog section that
the owner can extend as new model generations introduce new tics — without flooding
technical corpora whose legitimate vocabulary overlaps the tell list.

### Constraints

- The catalog stays the single rule inventory: the new section lives inside
  `plugins/ai-slop/skills/audit/reference/catalog.md`, sibling to "Cursor unslop
  additions", with its own attribution block (repo-owned, not CC BY-SA-adapted material)
  and its own dated model-era record. D1 is valid only with that record present (validator
  ruling: an undated section would contaminate the attributed corpus's drift claim).
- The catalog's inventory-count line ("65 tells ... plus 7 ...") must be updated to account
  for the new section.
- Density-lane admissions (rule-ai-vocabulary word list) are per-word and must pass the
  catalog's measured-narrowing gate: the density gate stays quiet on legitimate files AND
  the firing files are genuine residue. Measured this run: even the pruned 7-word Tier-C
  core yields domain-literal false positives (`uncommitted`, `dedup`); broad Tier-C = 636
  findings across 1,336 files (47% of corpus). Default expectation: Tier-C words land as
  `recorded-only` entries or README `vocab_add` suggestions, not shipped defaults.
- Evidence grade is wired, not decorative: `locally-observed` entries are eligible for
  `recorded-only` or rubric placement only — never a shipped per-occurrence script rule
  until upgraded to `community-attested` or `measured`. The model-era record's recheck
  consumes the grades.
- `phrase_add` must NOT reuse `cfg_array` (detect.sh:224-231 word-splits multiword
  phrases); use a separator-preserving jq reader (the `rule_allowed_paths` `@tsv`
  precedent) plus a `__VOCAB__`-style runtime-ERE substitution, and document the ERE
  metacharacter contract (existing phrase rules encode apostrophes as `.`).
- Prerequisite: fix the `rule_allowed()` unquoted-glob bug (detect.sh ~line 286; config
  globs undergo shell pathname expansion against the caller's cwd, silently breaking
  `rule_allowed_paths` from other cwds; `**` does not cross `/` as intended) before or with
  the `phrase_add` change.
- Shipped defaults stay neutral (SKILL.md: "Does not weaken rules to pass its own
  corpus"); this repo adds no new entries to `disabled_rules` for these rules. Residual
  density hits on genuine house vocabulary are absorbed via `rule_allowed_paths` or the
  legitimate-hit taxonomy, never whole-rule disables.
- Plugin conventions apply: changelog-parity (edits under `plugins/ai-slop/` publish a
  release: CHANGELOG + version bump), quotation exemption semantics unchanged, catalog
  self-exclusion (in-file marker + this repo's `excluded_paths`) already covers the new
  section file-scoped.

### Acceptance criteria

- catalog.md gains a "Model-era additions" section with: its own attribution/charter
  block; per-entry fields (detectability, applicability, v1, era, models,
  attribution-note distinguishing model-weight vs harness/system-prompt-primed, evidence
  grade); a dated model-era record block in the upstream-drift-record shape citing the
  research evidence; and entries for the researched roster (Tier A/B phrases; the
  ranked-punchline construction as `locally-observed`; Tier-C words as `recorded-only`
  unless a measurement admits them).
- detect.sh ships one new phrase rule wired into PATTERN_RULES, respecting the quotation
  exemption, with the shipped roster pinned to the ANCHORED ERE fragments in Phase 3
  (the "part most people skip" family, "(the|my) honest take", "that.s the unlock" —
  bare "the unlock" and "honest take" bigrams are recorded-only: the bare unlock form
  has a measured in-repo domain-literal false positive). Severity-crosswalk row added in
  the detector-findings convention (with that convention's own CHANGELOG minor bump) and
  mirrored in emit-findings.sh; detect.test.sh covers the rule, the roster-agreement
  sets, and the config-reader failure modes.
- `rule-abstract-metaphor-jargon` rubric entry gains the new metaphor word cues
  (load-bearing, seam, and researched siblings) with the literal-vs-metaphor boundary
  stated per word.
- `phrase_add` config key: documented in README, read via a separator-preserving reader,
  extends the phrase rule's ERE at runtime; `--show-config` reports it; tests cover a
  multiword phrase surviving the cascade.
- `rule_allowed()` glob bug fixed with a regression test (exemption honored from a
  non-root cwd; `**` crosses `/`).
- rewrite-guide.md gains replacement guidance for the new phrase/word classes.
- The audit SKILL.md and README document the new section, the evidence-grade wiring, and
  the update workflow; CHANGELOG entry + version bump per changelog-parity.
- A repo-wide `detect.sh` run after the change lands shows the expected bounded delta
  (phrase rule ~0 findings on current corpus; no density flood), demonstrating D4 holds.

### Captured assumptions

- The archiewood frequency pool's ratios are directionally right but single-pool
  (author-declared confounds) — revisit if a second independent measurement lands, which
  may promote Tier-C words past `recorded-only`.
- The "load-bearing" harness confound (system-prompt priming) is mirror-attested only —
  revisit at each model-era recheck; if Anthropic publishes the CC prompt or changes it,
  update the attribution note.
- Wikipedia and Cursor have not absorbed the 2026 Claude-ism layer (verified at head
  2026-08-26 / 2026-08-02) — revisit at each recheck; upstream absorption may let entries
  migrate from the custom section to the Wikipedia-derived inventory.

### Out-of-scope

- Bulk shipping the Tier-C frequency cluster as default density words (validator-refuted;
  47%-of-corpus flood under the broad list).
- The exact phrase "preexisting gaps" as an entry (unattested; the word "pre-existing" is
  handled per the density-lane gate).
- A dedicated refresh skill (a hypothetical `refresh-vocab` addition to the ai-slop
  plugin; considered and rejected) — the dated record + release recheck covers the
  cadence at current update frequency.
- De-slopping this repo's existing 200+-file backlog in this change (worked down in later
  explicit `fix` passes).
- LinkedIn-slop cluster and other single-SEO-source Tier-E candidates (LOW confidence, no
  corroboration).

### Deferred questions

- Q8 — Which (if any) Tier-C words pass the measured-narrowing gate into the shipped
  density list, given validator A's domain-literal findings even on the pruned core —
  defer until implementation runs the per-word measurements; **arbiter: /planning:plan**
- Q9 — Whether "belt and suspenders" (community-disputed as a tell) gets a rubric note or
  is left out entirely — defer until the entry is drafted against the research's dispute
  evidence; **arbiter: /planning:plan**

## Plan

Standards grounding: plugin conventions from the ai-slop plugin's own surfaces (SKILL.md
neutrality rule, catalog calibration record, changelog-parity from `.claude/ai-slop.json`'s
own comment); `.claude/rules/vendor-docs-are-not-style.md` (house style owned by this very
skill — all new prose must pass its own detector); detector test conventions from
detect.test.sh's header (inline fixtures, config isolation). No repo-level standards index
found beyond these.

Test strategy: extend the self-contained detect.test.sh suite (no external lib, inline
tmpdir fixtures, empty-HOME config isolation). Test boundaries, all existing: the
`detect.sh` CLI surface (existing — findings/decline/summary output contract), the config
cascade (existing — per-key layered reads), and the new `phrase_add`/`phrase_remove` keys
(introduced — driven through the same CLI, no new test-only interface). Red-Green where
practical: write the failing phrase-rule and glob-bug tests first, then implement.

### Phase 1: Fix the rule_allowed() glob-expansion bug [TODO]

- detect.sh `rule_allowed()`: replace the unquoted `matches_glob "$file" $globs` with a
  `read -r -a` split into an array (read does not pathname-expand) and a quoted
  `"${arr[@]}"` call. Note the bug bites hardest FROM the repo root (where globs
  expand against real files); `em_dash_allowed_paths` feeds the same path and is
  equally affected — the CHANGELOG behavior-change entry names both keys.
- detect.test.sh: regression tests — (a) a `rule_allowed_paths` glob honored from a cwd
  where the fixture makes pathname expansion actually occur (create files the glob
  expands to, so the test tests something), and from a nested path under a `**` glob;
  (b) pin the deliberate widening: `docs/*.md` matches `docs/sub/deep.md` (bash case
  fnmatch has no FNM_PATHNAME — `*` crosses `/`; tested so it is documented behavior,
  not an accident). Exemptions count as declined.
- README: document the glob semantics for all path-list keys ("shell case-match globs:
  `*` and `**` both cross `/`; not gitignore globs").
- **Sanity Check:** `bash plugins/ai-slop/skills/audit/scripts/detect.test.sh` exits 0
  including the new regression cases; `grep -n 'matches_glob "\$file" \$globs'
  plugins/ai-slop/skills/audit/scripts/detect.sh` returns no match.

### Phase 2: Catalog section — Model-era additions (repo-owned) [TODO]

- catalog.md: new H2 section after "Cursor unslop additions" with:
  - Charter/attribution block: repo-owned inventory (not CC BY-SA-adapted material; the
    license statement already scopes itself to adapted material), per-entry community
    sources cited, explicit editable-as-models-progress charter, evidence-grade
    vocabulary defined (`locally-observed | community-attested | measured`) with the
    placement gate stated (locally-observed → `recorded-only`/rubric only).
  - `rule-model-era-phrases` entry (script; wording class): distinctive phrase
    constructions with era/model/attribution fields. Shipped roster = exactly the
    anchored EREs pinned in Phase 3; the bare "the unlock" and "honest take" bigram
    spellings are recorded in the entry as recognized-but-not-shipped (measured
    domain-literal FP for the bare unlock form; blog-register human usage for the bare
    honest-take form). Ranked-punchline construction ("N observations, and one is
    load-bearing") catalogued `recorded-only` (evidence: locally-observed — zero
    indexed attestations; components documented).
  - Entry layout pinned for the count check: one `### rule-` heading per tell
    (`rule-model-era-phrases`, `rule-belt-and-suspenders`, the ranked-punchline
    entry); the Tier-C vocabulary words grouped under ONE `### rule-` heading
    (`recorded-only`, the rule-ai-vocabulary word-list pattern), each word with its
    single-pool caveat and promotion criterion.
  - "belt and suspenders" entry, `recorded-only`, with the community dispute recorded
    (HN commenters attest pre-LLM usage; density-only if ever promoted).
  - Tier-C vocabulary entries (`gating`, `dedup`, `pre-existing`, and the researched
    cluster) as `recorded-only` with the single-pool caveat and per-word promotion
    criterion (the measured-narrowing gate); pointer to README `vocab_add` suggestions.
  - Word-cue additions to `rule-abstract-metaphor-jargon`: "load-bearing", "seam", each
    with its literal-sense boundary written BROADLY — covering term-of-art use in
    architecture/testing prose (a Feathers seam, a load-bearing invariant named as
    such deliberately), not just the wall metaphor — and stating explicitly that
    saturation-level house usage is a fix-pass decision, never a per-audit re-report
    (this repo: the cues land on 496 of 1,361 files, 36%, measured; the rubric layer
    has no config lever, so the boundary text is the only suppression surface).
  - Currency notes on the existing `rule-chatbot-artifacts` entry ("You're absolutely
    right!", "Found the smoking gun": 2026 prominence, suppression-resistance evidence,
    Anthropic's own acknowledgment).
  - Model-era record block (upstream-drift-record shape): dated 2026-08-26 entry citing
    the research evidence (HN 48905248, archiewood/claudeisms, Suppa measurement,
    anthropics/claude-code#53454, Velitchkov, crystl.dev), the harness/system-prompt
    confound (mirror-attested), and the recheck trigger (each ai-slop release or new
    frontier model, AND "check whether a second independent Tier-C frequency pool has
    landed" — the promotion condition no recheck would otherwise look for).
  - Update the Inventory count line to account for the new section's entries.
- **Sanity Check:** `grep -c '^### rule-' plugins/ai-slop/skills/audit/reference/catalog.md`
  equals the sum of the counts stated in the Inventory section (currently 65+7=72;
  post-change 72 + the new `### rule-` headings per the pinned layout above);
  `grep -n 'Model-era additions' plugins/ai-slop/skills/audit/reference/catalog.md`
  hits the section, the attribution block, and the record block.

### Phase 3: Detector — phrase rule + phrase_add/phrase_remove [TODO]

- detect.sh: `MODEL_PHRASES` array holding the shipped roster as ERE fragments —
  **pinned here, the single source for every other mention in this plan**:
  `the part most people skip`, `(the|my) honest take`, `that.s the unlock`
  (apostrophes as `.` per the file's convention; anchored forms only — the bare
  bigrams are recorded-only in the catalog).
- Config plumbing: `phrase_remove` filters the array; `phrase_add` appends (both read
  via a separator-preserving jq reader — the `@tsv`/`join("|")` precedent, with the
  mandated CR-stripping — never `cfg_array`); joined into `__PHRASES__`, substituted in
  the pattern loop like `__VOCAB__`; new PATTERN_RULES entry
  `rule-model-era-phrases|phrase match|1|1|wording|__PHRASES__`; `--show-config` reports
  the effective phrase list; cascade semantics documented as replace-wholesale per key
  (the vocab_add precedent).
- Fragment hygiene (measured failure modes, both reproduced): drop empty/whitespace-only
  fragments (an empty alternation branch matches EVERY line — flood); probe each
  remaining fragment for ERE validity at config-read time (`grep -E --` against
  /dev/null; on exit 2, warn on stderr naming the fragment and layer, and skip that
  FRAGMENT, not the rule — an unbalanced paren otherwise silently kills the whole rule
  into an indistinguishable `findings=0` Summary row).
- Tier: pinned **SUGGESTION** (register preference among working phrasings — the
  significance-inflation walk), so the emit-findings.sh `rule_tier()` unknown-slug
  default is correct by construction; add the rule's rewrite action to `rule_action()`.
- Detector-findings convention (source of truth for the crosswalk,
  `docs/conventions/detector-findings/README.md`): add the argued row for
  `rule-model-era-phrases` in the convention's admission-test form, plus the
  convention's own CHANGELOG minor entry (2.6.0 → 2.7.0 per its "new adopter row is a
  minor bump" rule).
- detect.test.sh: phrase fires on an inline fixture; quoted/backticked mention declines
  via the quotation exemption (assert `declined=1` in the rule's Summary row — no
  per-candidate `Declined:` row exists for quote exemption); `phrase_add` multiword
  phrase survives the cascade (the cfg_array word-split trap under test); a CRLF-jq
  shim case for both new readers (the #3343 regression class — join the existing
  CRLF section); `phrase_remove` silences a shipped phrase; `disabled_rules` disables
  the rule; empty-roster guard; invalid-fragment case (shipped roster keeps firing,
  stderr names the fragment); empty-string-element case (no flood); extend the
  roster-agreement expected sets (`EXPECTED_SUGGESTION`) for the new rule; catalog
  consistency assertion — within the Model-era section, `evidence: locally-observed`
  never co-occurs with `v1: script` (the evidence-grade gate survives future edits).
- **Sanity Check:** detect.test.sh exits 0 with all new cases; a tmpdir fixture
  containing "that's the unlock" yields a `rule-model-era-phrases` finding; the same
  text double-quoted yields `findings=0 declined=1` in that rule's Summary row;
  `grep -n 'rule-model-era-phrases' docs/conventions/detector-findings/README.md` hits
  the crosswalk row and `head docs/conventions/detector-findings/CHANGELOG.md` shows
  2.7.0.

### Phase 4: Docs — README, rewrite guide, SKILL.md [TODO]

- README.md: document `phrase_add`/`phrase_remove` (ERE-fragment contract, apostrophes
  as `.`, replace-wholesale cascade semantics, the malformed-fragment behavior — invalid
  fragments are skipped with a stderr warning), the glob semantics note from Phase 1,
  the evidence-grade wiring, the section's UPDATE WORKFLOW (how the owner adds a phrase
  as model eras progress: catalog entry with grade + measurement, then detector roster
  if grade and measurement admit it, then record-block entry), a "suggested vocab_add
  candidates" list for the Tier-C words that did not ship (one-line reason each), and a
  note that rubric word-cues have no config lever (advisory; the catalog boundary text
  is the suppression surface).
- Setup surface (pre-flight consumer sweep, verified consumers): `skills/setup/SKILL.md`
  key table + misconfiguration-validation list gain both new keys; the config-cascade
  convention's adopter row for ai-slop (`docs/conventions/config-cascade/README.md`,
  "Two list keys...") updated to name the phrase pair.
- rewrite-guide.md: replacement guidance for the new classes — metaphor words
  (load-bearing → name what actually depends on it; seam → the concrete interface/file),
  phrase constructions (ranked punchline → state the observation without self-ranking;
  "honest take" → delete the opener; "the unlock" → name the mechanism).
- SKILL.md purpose line: extend the catalog-sections mention to include the model-era
  section; check plugin.json `description` and SKILL.md frontmatter `description` for
  the same currency (they enumerate tell families).
- **Sanity Check:** `grep -n phrase_add plugins/ai-slop/README.md
  plugins/ai-slop/skills/setup/SKILL.md docs/conventions/config-cascade/README.md`
  hits all three; `grep -n 'load-bearing'
  plugins/ai-slop/skills/audit/reference/rewrite-guide.md` hits the new guidance;
  detector run over README.md and the audit SKILL.md reports zero new findings
  (catalog.md and rewrite-guide.md are exclusion/marker-covered and verify as declined,
  not as scanned-clean).

### Phase 5: Calibration, changelog-parity release [TODO]

- Repo-wide detector run (chunked per SKILL.md) before/after; record the delta in the
  catalog's calibration record as a dated fourth pass (expected: phrase rule ~0 findings
  on this corpus; no density change since no Tier-C word ships by default), AND the
  rubric-cue base-rate counts (load-bearing/seam file and occurrence greps) alongside —
  the rubric layer carries this change's real cost and the detector delta alone would
  measure the wrong layer.
- Per-word measurement for the deferred Q8 candidates (`pre-existing` first): run the
  detector with the word in `vocab_add` over the corpus; admit into the shipped list
  only if the density gate stays quiet on legitimate files AND firing files are genuine
  residue; otherwise the catalog entry stays `recorded-only` with the measurement cited.
- CHANGELOG.md entry (new section, new rule, new config keys, glob-bug fix, evidence
  citations) + plugin.json version bump 0.4.2 → 0.5.0 (additive feature + fix; the
  0.4.0 three-new-rules release is the size precedent). The entry states that new
  findings will appear (the 0.4.0 wording precedent) and carries the glob-fix
  behavior-change note naming BOTH `rule_allowed_paths` and `em_dash_allowed_paths`.
- Run repo toolchain checks on touched files (shellcheck/shfmt on detect.sh and tests,
  markdownlint on edited markdown).
- **Sanity Check:** `jq -r .version plugins/ai-slop/.claude-plugin/plugin.json` prints
  0.5.0; CHANGELOG head names 0.5.0; `shellcheck plugins/ai-slop/skills/audit/scripts/detect.sh`
  exits 0; the before/after finding counts are recorded in the calibration record.

## Blast radius

MEDIUM — the plugin ships to consumer repos and the change touches the deterministic
detector plus its config contract. Mitigations: everything is additive behind neutral,
measured defaults (new phrase rule ~0 hits on a 1,359-file corpus; no default density
additions), the config keys are new (no existing consumer config can break), and the one
behavior change to existing plumbing (glob-bug fix) makes a documented feature work as
documented (strictly widens exemptions to where they were already configured).

## Stress-test summary

Both fresh-context passes ran 2026-08-27 against the draft and their confirmed findings
are folded into the phases above. Plan-reviewer: 1 CRITICAL (roster-agreement tests +
emit-findings tier mirror unaccounted — now in Phase 3), 4 IMPORTANT (convention
CHANGELOG duty, consumer sweep for setup/config-cascade surfaces, roster-form
inconsistency, CRLF-jq regression case), 5 SUGGESTION (all folded). Devils-advocate
(verdict: plan survives with revisions): 3 HIGH — the bare "unlock" form fails the
plan's own ~0-findings criterion on a measured in-repo domain-literal hit (roster now
pinned to anchored forms), phrase_add fragment flood/silent-kill failure modes
reproduced by measurement (fragment hygiene + tests now in Phase 3), rubric cues land
on 36% of this corpus with no config lever (boundary text broadened, suppression story
documented, rubric base rates added to Phase 5's evidence); 3 MEDIUM and 3 LOW folded
(anchored honest-take form, glob-semantics documentation naming both keys, convention
row/tier pinning, entry-layout pinning, version-bump precedent confirmed, recheck line
for a second Tier-C pool). Both validators independently confirmed the glob-bug
diagnosis and fix shape.

## Execution shape

Fully sequential, all main-session — each phase's output feeds the next (bug fix gates
the config-plumbing change; catalog roster gates the detector list; detector gates docs
and calibration), file sets overlap (detect.sh in Phases 1 and 3; catalog.md in Phases 2
and 5), and total delta is small (~400 LOC). No parallelism opportunity worth agent
overhead.

| Phase | Surface | Basis |
|---|---|---|
| 1-5 | main session | tightly coupled, judgment-heavy content work; sequential dependencies |

## Open questions

- Q8 (deferred, arbiter: this plan) — resolved into Phase 5's per-word measurement gate:
  no Tier-C word ships by default; each is admitted only by its own measurement.
- Q9 (deferred, arbiter: this plan) — resolved: "belt and suspenders" enters as
  `recorded-only` with the dispute recorded (Phase 2), not as a rubric cue.

## Handoff to implementation

### User-approval gates

- None beyond plan approval — the user pre-delegated ("audit-answers and then go with
  recommended"); all decisions below are [EXEC-SHAPE] within briefed scope. Flag any to
  change.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Sequential main-session execution (table above).
- [EXEC-SHAPE] `phrase_remove` added alongside `phrase_add` (symmetry with
  vocab_add/vocab_remove; closes "consumer disputes one shipped phrase" without
  whole-rule disable).
- [EXEC-SHAPE] Rule slug `rule-model-era-phrases`; section title "Model-era additions
  (repo-owned)".
- [EXEC-SHAPE] Version bump minor (0.5.0): additive rule + config keys + bug fix.
- [EXEC-SHAPE] Ranked-punchline construction ships `recorded-only` (locally-observed
  grade gates it out of the script rule per the Brief's evidence-grade wiring).

### Mechanical work

- One commit per phase (or Phases 1+3 combined if the detector diff reads better
  together), each with passing tests; changelog-parity commit last.
- Sequential fallback: not applicable (already sequential).
- PLAN.md phase tags advanced per phase; deviations logged to DEVIATIONS.md beside this
  file if any boundary not named here is introduced.
