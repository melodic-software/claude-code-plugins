# Changelog

## [0.5.5]

### Changed

- **`audit`:** `reference/rubric.md` drops its version-history preamble and the two in-line
  version notes, keeping the invalidation rule; the editor rule about measurement results moves to
  a new `skills/audit/AGENTS.md`, which also takes the `affected-tests.sh` exit-3 note from
  `context/gotchas.md`. `context/persist-findings.md` states its eight relay-boundary rules in the
  present tense instead of as past bug reports. `reference/nomination.md` drops its rubric-version
  pins, states the judge and review case block once, and trims the reviewer rationale to the one
  fact the Judgment section does not carry. `reference/source-fetch.md` and
  `reference/dispositions.md` drop the research-phase incident, the marketplace-specific generator
  path, and the golden-set starting count. `context/gotchas.md` drops its preamble and the
  8 percent figure.
- **`setup`:** removed the editor-addressed sentence after the fixture-exclusion rule.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1
  (docs/specs/prompt-audit-skills-2026-09.md).

## [0.5.2]

### Fixed

- **`audit`, `setup`:** the git pre-compute lines moved out of `## Pre-computed context` into a
  "Repository context. Gather first" body section of individual Bash calls, one command per call,
  each `head` bound kept inside its command and a failure read as an unknown value. The harness
  composes a skill's whole pre-compute block into one shell invocation, and a worktree-isolated
  session refuses a git-bearing compound command, which blocked these skills from loading inside a
  worktree. Same shape as the worktree skill's fix in #1619. Non-git pre-compute lines stay where
  they were. setup tests for the team config under the literal root the previous call returned.

## [0.5.1]

### Fixed

- **Three statements in 0.4.0 are no longer true, and this entry supersedes them rather than
  editing them.** That entry deferred a fixture leak as "deliberately NOT fixed here", recorded
  four case bodies stating their own answer as a limit that could not be worked around without
  editing a fixture, and said the deterministic layer "reproduced every containment, jaccard and
  matched-span figure the fixtures record". All three are now overtaken: the leaks are removed and
  two jaccard figures moved as a direct result. Dated records are not rewritten here, so 0.4.0
  stands as what was true when it was written and this entry carries what changed.

- **The shared source page for `c08`, `c09` and `c10` named the cases and gave away the answer.**
  It opened by stating it was the shared basis for the three synonym-rotation cases and that
  holding it fixed made rotation density the single variable. Judges read `source.md`, so that
  paragraph settled C1 and C2 before either was graded, and nine of the thirty judges in the
  version-3 re-score read it.

  **The removal and the re-measurement are one change, because the first moves the second.** The
  fingerprint compares the case body against `source.md`, so deleting from the source changes the
  arithmetic those three cases record, and shipping the deletion alone would leave a measurement
  that no longer reproduced from its own fixtures. Containment, longest matched span and the
  matched-span set are unchanged, because the removed paragraph shares no five-word shingle with
  any case body; the union shrank while the intersection did not, so jaccard rises: `c08` 0.232 to
  0.280, `c09` 0.146 to 0.178, `c10` unchanged at zero. Each case still classifies as its
  `expected.json` says, `c09` still on the containment limb alone and `c10` on neither, so the
  density ladder still measures density.

- **Four case bodies stated their own answer, in the graded passage itself.** `c06` and `c07`
  opened "A hard negative", `c08` called the passage below it "the copied passage", and `c10`
  supplied its own C1 and C2 findings outright along with a tier hint. 0.4.0 recorded these as
  accepted because withholding them "would mean editing a fixture" — an objection the fixture edit
  above overtakes. They are removed under the same fix-and-re-measure discipline, and the affected
  `notes.measured` figures are corrected in the same commit: `c06` containment 0.031 to 0.039,
  `c08` 0.473 to 0.570 with jaccard 0.312.

  Two `span` line ranges moved with them. That is a re-anchor, not a verdict change: deleting
  leading lines shifts every line number below, the shift matches the deleted count exactly, and
  the spanned text is byte-identical before and after. No `class` or `tier` field was touched.

- **A weaker date signal could delete a stamp instead of reinforcing it.** `may_form()` reports two
  signals for the month May — a digit beside the word, and a capital M on the original line —
  through a single `RSTART` that all three call sites read to decide whether the match began inside
  the keyword window. It returned on whichever branch matched first, so a digit-adjacent "may" out
  in the window's slack handed back an out-of-window offset, the caller rejected it, and a capital
  "May" sitting inside the window was never consulted: appending a stray "7 may" to "Verified this
  May" removed the line from the candidates entirely. Both signals are now evaluated and the
  leftmost returned, in `check-stamps.sh` and `extract-breadcrumbs.sh` alike, so a signal the
  window would reject can no longer hide one it would accept. Corpus output is unchanged over
  1,352 files: 530 candidates, 499 parsed, 31 declined, 0 findings.

  Swapping the branch order was rejected as a fix because it mirrors the bug rather than removing
  it. The cross-implementation agreement assertion is what let this survive: it compared the two
  scripts' candidate sets and **passed while both were wrong**, agreeing on one where the answer
  was two. Agreement tests are blind to a shared error by construction, and the assertion now pins
  the count rather than only the agreement.

- **The relay boundary leaked through the `## Unparsed` appendix.** A judgment verdict
  (`source-fetched-similar`, `llm-suspected`, `not-found`) carrying no rule id matched no branch in
  the projection and was dumped verbatim into the findings file, tier name and payload included —
  the one file those verdicts are withheld from, and the apply relay's input. Withholding is now
  decided on the **declared** tier ahead of any rule lookup, read from a fixed key allowlist and
  matched exactly against the three verdict names. The record is still counted in `## Surfaces`, so
  nothing is dropped.

  **Reaching that took ten rounds, and for the first nine each fix opened the next hole.** Recorded
  in full because the sequence, not any one defect, is the finding.

  1. The first version matched the tier exactly at the top level. An adversarial probe defeated it
     four ways: a padded `"  not-found  "`, an array-valued `["not-found"]`, an object-valued
     `{"name":"llm-suspected"}`, and a capitalised `"Tier"` key.
  2. Widening it to any key named `tier` at any depth closed those and **silently dropped
     relay-eligible findings**: a `fingerprint-confirmed` copy carrying an unrelated nested tier —
     `"review":{"tier":"one agent argued llm-suspected and was vetoed"}`, a note `SKILL.md` invites
     — was withheld, reaching neither the relay table nor `## Unparsed`, while `## Surfaces` called
     it a judgment finding that stays on a human report it was never on. Seven vectors.
  3. Narrowing to a key allowlist fixed the drop and **relayed a judgment verdict**: the allowlist
     read `verdict.tier` but not `verdict` itself, so `{"verdict":"not-found"}` on a stamp rule
     reached the relay table.
  4. Reading a whole `verdict` closed that and re-introduced the drop from a different direction. A
     `verdict` holds the judges' output while the tier is mapped by fixed rule from the evidence —
     `SKILL.md` step 9, "never from a judge's confidence" — so a confirmed copy beside
     `"verdict":{"prior":"llm-suspected"}` was withheld again, and one shape refused the whole
     sidecar. The same round trimmed invisible characters by enumerating two code points, leaving
     six other `Cf` characters to walk a verdict onto a relay row; an unhandled one at the end even
     neutralised a handled one at the start.
  5. The declared `tier` now wins whenever the record has one, falling back to the `verdict` only
     when it does not — and the fallback turns on the slot **naming** a known tier rather than the
     key merely being present, which is what `{"tier":null}`, `{"tier":[]}` and `{"tier":"pending"}`
     beside a verdict had been slipping through.
  6. The same defect one container down: the `verdict` → `verdict.tier` step still keyed off the
     child being present, so `{"verdict":{"tier":"pending","result":"not-found"}}` declared nothing
     and printed its outcome verbatim. Both steps now share one definition — the first fix in the
     sequence to address the class rather than an instance.
  7. Format characters were stripped only at the ends of a value, so one sitting *inside* the name
     — a word joiner placed mid-word in `not-found` — failed the exact match and relayed. Stripped
     everywhere now.
  8. Stripping was by an enumerated class, which missed a variation selector and a combining
     grapheme joiner. It now strips by the Unicode property that defines rendering as nothing.
  9. Three routes at once. A verdict spelled as a **key** (`{"tier":{"not-found":true}}`) was read
     by neither reader, because both walked string values only. A hyphen homoglyph (U+2010)
     rendered identically to the name it spelled and relayed, so hyphen-likes now fold to ASCII by
     the dash class. And `Location` was the one cell carrying input that was never pipe-escaped, so
     a path like `a|b.md` split the row and a consumer read the Finding cell as a Surface.
  10. The `searched` key was read literally while `tier` and `verdict` were case-folded, so a
      sidecar that **did** name its surfaces under `Searched` was refused whole, taking every
      relay-eligible finding beside it — the one direction that gate has no excuse for failing in.
      And the stamp rules relayed on any tier at all, which falsified round 9's own safety argument
      for the homoglyph limit: a Cyrillic-`о` spelling took a relay row instead of the ordinary
      path. A stamp rule now still relays whatever a record does or does not declare, except when
      its own `tier` field names no tier this reader knows.

  **Every one of these passed review before it was probed.** Across the rounds a bot reviewer, five
  security passes and three code-review passes read this file; all of them characterised the
  failure direction as over-withholding and therefore safe. Over-withholding was destroying
  relay-eligible findings, and the boundary was leaking in two separate rounds. Reading a diff and
  attacking an invariant are different activities, and only the second found any of this. The suite
  went from 110 assertions to 307, the gap being almost entirely the direction nobody was testing:
  that a legitimate finding still **survives**.

  Two limits are stated rather than papered over. A record that is not an object has no declared
  tier to read, so it is withheld when a verdict name appears anywhere inside it — the blast radius
  the malformed-record route exists to avoid. And `source-not-identified`, the neutral tier name
  `SKILL.md` publishes, is not one of the three the reader knows.

  `context/persist-findings.md` required both that withheld tier names never appear and that an
  unmappable finding lands in `## Unparsed` verbatim, never a silent drop, without saying how the
  two coexist — a conflict landing precisely on the leaking record. It now states the ordering and
  names the `## Surfaces` count as where the no-silent-drop guarantee is discharged, so the next
  reader does not restore the leak as a bug fix.

- **The relabeling that kept fixture paths away from judges was a habit, not a rule.** 0.4.0 records
  that the version-3 re-score relabelled cases "so no directory name or path reached a judge".
  Nothing in the plugin required it: a grep across `SKILL.md`, every `reference/*.md`,
  `evals/evals.json` and every script found exactly one mention of relabeling in the whole plugin,
  in that changelog entry. The golden directories are named for their own answers —
  `c06-negative-quoted-and-cited`, `c08-adversarial-rotation-sparse` — so a judge handed a path
  reads the class, the carve-out and the rotation density before opening the file.

  `reference/nomination.md`, which constructs all three subagent prompts, now carries "Neutral
  labels (required)": a case reaches any subagent the run dispatches over it — nominating, judging,
  reviewing, guarding a fix — under an opaque label, and the run holds the label-to-path mapping.
  `SKILL.md` and `reference/dispositions.md` reference the rule rather than restating it.

  Two channels beyond the directory name are closed with it. `SOURCE TEXT` said "fetched bytes,
  with its URL and the rung it came from"; under the vendored-snapshot route and in the golden set
  the source is served from a local file, so that field could hand over an in-repo path. It now
  carries the source's declared URL and route, never the local path. And every golden `source.md`
  opens by naming the golden set and calling the page invented for these fixtures — the answer
  arriving in the body text once the path was shut — so that paragraph is dropped from the copy a
  subagent is handed. `fingerprint.mjs` is not a subagent and reads the file as committed, so no
  containment, jaccard or span figure moves.

  The directories are not renamed: the names carry meaning for the humans maintaining the set, and
  renaming would churn the 30 paths `evals.json` enumerates for no gain over fixing the dispatch.
  Four verifier rounds went into this, three of which failed — the third catching that a fix had
  quietly narrowed the judge prompt to four of the rubric's six carve-outs, which is a grading
  change this work was not allowed to make. It was reverted. The requirement remains unmeasured:
  no `evals.json` expectation asserts that a run relabelled before dispatch.

### Added

- **The `not-found` searched-surfaces listing is schema-checked at the sidecar.**
  `emit-findings.sh` refuses a report sidecar whose `not-found` finding names no surface at all, on
  exit 3, the input-refusal code it already uses for a sidecar that is not audit output. The check
  validates the sidecar rather than an emitted row, and it has to: the relay boundary withholds
  every `not-found` finding from the findings file, so there is no row to check.

  Presence is all it can assert. Nothing knows which surfaces a run actually visited, so a listing
  omitting one it checked is still indistinguishable from a complete one, and a report's listing
  remains the run's own claim rather than validation evidence that no source exists.

### Changed

- **Sweep resume semantics are stated where a run will read them.** The closure ledger is now named
  by its path, `.work/<topic-slug>/sweep-ledger.md`, rather than left to a repo-local spec no
  plugin file pointed at, and the three facts the sweep Brief requires and the shipped docs
  contradicted are recorded: `corpus_fetch_ceiling` is spent across the whole sweep and a resume
  restores its spend rather than restarting at zero; the response cache is per-sweep and a resume
  re-validates an entry rather than reusing a body nobody in this sweep read; the ledger is
  checkout-local, so a sweep resumed elsewhere is a new sweep and reports itself as one.
  `reference/dispositions.md` carries the entry's required fields.

  **No ledger machinery exists, and the prose says so at every mention.** Nothing in this plugin
  creates, reads, or validates that file. These are rules for how a run conducts itself, and they
  hold only as far as the run keeps the ledger honestly.

### Method, and what it does not support

- **The version-3 re-score reported here was not a blind panel, and is not offered as one.** The
  worker that ran it had no subagent tool, so it graded sequentially inline, one pass per case
  rather than three. `c01` through `c07` were graded without their `expected.json` ever being
  opened. `c08`, `c09` and `c10` were graded *after* it, because checking the classification
  against the answer key required reading it; those three verdicts are worth less than the other
  seven and are marked contaminated rather than averaged in silently.

  The result reproduces the recorded table — **8 tp / 0 fp / 0 fn / 2 tn, precision 1.00, recall
  1.00, no verdict moved** — and no class becomes fix-eligible, every one still below
  `min_n_per_class` 10 at n = 2, 5, 1, 2. The arithmetic beside it was re-derived independently and
  holds; it is the *method* claim that is narrower than 0.4.0's.

  `c09` is the control worth noting: it carries no self-describing line, and it graded identically
  to the two that did.

- **This entry now lands above 0.5.0, and every panel figure it reports is pinned to rubric
  version 3.** 0.5.0 moved the rubric to version 4, narrowed carve-out 5, and invalidated the
  version-3 golden-set measurement. The `8 tp / 0 fp / 0 fn / 2 tn, precision 1.00, recall 1.00`
  table restated above, and the "no class becomes fix-eligible" conclusion drawn beside it, are
  therefore superseded by 0.5.0 and are not offered as version-4 claims. This work was authored
  against version 3 and is recorded as it was measured rather than rewritten.

  **What the rubric change does not touch is the deterministic arithmetic.** Containment, jaccard,
  longest matched span, the matched-span sets and the span re-anchors are computed by
  `fingerprint.mjs` over the committed bytes; they read no rubric and no carve-out, so every
  recomputed figure in the entries above stands exactly as recorded. So do the fixture edits
  themselves: an answer key removed from a case body or a `source.md` is a leak closed under any
  rubric version. The golden set still awaits its version-4 re-score, per 0.5.0.

## [0.5.0]

### Changed

- **Rubric version 4: carve-out 5 (distilled-product architectures) gains a span-level qualifier,
  and the version-3 golden-set measurement is invalidated.** Version 3 asked only whether the
  surface's product is a distillation. That question is satisfiable by almost any reference file
  that credits a source, and because carve-outs are graded before the criteria and stop grading, a
  broad reading silently absorbs the C2 and C4 failures the criteria exist to catch. Version 4
  keeps the purpose test and adds the boundary a distilling file draws for itself: **a verbatim or
  near-verbatim span the file's own attribution does not enumerate is not covered**, and
  reformatting (un-fencing a prompt block into prose, tabulating a source's prose) is not
  distillation.

  **The evidence, recorded here rather than in the rubric** (the rubric is inlined into every judge
  prompt, so a measurement written there is read by every judge before it grades). In a repo-wide
  run over 1292 tracked files, carve-out 5 drew **110 of roughly 230 carve-out citations across 138
  panels** — more than double the next carve-out. An adversarial review pass over the unanimous
  clears returned three challenges, two of which attacked carve-out 5 specifically and both on the
  rubric rather than on the file: one on `plugins/playbooks/reference/model-adaptation/opus-5.md`,
  whose own Sources section enumerates which spans are verbatim while the matched block appears on
  none of those lists; one on `plugins/mcp-tools/skills/audit/reference/checklist.md`, whose
  opening line declares a pointer discipline ("do not recap them here, read them at the source"),
  the opposite of a distillation product. The enumerating-file test in version 4 is the first of
  those arguments generalized, because it is the one a judge can apply to a span.

  **Consequences.** The golden set must be re-scored against version 4 before any precision figure
  is cited against it, and no class becomes fix-eligible on a measurement pinned to version 3. The
  version-3 re-score recorded below is superseded. Expect the change to move findings in one
  direction only: spans inside distilling files that were previously declined before grading now
  reach the criteria, where C2 and C4 decide them on their merits.

  This also matters beyond the copy lane. A `restated-upstream-fact` detector of the kind proposed
  in #3525 would inherit this carve-out, and restated facts live disproportionately in exactly the
  distilling files version 3 declined wholesale, so the broad reading would have suppressed the new
  lane before it shipped.

## [0.4.2]

### Changed

- **`audit`: `check-stamps.sh` collapses a duplicate branch in `from_label()`.** The `--*` arm and
  the fallback arm of the three-way conditional printed the character-identical `(from %s)` string,
  so the split carried no behavior. The two arms are now one. Verified over an executed 25-case
  input matrix (flag forms, config-layer paths, format-string hazards, whitespace, multi-arg and
  no-arg calls): old and new outputs are byte-identical everywhere, and the 71-case suite passes
  unchanged.

## [0.4.1]

### Fixed

- **`audit`: the two config probes broke on any install path containing a space.** Both expansions
  were unquoted, so an install under a path with a space in it (a Windows profile directory named
  `<First Last>`, a macOS `Application Support` tree) word-split into two arguments, the script was
  never found, and the guard short-circuited to `detector unavailable` on scripts that are present
  and working. Reproduced by copying a detector into a directory whose name contains a space:
  unquoted renders `detector unavailable`, quoted renders the config, and on a space-free path both
  render it. Both the guard run and the data run are quoted now, matching the form
  `firecrawl:update` already ships.

  Quoting changes the literal command string, and Bash permission rules are globs over that literal
  string, so the existing `Bash(${CLAUDE_SKILL_DIR}/scripts/list-corpus.sh:*)` and
  `Bash(${CLAUDE_SKILL_DIR}/scripts/check-stamps.sh:*)` rules no longer match the quoted
  invocations. A companion quoted rule is added for each. The unquoted rules are kept, because the
  audit flow's own steps 1 and 3 still invoke both scripts unquoted. Each pair names one script
  under the same `${CLAUDE_SKILL_DIR}` anchor with the same `:*` argument scope, so this authorizes
  nothing the plugin could not already run.

### Changed

- **Both config probes adopt the pipefail-proof filtered-probe shape, on shape rather than on an
  observed failure.** `list-corpus.sh --show-config` emits 7 lines against a `head -10` cap, so
  `head` never closes the pipe early, and `check-stamps.sh --show-config` is piped into `tail -3`,
  which drains its input and cannot raise SIGPIPE at all. Both were verified by execution in three
  states under both `pipefail` settings and neither showed any difference: **these were latent by
  shape, not live defects, and nothing observable is fixed here.** The change is that a later
  `--show-config` growing past ten lines would silently start asserting `detector unavailable`
  under a correct detector, which is exactly what happened to `ai-slop:audit`. Confirmed by
  substituting a 500-line detector: the old shape renders 10 lines plus the token under `pipefail`,
  the new one renders 10 lines. The filter pipelines now sit in a brace group closed by `:`, the
  shape `docs-hygiene` 0.21.23 and `code-tidying` 0.14.13 established.

## [0.4.0]

### Changed

- **The version-3 re-score is done, and the measurement carries forward unchanged.** Version 3's
  own rule blocked every precision figure, and with it every class's fix eligibility, on a table
  pinned to version 2. All ten golden cases were re-judged by a three-judge panel each, thirty
  judges in independent processes, cases relabelled so no directory name or path reached a judge.
  Each saw the candidate passage, the fetched source, the whole containing file and the rubric,
  per the version-3 dispatch; none saw the case's `expected.json`, the fingerprint figures, or
  another judge's verdict. The deterministic layer was re-run alongside and reproduced every
  containment, jaccard and matched-span figure the fixtures record.

  Result: **8 tp / 0 fp / 0 fn / 2 tn, precision 1.00, recall 1.00** — the table version 2
  recorded, now pinned to version 3. Every panel unanimous, **no verdict moved.** `c04` is the
  only case whose attribution reaches grading, so it is the only one C3's stated scope could have
  moved, and all three judges took the new test where version 2 left it: the derivation is one
  lift inside otherwise-original material, so a `See also` bullet two sections below understates
  its scope and C3 passes.

  **No class becomes fix-eligible, for the reason that was already there.** Every class measures
  1.00 against the 0.95 bar and every class sits below `min_n_per_class` 10 (n = 2, 5, 1, 2). The
  re-score lifts the rubric-version block and leaves the class-size one standing, which is what
  keeps the sweep in #3465 report-only.

### Fixed

- **The rubric carried its own answer key, and every judge read it.** Version 3's version-history
  paragraph recorded the expected tally, the panel size, and an enumeration of which golden case
  turns on which criterion, including the one case the scope change exists to restate. The
  pipeline inlines the whole rubric into every judge prompt at the judgment step, so all thirty
  judges in the re-score above read the prediction before grading, and that run had to withdraw
  its claim of a blind panel. Found by that run's own fresh-context verifier, which returned FAIL
  on the method while confirming the arithmetic.

  The paragraph was written to keep the figures from sitting under a cloud they did not deserve.
  Putting it in the file judges read at judgment time is what made a blind measurement against
  that rubric impossible. The prediction and the enumeration are changelog material and now live
  here; the rubric keeps the criteria, the carve-outs, the scope rule, the worked examples and the
  tier table, and says explicitly that a judge should be able to read all of it and still not know
  the answer.

  **The verdict was tested against the leak rather than assumed safe.** `c04` was re-judged by a
  second three-judge panel against the same rubric with the version-history preamble removed and
  every criterion, carve-out, scope sentence and worked example intact. All three returned STANDS
  with C3 PASS on the same scope-mismatch reasoning. The leak did not drive the verdict; the claim
  that a fully blind panel produced it is still withdrawn.

  **A second leak of the same kind sits in a fixture and is deliberately NOT fixed here.** The
  `source.md` shared by `c08`, `c09` and `c10` announces itself as "the shared basis for the three
  adversarial synonym-rotation cases", naming them and asserting the local text is a rotation,
  which pre-answers C1 and C2 for nine of the thirty judges. That line is inside the text the
  fingerprint module compares, so removing it moves every containment and matched-span figure
  those three cases record. **The fix and a re-score are one atomic change**, and splitting them
  would leave a recorded measurement that no longer reproduces from its own fixtures. It is filed
  for the round that next re-scores rather than taken now.

  Two smaller limits, recorded rather than worked around. Four case bodies state their own intended
  answer (`c06` and `c07` open "A hard negative", `c08` and `c10` open "Adversarial case"), and
  version 3 requires the judge to read the whole containing file, so those judges saw it;
  withholding it would mean editing a fixture. And `c07`'s `expected.json` explains the case as a
  C1 failure while also recording that the owned-content carve-out applies, which the rubric's own
  order of evaluation makes exclusive. All three judges declined it at the carve-out, which is what
  that order requires. The route differs, the recorded answer does not, and neither the fixture nor
  the rubric was changed to match the run.

### Added

- **The evidence-tier contract now covers a vendored-snapshot basis.** Every tier row gated on
  either a fetched source or no source at all, and the sweep hit a third case the table could not
  express: a finding compared against an in-repo copy of upstream, carrying a declared upstream ref
  and a sync date, reached because every live fetch rung failed. Strong provenance, weak currency.
  It happened at `plugins/playwright/skills/playwright/reference/test-generation.md:80`, where both
  candidate upstream URLs returned 404 and only the committed baseline remained.

  Such a finding now caps at `source-fetched-similar`, records `source.route: vendored-snapshot`
  together with each live fetch that failed and how, and is **never fix-eligible**. The reason is
  the plugin's whole subject: fix eligibility rests on current upstream state, and a snapshot
  cannot establish it. Stale evidence licenses no edit. The tier borrow is declared deliberate
  rather than left to read as accurate, since `source-fetched-similar` is worded for a source that
  was fetched and this one was not; the recorded route is what keeps the report honest about the
  difference. The follow-up is human: re-run the candidate when upstream is reachable or the
  snapshot re-syncs, rather than holding the finding open.

- **The modal "may" is no longer read as a month name.** `may` is a month and an ordinary English
  modal verb, and both stamp detectors matched it bare, so prose like "the first read may raise a
  permission prompt" became a stamp candidate whose date could not be parsed and landed in the
  declined bucket — indistinguishable, to a reader adjudicating that bucket, from a real stamp the
  parser failed on. **19 of the 24 month-name declines carried the word**, measured over 1,352
  files at `--as-of 2026-08-28` on this branch's head.

  That figure is tree-dependent and three different numbers for it appeared during this change,
  which is worth recording rather than tidying away. An earlier draft said 17 of 22, measured
  correctly against a branch base that was two commits behind `main` and therefore missing merged
  changelog entries whose own prose contains the modal; repairing the base moved it to 19 of 24.
  The script comments said 13, which matched no tree. Both are corrected. The lesson is the same
  one 0.3.2 records about this file: a count taken over a corpus that includes this repository is
  a reading at a commit, not a constant, and it needs the commit attached or it will not
  reproduce.

  `may` counts as a date when a digit sits beside it — every date form has one and the modal does
  not — **or** when the original line capitalises it. The other eleven months still match bare,
  because over-reporting into a bucket a human reads is the safe direction and this fix must not
  trade it for under-reporting.

  **The first version of this fix did trade it, and three independent reviewers caught that.**
  Requiring a digit made a digitless stamp vanish: `Verified this May` and `Checked last May
  against the vendor page` stopped matching anything, and the loss was *upstream* of the declined
  bucket rather than inside it — `keyword_window()` returned empty, the caller dropped the line
  before classification, and `is_stamp()` did the same to the inventory. Not declined, not
  inventoried, gone. `Verified in June` was still declined and still visible, so the same shape got
  two different treatments purely because of the modal collision.

  The capital `M` is what fixes it. Both scripts lowercase before matching and so discard the one
  signal that separates these in edited prose. The rule now lives in a named `may_form()` carried
  at all three sites rather than three copied regexes.

  **The case signal was measured on this corpus, not assumed.** At `3c538bcc`, over 1,352 files:
  1,458 lines carry a lowercase `may`, overwhelmingly the modal; 24 carry a capital `May`, of which
  **14 are month dates and 10 are capitalised modals** in table cells, bullets and sentence
  openings; and 34 carry an ALL-CAPS `MAY`, of which **none is a date** — they are permission
  modals. So two costs are accepted knowingly.
  A capitalised modal opening a sentence or a cell now reads as a month when a stamp keyword sits
  in its window, which over-reports into a bucket a human adjudicates. And ALL-CAPS defeats case, so
  a digitless `MAY` date stays invisible; buying it back would mean reading `MAY` as a month, which
  on this corpus means 34 false candidates for a form nobody writes. Both are pinned by tests,
  including one named for the over-report so it is not rediscovered as a bug.

  **A third cost is recorded and left rather than chased.** `may_form()` returns on the digit
  branch, so `RSTART` belongs to that match; when a digit-adjacent `may` sits beyond the window and
  a capital `May` sits inside it, the caller rejects the out-of-window digit match and never
  consults the in-window capital. Appending a stray `7 may` to an otherwise valid line therefore
  removes its candidacy — under-reporting, the direction this fix exists to prevent. No corpus line
  has that shape. Returning the leftmost of the two matches would fix it; trying the capital branch
  first only mirrors the bug, so the obvious one-line swap is not a fix. Both scripts inherit it
  identically, so their cross-script agreement assertion is blind to it, exactly as it was to the
  original regression. Recorded at the rule so the next reader is warned rather than surprised.

  **The suites could not have caught this, which is the part worth keeping.** They assert that both
  scripts return the same count over a shared fixture — an assertion that passes when both are
  equally wrong, which is exactly what happened. A cross-implementation agreement test detects
  divergence and is blind to a common error, and a shared definition is what makes a common error
  likely. The new cases pin a **non-zero** expected count in both suites, so agreement is now
  backed by a known answer rather than by two implementations nodding at each other.

  Corpus effect of the correction, **at `3c538bcc`**: none. Candidates, parsed, declined and
  findings all unchanged at 527 / 499 / 28 / 0, the two JSON products byte-identical, because the
  corpus carried no digitless-May stamp at that commit. The regression was latent there and real in
  principle.

  **It stopped being latent one commit later, and this entry is why.** The paragraph above quotes
  `Verified this May` as an example of the shape, inside a `verified` keyword window, in a file the
  corpus scans. So from the commit that documents the fix onward the corpus does carry a
  digitless-May stamp — the one written to explain that it carried none. Measured at `a827aa58`:
  529 / 499 / 30 / 0 post-fix against 528 / 499 / 29 / 0 pre-fix, an effect of +1 candidate rather than
  none.

  That is the fourth time on this branch that prose about a detector has moved what the detector
  reports, after the stale Phase 6 baseline, the figures that went stale as the entry describing
  them was written, and a count that changed when the branch base was repaired. The rule this file
  keeps relearning is the one it already states: **a count over a corpus that includes this
  repository is a reading at a commit, and it needs the commit attached or it will not reproduce.**
  Every figure in this entry now carries one.

  Three sites changed, not two: both detectors and **the classifier in `check-stamps.sh`**, which
  a single-site fix would have missed and which decides the decline reason a human then reads.
  `check-stamps.sh` and `extract-breadcrumbs.sh` change together and their suites now assert the
  agreement over a shared fixture, because a previous fix in this area landed in one script and
  needed a follow-up commit to reach its sibling.

  Over 1,352 files: declines 45 to 28, month-name declines 22 to 5, 17 lines removed and none
  added. **`parsed` is unchanged at 499 and `findings` unchanged at 0** — the load-bearing numbers,
  because they say no real stamp was reclassified in either direction and none had been masked. A
  real `May 2026` stamp is still detected in both month-first and day-first forms.

  Two adjacent false positives are deliberately left in place and recorded rather than fixed:
  `SC2034` read as a bare year, and `read` matching inside `cache_read_input_tokens`. Both have a
  different root cause (token boundaries, not the month list), and both plausible fixes push toward
  under-reporting: a year-boundary fix shifts `RSTART` into the window machinery two prior commits
  tuned, and excluding `_` from the keyword boundary would stop matching a real stamp that exists
  today: `plugins/work-items/skills/track/actions/add.md:104` carries `"last_checked":
  "2026-04-08"`, which parses now and would be lost. That exhibit is named because the first draft
  of this entry cited an invented one; the verifier checked the repo, found no such token, and
  supplied the real line. The conclusion held, the evidence for it did not.

  The bare-year bucket needs its own designed pass rather than a boundary tweak bolted onto a
  word-sense fix. Of its 23 declines, a token-boundary change repairs exactly one: the rest carry
  years that are already token-boundaried, among them an issue number `#1941` and a glob example
  `photos [2024/**`.

- **The `not-found` searched-surfaces listing is recorded as prose-only and unenforced.** Three
  separate requirements say a run must list every surface it searched before concluding no source
  exists. Nothing checks that: `emit-findings.sh` projects no `searched` array and no budget block,
  and the relay boundary withholds `not-found` findings from the file entirely, so a listing that
  omits a rung is indistinguishable downstream from a complete one. Rather than leave three
  requirements reading as though something enforced them, the docs now say a run's listing is that
  run's own claim and never validation evidence that no source exists, and name what an
  implementing change would need. This repo's house style prefers a recorded limitation to an
  asserted capability.

- **The fix contract warns that a corpus file can be a generator's rendered output.** The sweep
  found one whose authoritative home is `docs/native-surfaces/records.json`, outside the markdown
  corpus, with its rendering marked never-hand-edit. A fix applied to the rendering would edit a
  file its own header forbids editing, and the next regeneration would overwrite it. Dispositions
  now say to check the file head for a generated-output marker and route to the human naming the
  generator's input as the real fix site. No script enforces this check.

## [0.3.2]

### Fixed

- **The window fix landed in one of the two scripts that share the definition.**
  `extract-breadcrumbs.sh:is_stamp` still sliced the keyword window at exactly its length after
  0.3.1 fixed `check-stamps.sh:keyword_window`, so the two disagreed about what a stamp candidate
  is while the audit flow passes the extractor's output to nomination. Measured across every file
  the 0.3.1 fix newly parsed, **five** were short a stamp line the extractor should have
  inventoried: `docs/CLOUD-SESSIONS.md` (3 against 4),
  `docs/conventions/loop-lane/README.md` (4 against 5),
  `docs/topics/fresh-eyes-checkpoint-audit/design/design-resolution.md` (1 against 2),
  `plugins/context-guard/CHANGELOG.md` (4 against 5), and
  `plugins/session-flow/CHANGELOG.md` (7 against 8). All five agree now.

  An earlier draft of this entry said three, because it sampled five of the seven affected files
  and reported the differences it happened to catch as the total. The number here comes from
  sweeping all seven against both versions of the extractor.

  `docs/CLOUD-SESSIONS.md:320` is the worked case, and it is worse than the 0.3.1 one rather than
  a repeat of it. Its date begins at offset 60 of the 60-character window, so the cut left a bare
  `2` and **no** form matched — not even the bare-year fallback that at least kept the 0.3.1 case
  visible in the declined bucket. The line did not decline; it left the inventory entirely, which
  is the quieter failure of the two.

  The same slack-and-start-boundary rule now applies in both: slice `wlen + 9`, require every
  match to begin at or before `wlen`. A regression test pins the real corpus line, with a negative
  control at offset 64 confirming the added slack does not admit a date that starts outside the
  window.

  One property of `is_stamp` is worth recording, because it masked this and will mask the next
  attempt to reproduce it: the function rescans from each keyword in turn, so a line carrying a
  second keyword beside its date (an `as-of` immediately before it, say) matches there regardless
  of what the first window truncated. A fixture written to exercise the boundary must carry
  exactly one keyword, or it passes against the unfixed script and proves nothing. Two fixtures
  written the other way did exactly that here, and a third placed the date by eye rather than by
  measurement; only lifting a real corpus line verbatim produced a genuine red.

  That sentence is also why this paragraph names no literal date. An earlier draft of it quoted
  one as an example of the shape, and the corpus run then reported this changelog as carrying an
  expired stamp, one day over. Prose *about* stamp syntax is indistinguishable from a stamp to a
  mechanical detector, and this file is inside the corpus it documents.

- **The review dispatch could not execute rubric v3 either.** 0.3.0 gave the judge the containing
  file and left the reviewer, which runs when `accuracy.review_agents > 0`, holding only the
  passage, the source text, and the quoted grades. Its job includes checking the C3 grade and
  whether a carve-out was missed; C3 is graded across the file and carve-outs 1, 4 and 5 are
  file-level. A reviewer without the file either declines the check or waves through an
  unsupported C3 PASS — and review is the last stage before fix eligibility, so waving one through
  is what puts an unsupported finding in reach of an automatic edit. The review prompt now carries
  `LOCAL FILE:` on the same terms as the judge prompt.

## [0.3.1]

### Fixed

- **A conforming ISO stamp was declined as a bare year, and a declined stamp is never
  expiry-checked.** `check-stamps.sh` sliced the keyword window at exactly its length (60
  characters, 30 after `read`), which cut through any date that started inside the window but ended
  past it. At `docs/upstream/aihero-course.md:127` the window ended mid-date: `as-of 2026-08-17`
  was read as `2026-08-`, the ISO test failed on the fragment, and the bare-year fallback then
  matched the `2026` it left behind. Declining routes the line into the reported `declined` bucket
  and skips it, so the one thing the script exists to do, compare the date against the currency
  window, never ran on a date that parses perfectly well, and the output said only that the stamp
  date went unparsed.

  The window is now a distance from the keyword rather than a cut through the text. The slice
  carries nine more characters, one short of the longest form the tests match, and every form must
  begin at or before the window length, so the added slack lets a date finish without admitting one
  that starts outside the window.

  Corpus effect at `--as-of 2026-08-28` over 1,352 tracked files, stated as the delta because that
  is the part that stays true: **+7 candidates, +7 parsed, declined unchanged** (month-name and
  bare-year trading 2, as the two below flip), **expiry findings unchanged at 0**. Absolutes
  measured at `fb11cf6a` are 538 to 545 candidates and 493 to 500 parsed, against 45 declined.

  **Those absolutes will not reproduce at another commit, and the reason is worth more than the
  numbers.** This changelog is inside the corpus it measures, so each paragraph added here creates
  new stamp candidates and moves the totals. The figures first published in this entry were taken
  before the entry itself was written and were already stale by the time it shipped: a smaller,
  quieter instance of exactly the staleness 0.2.1 was written to correct. The delta is the durable
  claim; an absolute needs the commit it was taken at, and even then only holds there.

  Two of the seven newly parsed stamps had been declined as bare years
  (`docs/upstream/aihero-course.md:127`,
  `plugins/context-guard/reference/cloud-headless-capture.md:78`); the other five were not detected
  as candidates at all, because truncation left nothing date-shaped in the window. None of the seven
  is expired — the oldest is 40 days, and the oldest parsed stamp anywhere in the corpus is 142 days
  against a 180-day window — so no lapsed stamp had been hidden by this.

  Two new declines appear, both instances of the separate `may` false positive, where the month-name
  test reads the ordinary English word as a month name: `plugins/planning/skills/interview/SKILL.md`
  at line 117 and `plugins/repo-hygiene/skills/clean/context/git-branch-cleanup.md` at line 42. In
  each the word starts inside the window (at offset 60 and 59) and the old slice cut it after one
  character, so the same truncation that hid the ISO dates had been hiding these. That defect is
  untouched here, and reproduces identically on the previous script: it over-reports into the
  declined bucket, which is the direction that stays visible to a reader, and is left for its own
  fix.

  Patch rather than minor: no flag, no output shape and no configuration changes. The counts move
  because the existing expiry check now reaches stamps it had been dropping.

## [0.3.0]

### Changed

- **Rubric version 3: version 2 never said at which scope C3 is graded.** Applying the rubric to
  a real corpus passage surfaced it. Two readers reached the same verdict on
  `plugins/dometrain/skills/grounding/SKILL.md:50-64` at `d7e391da` (containment 0.589, a
  142-token matched span against `Dometrain/mcp@master` fetched 2026-08-28) and disagreed on which
  scope produced it. Under version 2 both readings were available and they resolve in opposite
  directions: grade C3 and C4 both at the file and a majority-adapted file *that carries adequate
  file-level attribution* clears twice; grade both at the span and a well-attributed derived file
  stands every time.

  Version 3 states it: **C3 is graded outward across the whole file, C4 on the passage.** What C3
  tests is whether the attribution's declared scope matches the derivation's — file-scope
  attribution discharges C3 when the derivation is file-wide, and does not when one lift sits
  inside otherwise-original material, where the header understates and the reader misallocates.
  This is a substantive addition, and version 2's "a bare link at the bottom of a long file does
  not attribute a specific paragraph in the middle of it" cuts against it. **C4's half is only
  written down**: its worked examples and its closing replacement test were already
  passage-scoped, so nothing about C4 changes.

  The rejected reading is worth recording because it is the one a judge reaches for: "the
  attribution exists and is complete." That is not the test. It would let a single lift into an
  otherwise-original file escape C3 on the strength of a header line about something else.

- **The judge dispatch could not execute the new rule, and now can.** `reference/nomination.md`
  handed each judge the local passage, the fetched source, and the rubric — never the containing
  file. A C3 graded across the whole file is unanswerable from that, and both the rubric and the
  judge prompt instruct UNKNOWN when the text to quote is absent, so a *conforming* judge under
  version 3 would have graded C3 UNKNOWN on every candidate, stopping every verdict and routing
  every run to the human. The motivating case proves it: the attribution that clears it sits about
  35 lines above the passage. The dispatch now supplies `LOCAL FILE:` and says which criteria are
  graded against which input. Blindness in this panel means blind to the pipeline's own suspicion
  — the fingerprint numbers, the nomination's reasoning, the other judges — never blind to the
  material a criterion is defined over. The lens-diversity stance that read for "whether the
  attribution present already discharges the obligation" was pointing judges at the reading
  version 3 rejects, and now reads for scope match.

  Carve-outs 1, 4 and 5 are file-level judgments too, and were under-supplied by the
  passage-only dispatch before this change. That gap predates version 3; it is closed by the same
  fix.

- **The measurement version 2 stands on does not carry forward.** This file's own rule is that a
  criterion change invalidates any measurement pinned to the prior version, and version 3 adds a
  scope-match test to C3 that can decide a case either way. **The golden set must be re-scored
  against version 3 before any precision figure is cited against it**, and no class becomes
  fix-eligible on a measurement pinned to a superseded rubric. Version 2 took the one exception to
  that rule on the argument that it changed no criterion's substance; version 3 cannot make that
  argument and does not try.

  Said plainly so the figures are not left under a cloud they do not deserve: **no current golden
  case appears to turn on the scope question.** Seven carry no attribution anywhere, one is
  declined at a carve-out before grading, one fails C1, and the single case with attribution is a
  lift inside an otherwise-original file, which resolves identically at either scope. The re-score
  is expected to reproduce 8 tp / 0 fp / 0 fn / 2 tn. It is still required, because the rule keys
  on a criterion changing rather than on a recorded case flipping — and inventing a second, weaker
  exception ("substantive change, but the set does not happen to exercise it") to save a ten-case
  re-score that costs nothing is the bad trade.

## [0.2.1]

### Fixed

- **The Phase 6 corpus baseline is stale: it reports Phase 3 figures.** The 0.2.0 entry records
  1,347 tracked files after carve-outs, 525 stamp candidates, 482 parsed, 43 declined, 0 expired,
  oldest parsed stamp 2026-04-08. All six reproduce exactly at `33dccc59`
  ("corpus, breadcrumb, and stamp scripts, Phase 3 part 1" — the commit that introduces
  `list-corpus.sh`), clean tree, running the scripts as they existed there. They were then carried
  into the Phase 6 paragraph several commits later without re-measuring, so a paragraph presenting
  itself as the Phase 6 measurement reports a Phase 3 one.

  The current baseline, at `619199ee` with `--as-of 2026-08-28`: **1,352** tracked markdown files
  after carve-outs (1,395 considered, 43 declined at path level), **535** stamp candidates,
  **491** parsed, **44** declined at stamp level (20 month-name forms, 24 bare years), **0**
  expired at the 180-day default, oldest parsed stamp 2026-04-08 at
  `plugins/work-items/skills/track/actions/add.md:104`, and 9 findings at a 60-day window.
  `list-corpus`'s path-level `declined: 43` and `check-stamps`'s stamp-level `declined: 44` count
  different populations and are not an inconsistency.

  **Two of those figures are date-relative and expire**, which is why the as-of date is pinned
  beside the commit rather than left implicit. `0 expired at the 180-day default` holds only
  until 2026-10-05 on the current oldest stamp, and `9 findings at a 60-day window` moves daily.
  `check-stamps.sh --as-of` reproduces both at the recorded date. A baseline recorded without one
  is the same staleness this entry corrects, one turn later.

  **The delta is not what a first reading of it suggested.** It is not `main` moving across #3467
  to #3469: those three contribute **+1 in total**, one added file in #3468. #3467 adds 20
  markdown files and contributes **zero**, because every one lands under `evals/fixtures/golden/`
  inside the excluded tree — which is why it raises `considered` by 20 and the fixture decline
  from 3 to 23 while leaving the corpus untouched. The rest of the gap is the four months of
  corpus growth between Phase 3 and now. Separately, `.claude/provenance.json` is first tracked in
  `d7e391da`, so the `excluded_paths` layer postdates the figures in the 0.2.0 paragraph.

  **A note on how the wrong diagnosis was nearly recorded instead**, because the method matters
  more than this particular number. A first pass replayed the carve-out filter across 60 commits
  reachable from `main`, found 1,347 at none of them, and concluded the figure came from no commit
  at all. The originating commits sit on the pre-squash build branch, which the squash-merge made
  unreachable from `main`; the reflog held them throughout. A history replay bounded at a squash
  boundary cannot answer "does this number come from a commit", and reporting that it can converts
  a missing sample into a false negative.

## [0.2.0]

### Added

- **Rubric version 2: an inverted polarity in C3 and C4, caught by blind adjudication.** The
  verdict rule says a finding STANDS only if all four criteria PASS, and it says so three times.
  But C3 and C4 were phrased as questions whose intuitive "yes" is exculpatory — is the
  attribution adequate, does the text transform — and their worked examples labelled that
  exculpatory answer PASS. Read literally, the two halves of the file contradicted each other and
  **no finding could ever stand**.

  Nothing measured was wrong: the version-1 run and the independent blind pass both graded on the
  operative verdict rule rather than the labels, and both returned the same eight positives. The
  defect was in what the file told the next judge to do. Both criteria are now phrased in the
  negative so all four point the same way, the four worked-example labels are corrected, and the
  polarity is stated once, explicitly, at the head of the criteria section. Version 2 carries the
  version-1 measurement forward and says why, which is the single exception to this catalog's own
  invalidation rule.

  Worth recording how it was found: three review passes and a self-check had read this file
  without noticing. What surfaced it was asking an agent to actually apply the rubric with the
  expectations withheld — the first reader with no way to infer the intended answer.

- **A contested class the golden set records rather than settles.** Case `c10` is a copy rotated
  until no five-word window survives. The pipeline classed it `near-verbatim` at tier
  `source-fetched-similar`, on the grounds that a source was fetched and compared; the blind
  adjudicator classed it `paraphrase` at `llm-suspected`, on the grounds that zero lexical
  evidence is available to a reader who does not already know it was rotated. Both readings are
  defensible under the current tier table, which is the finding: a rotated copy with a fetched
  source fits neither tier cleanly. The practical stakes are nil today — both tiers are
  report-only and neither is fix-eligible — so the disagreement is recorded here and carried to
  the growth round rather than resolved by picking the answer that flatters the score.

- **The golden set, the first measurement, and the loop that grows it.** Ten synthetic cases under
  `skills/audit/evals/fixtures/golden/`, one directory each carrying `case.md`, `expected.json`,
  and the `source.md` the case is judged against, so every case runs offline: the source is served
  to the fingerprint module directly and the fetch stage is short-circuited rather than mocked.
  Coverage is two verbatim positives, five near-verbatim, one paraphrase, and two hard negatives —
  a quoted-and-cited excerpt, and the paraphrase-styled-never-copied distractor, which is the false
  positive this detector is most likely to produce. Every fixture describes the same fictional
  build tool the earlier fixtures use. A golden set holding real copied prose would make this
  repository carry the defect the plugin exists to find, in the one tree its own scan is
  categorically forbidden to read.

  **The gate decision table**, from `score-golden.sh` over the run recorded at the same date.
  Classes are the scorer's own grouping: a case's class is its first expected finding's class, and
  a hard negative groups as `negative`.

  | Class | n | Precision | Recall | Gate outcome |
  |---|---|---|---|---|
  | `verbatim` | 2 | 1.00 | 1.00 | report-only (n=2 below `min_n_per_class` 10) |
  | `near-verbatim` | 5 | 1.00 | 1.00 | report-only (n=5 below `min_n_per_class` 10) |
  | `paraphrase` | 1 | 1.00 | 1.00 | report-only (n=1 below `min_n_per_class` 10) |
  | `negative` | 2 | n/a | n/a | report-only (n=2 below `min_n_per_class` 10) |
  | *overall* | 10 | 1.00 | 1.00 | 8 tp, 0 fp, 0 fn, 2 tn, 0 declined |

  **Every class ships report-only, and that is the gate's arithmetic rather than a shortfall.** Ten
  cases across four groupings cannot put any class at n=10, so no class is fix-eligible at v1 and
  the precision column decides nothing yet. The numbers were not tuned to change that and the gate
  was not lowered to meet them: gates bind fix eligibility and release readiness only, never what
  the report shows. `verbatim` and `near-verbatim` reaching n=10 at or above the 0.95 bar is the
  named exit condition of the first growth round. At n near 10 that bar behaves as a ratchet rather
  than as a statistic — one error demotes a class — and that is accepted.

  **What a perfect score here does and does not establish.** It does not say the detector is
  accurate on a corpus. Ten cases were authored at chosen points on the separation curve, and in
  this first round the agent that wrote the expectations is the agent that ran the pipeline, so
  recall is measured against expectations written by the same hand. What it does establish is a
  floor: the deterministic half is genuinely measured, not asserted, and the run would have failed
  the set on any contract violation — a paraphrase promoted to `fingerprint-confirmed`, a hard
  negative that fired, a span the scorer could not overlap. The adjudication loop below is what
  breaks the circularity, because a case converted from a rejected finding is a case nobody
  authored to pass. One limit of the tally is worth stating so it is not read as broader than it
  is: `score-golden.sh` matches on class equality and span overlap and never compares tiers, so
  tier fidelity is pinned by the two new eval cases rather than by this table.

  An independent blind pass was attempted and did not land. A separate agent was given the ten
  `case.md` and `source.md` pairs and the rubric, with the expectations and every lexical
  measurement withheld, so that its verdicts could stand as the run instead of the author's. It
  completed, but no channel was available to retrieve its per-case verdicts, so nothing it produced
  contributed to the table above and the figures are single-agent. Recorded as an open item rather
  than quietly dropped: the first growth round should re-run that pass and record whether a blind
  judge clears both hard negatives, since the distractor in `c07` is the case most likely to
  separate an independent judge from this one.

  **The adversarial synonym-rotation probe (design thread T15) returned a real answer.** Cases c08,
  c09 and c10 share one source page and differ only in rotation density, which makes density the
  single variable. At roughly one substitution every nineteen words the copy is untouched:
  containment 0.473 with a 22-word span, both limbs of the separation rule firing. At one every
  nine words the span limb dies and containment alone carries it: 0.413 with a longest span of 10,
  below the 15-word floor. At one every four words nothing survives: containment 0.0, no matched
  spans, against a source that was fetched and identity-checked, which lands the finding at
  `source-fetched-similar` — a human report, not fix-eligible, and deliberately not
  `llm-suspected`, because a source was in hand.

  Three consequences, recorded rather than acted on. The two-limb rule is load-bearing: dropping
  either limb loses c09. Word-shingling is evadable by an author who intends to evade it, and no
  value of `min_containment` above zero recovers a passage with zero matching shingles, so the
  answer is not a different number on this axis — which is why the constants were left at the
  bundled 0.3 and 15. And c09's containment only clears the threshold because the copy dominates a
  short file; the same rotation inside a long host file would dilute containment toward noise while
  the 10-word spans stayed under the floor, which is the dilution the span axis was added to
  survive and which rotation now defeats. A related note for fix mode: c09's eight matched spans
  are too fragmented to fence an edit against, so `fingerprint-confirmed` is not by itself evidence
  that a fix is applicable.

  **One measured behavior in the quoted-and-cited negative, found blind and then fixed.** The
  blockquote always stripped to nothing, as designed, but a 12-word residue survived at local lines
  19-20 because that fixture's inline quotation opens on one line and closes on the next, and the
  inline-quote stripper worked one line at a time: the opening mark is unpaired on its own line and
  was left in place rather than swallowing the rest of it. `c06` still cleared, the residue sitting
  far below both thresholds with carve-out 3 covering it, and this entry first recorded the gap as
  an accepted measurement. The blind adjudication pass rejected that reading, and it was right to.
  Hard-wrapped prose is ordinary markdown, so the clearance was luck rather than design: the same
  wrapped quotation carried a few words further would have cleared the 15-word span floor and
  fired, on a passage that is quoted and attributed. Inline stripping now runs over the paragraph
  rather than the line. The paragraph is also the bound, since a blank line, a fence delimiter or a
  blockquote line resets the open-quote state, so an unpaired mark or a stray apostrophe still
  cannot reach past the block it sits in, which is the conservatism the per-line behavior was
  protecting. Stripped characters are blanked in place and newlines are kept, so the line count and
  every reported line offset survive untouched and the fix step still has spans it can fence an
  edit against. Measured: `c06` moves from containment 0.100, jaccard 0.045 and a 12-word longest
  span to containment 0.031, jaccard 0.012 and a 7-word longest span, and the other nine golden
  cases do not move at all. The 7 words that remain at line 20 are not quotation residue but the
  citation URL matching the source page's own canonical-location line, and they stay in on purpose:
  a URL naming the source is evidence of attribution rather than of copying. Carve-out 3 keeps its
  reason to exist, because a stripper that follows quotation marks still cannot see a borrowing
  that carries none.

  **Widening the pairing scope exposed two further defects, both caught by review rather than by
  the suite, and both fixed here.** They are recorded because each one is a case of a fix making a
  latent bug reachable, which is the failure mode a widened scope invites.

  First, the closing scan had no word-internal apostrophe guard, though the opening mark has had
  one all along. A single-quoted excerpt containing a contraction closed at the apostrophe in
  "doesn't", leaving the rest of the excerpt in the token stream. Measured on a five-line fixture:
  ten words of quoted upstream text survived, close enough to the 15-word floor that a slightly
  longer excerpt would have fired the separation rule, which is precisely the false positive the
  stripper exists to prevent. The closing scan now skips apostrophes with word characters on both
  sides. The predicate is both-sided rather than the opening guard's one-sided test, because a
  legitimate closer nearly always follows a word (`...opts in explicitly'`) and the one-sided form
  skipped every real closer, stripping nothing at all.

  Second, and the worse of the two, the opening guard tested only whether a word character preceded
  the mark. A possessive following markup — `` `Location`'s ``, `(FILE.md)'s ``, forms this
  repository's own prose is full of — therefore opened a phantom quotation. That was survivable
  while the closing scan stopped at the next contraction; once pairing learned to skip those, the
  phantom ran to the next stray mark instead. Measured across 1,393 tracked markdown files, it
  blanked 16,031 characters in the worst case and whole paragraphs of original prose in 32 of them.
  **Over-stripping hides real copies, so this was the false-negative direction and the more
  dangerous one.** The guard now tests the position: an apostrophe opens a quotation only at the
  start of a paragraph, after whitespace, or after an opening bracket.

  The corpus differential over the same 1,393 files now reports 258 differing, of which 256 strip
  LESS — recovering prose the previous behavior wrongly blanked — and 2 strip more, both in a file
  whose subject is regex quoting patterns and whose extra stripping is a genuine wrapped quotation
  being caught correctly. Line-count drift is zero across every file, and all ten golden cases hold
  their recorded values.

  **`.claude/provenance.json`, this repository's own config, carrying the fixture-tree exclusion.**
  `excluded_paths` lists `**/provenance/skills/audit/evals/fixtures/**`, and that is the whole of
  the file: the separation constants, budgets and gates stay at their bundled defaults because
  nothing measured here justified moving one. The exclusion lives in config and never in
  `list-corpus.sh`, which is the #3041 resolution — an unconditional exclusion would decline the
  fixtures under the eval harness's own config isolation and leave the eval author reading prose
  instead of results. Measured over `plugins/provenance` with the file in place: 33 considered, 10
  included, 23 declined against that one pattern with its reason named.

  **The adjudication-to-fixture loop, in `reference/dispositions.md`.** A finding the human rejected
  and a copy the audit walked past are both measurements the set does not yet contain, and both are
  lost unless they are converted. The section states the conversion in order — synthetic rewrite
  preserving the shape and never the text, the adjudicated verdict rather than the run's,
  registration in `evals.json` before the case counts as landed, and a re-score of the whole set —
  plus the two limits that matter as it grows: a rubric change invalidates every recorded figure
  while leaving the fixtures intact, and cases harvested from a sweep are a biased estimator
  because they are the cases this detector already got wrong.

  **This run is sidecar-only.** `emit-findings.sh` was not invoked and no relay findings file was
  written, because the crosswalk rows for `rule-verbatim-copy` and the two stamp rules land
  separately. No relay file ever carries a rule id with no row behind it.

## [0.1.1]

### Fixed

- **`audit`: both `detector unavailable` fallbacks could not render.** The effective-config probe
  ended `| head -10 || echo "detector unavailable"` and the stamp-config probe ended
  `| tail -3 || echo "detector unavailable"`. `head` and `tail` each exit 0 regardless of what the
  script before them did, so a missing or broken `list-corpus.sh` or `check-stamps.sh` rendered an
  empty line under a label that reads as a detector reporting nothing to report. Verified by
  execution: with each script absent the old shapes rendered `[]` and the new ones render
  `[detector unavailable]`; with the real scripts both still render their config lines. Each probe
  now runs `--show-config` once to `/dev/null` and pipes the second run into the cap, so the `||`
  binds to the script. The double runs cost 10 ms and 17 ms measured on this repository. Every
  subcommand still begins with its `${CLAUDE_SKILL_DIR}/scripts/<name>.sh` path, so the existing
  grants cover each independently. Nothing was widened. Unchanged and pre-existing: the stamp probe
  pipes into `tail`, which `allowed-tools` does not name, though `tail` is one of the Bash tool's
  built-in read-only commands and never prompts.

## [0.1.0]

### Added

- **Five review findings fixed, each verified by execution first.** All were real:

  - **`list-corpus.sh .` reported an empty corpus.** The repository root has several spellings and
    every one means "the whole corpus", but `.` reached the directory-prefix filter as a literal
    prefix, matched no tracked path, and returned zero files with no error. On this repository
    that was 0 instead of 1,353, and it read as a clean repository rather than a broken
    invocation. Every root spelling now normalizes to the empty prefix.
  - **An explicit `"excluded_paths": []` could not clear an inherited exclusion.** Treating "no
    elements" as "key absent" left the earlier layer's value in force, so an overlay could add
    exclusions but never remove one. Presence, not emptiness, now decides whether a layer
    overrides, which is what per-key override actually requires.
  - **`emit-findings.sh` reported success having written nothing.** With `set -e` deliberately
    off, an uncreatable directory or an unwritable path fell through to the "wrote" message and
    exit 0. That is the worst failure a persistence step can have, because nothing downstream
    contradicts it: the audit says the findings are relayed and the consumer never scans a file
    that does not exist. Both writing steps are now checked, with a new exit 5.
  - **Configured separation thresholds never reached the fingerprint module.** The module reads
    no config by design, so a repository that tuned `min_containment` or `min_span_words` silently
    got the bundled 0.3 and 15 — constants that decide which findings become fix-eligible. The
    audit flow now resolves them through the cascade and passes them explicitly, and reports the
    values it used.
  - **`--show-config` did not say which layer supplied a value.** The setup skill promises
    per-value provenance and tells the operator to read it from there rather than parsing the
    layers by hand; listing the layers and the effective values separately did not deliver that.
    Each value is now attributed to its layer, to the overriding flag, or to the bundled defaults.

- **Design artifacts graduated to `docs/specs/`, contract slice pruned.** The
  `copied-external-content` contract slice was pruned before merge per the topic-docs
  contract-slice lifecycle. Its durable half graduated with history preserved:
  `provenance-type-inventory.md` (script contracts, finding record, tier enum, config schema,
  golden-set case shape, draft crosswalk rows), `provenance-capability-matrix.md`,
  `provenance-design-threads.md`, `provenance-plugin-topology.md`, and
  `provenance-convention-engagement.md`. Remaining phases 6 to 8 graduated to the work-item
  tracker. Every in-plugin pointer to the old `docs/topics/` paths was rewritten, so a script
  header names a contract that still resolves.

- **The two skills, their evals, and the leaf-name registration.** `/provenance:audit` (default
  read-only, plus explicit `fix` and `sweep`) and `/provenance:setup` (`check` by default,
  `apply` on request), with 8 and 6 eval cases and a `context/gotchas.md` recording the build's
  real failure history.

  The audit's action router keeps mutation behind an explicit argument, so a bare invocation
  scopes, judges and reports and touches nothing. The untrusted-content spine is carried in the
  fetch step, and the fix flow's pointer-liveness check cites that statement rather than
  restating it, which keeps one contract in the file instead of two wordings of it.

  The setup skill is human-invoked under the setup contract, and the reason is specific rather
  than ceremonial: config decides what the audit is allowed to ignore, so a model proposing its
  own exclusions could quiet its own findings. Its eval set pins the refusals that matter, among
  them declining to hardcode the fixture exclusion into `list-corpus.sh` and correcting the
  premise that raising a gate shortens a report.

  Eval fixtures describe a fictional build tool. A fixture that planted real copied text would
  make the plugin's own repository carry the defect it exists to find.

- **The reference artifacts, the audit's judgment half.** `rubric.md` (shipped at version 1 here,
  corrected to version 2 above before this release closed),
  `dispositions.md`, `source-fetch.md`, `nomination.md`, and `context/persist-findings.md`. Each
  is read at the step that needs it rather than preloaded, so a read-only audit never pays for
  the fix discipline and a run with no fetch never reads the fetch route.

  The rubric states its own boundary first, because the four criterion names resemble fair-use
  factors and the resemblance is misleading: the verdicts are editorial, the remedies are
  maintenance remedies, and a finding says a passage should point at its source rather than
  restate it. It never says a passage is unlawful. Carve-outs are evaluated before any criterion,
  since several of them make the criteria meaningless rather than merely satisfied, and each
  criterion requires a quoted span, with UNKNOWN available when the material needed to quote is
  not in front of the judge.

  Two shapes exist to stop a measurement from lying. Judges are blind to the fingerprint numbers
  and to each other, because a judge told the containment score turns three samples into one
  sample repeated; and the semantic-diff guard reads the before and after without the rewrite
  rationale, because an agent told why an edit was made reliably finds that the edit achieved it.
  Nomination passes union rather than intersect, since intersecting two recall-biased passes
  converts them into a precision filter and discards the recall they were spawned to buy.

  `persist-findings.md` resolves the detector-findings contract through three rungs: the `review`
  plugin's bundled copy when that plugin is installed, the publisher's raw URL otherwise, and a
  refusal to write when neither is reachable. The first rung is new against the ai-slop precedent
  and closes a real gap — fetching a contract from one organization's URL made every offline run
  report-only and pointed a portable plugin at a single publisher.

  The untrusted-content framing spine is carried inline byte-identical at both Phase 4 ingest
  surfaces, with the site tails naming what these surfaces actually attract: fetched
  documentation pages that instruct the reader to copy them, which is the case under audit rather
  than a settlement of it.

- **The five deterministic scripts, the audit's reasoning-free half.** `list-corpus.sh`
  enumerates tracked markdown minus the categorical carve-outs; `extract-breadcrumbs.sh`
  inventories the provenance signals already in a directory; `check-stamps.sh` flags expired
  verification stamps; `emit-findings.sh` projects relay-eligible findings into a conforming
  findings file; `score-golden.sh` tallies case-level precision and recall. Each was written
  test-first and observed red: 223 cases across the five, all passing.

  Three shapes are contract rather than implementation detail. The eval-fixture exclusion reaches
  `list-corpus.sh` through the config layer and never unconditionally, so the eval harness's own
  config isolation lifts it and the fixtures report real findings; making that expressible is why
  the corpus root and the config root resolve separately. Breadcrumbs are emitted per directory
  rather than per file, because a neighbor's citation is what identifies an unfenced copy's
  source. And `emit-findings.sh` enforces the relay boundary: only fingerprint-confirmed copies
  and the two stamp rules may reach a findings file, judgment verdicts are counted in `Surfaces`
  rather than dropped, and their tier names are deliberately absent from the file, since a tier
  name in the apply relay's input invites a consumer to act on a verdict this producer withheld
  on purpose.

  Two findings cost real measurement. **mawk panics at compile time on interval expressions**
  (`{0,4}`), and the panic is quiet enough that the scan simply returns nothing and the script
  still exits 0 — a whole rule silently stopped firing until the corpus run showed zero
  candidates where hundreds were expected. Every regex in these scripts uses explicit repetition
  instead. Second, **"read" is an ordinary English verb**, so at the same keyword window the
  explicit stamp verbs use, prose like "an unconfirmed read of a shipped build" became a stamp
  candidate, and `context-management-2025-06-27` — an API beta identifier, not a date — became an
  expired-stamp finding. Narrowing the window for that one keyword dropped every such case while
  keeping the real `read <date>` forms: declined candidates fell 54 to 43 and the false finding
  went with them.

  Measured over this repository, 1,347 tracked files after carve-outs: 525 stamp candidates, 482
  parsed, 43 declined, 0 expired at the 180-day default (the oldest parsed stamp is 2026-04-08).
  The declined count is the honest report the design asks for and not a defect to tune away — the
  corpus genuinely carries month-name and bare-year stamp forms, and a parser that guessed at
  them would manufacture findings against dates nobody wrote down.

  **These are Phase 3 figures, carried into this Phase 6 paragraph without re-measuring.** They
  reproduce exactly at `33dccc59`. See 0.2.1 above for the current baseline and its as-of date.

- **The fingerprint module, the plugin's one pure library.** Word 5-shingles,
  containment, Jaccard, and contiguous matched spans between a local passage and an
  already-fetched source, behind a thin CLI. It decides nothing: it reports lexical overlap and
  the audit flow maps that evidence to a tier.

  Two behaviors are contract rather than implementation detail, both earned in the spike phase.
  Quotation stripping runs inside the module over the local text before shingling and covers
  inline quotation marks (straight and curly) as well as blockquotes and code fences, because a
  properly quoted and cited excerpt must not read as a copy and a rubric-layer carve-out arrives
  too late. Verdicts are matched spans carrying local line offsets, because whole-file
  containment diluted a real 27-word match to 0.019 on a 2,912-shingle file; the separation rule
  fires on either measure, and the spans are what a fix edits against.

  Written test-first: 21 cases, red before the module existed, with the two amendment fixtures
  named in the output (an inline-quoted excerpt that must strip to zero matched spans, and a
  real-sized file whose planted span must surface while its ratio goes to noise). An unpaired
  quotation mark is left in place rather than swallowing the rest of the line, and a
  word-internal apostrophe is not treated as a quote. The `.test.sh` wrapper exists because CI
  discovers only `*.test.sh`; without it the module would ship with no CI coverage.

- **Plugin scaffold and registration.** Manifest, README, and marketplace entry for the
  documentation-provenance audit: prose in tracked markdown that restates an externally-owned
  fact without a pointer or a conforming stamped record.

  The README carries the boundary against every adjacent owner, the config schema, the fence and
  stamped-record marker forms, and the prerequisites, including what the audit still does when web
  search is unavailable (breadcrumb-only resolution, with the rest landing on the neutral
  `not-found` disposition). The skills, scripts, rubric, and evals land in later phases; the
  contract they build against is the graduated specs under `docs/specs/provenance-*.md`, chiefly
  `provenance-type-inventory.md` and `provenance-capability-matrix.md`.

  The rubric catalog is versioned with this plugin, so a criterion or carve-out change lands here
  and invalidates any golden-set measurement pinned to the prior version.
