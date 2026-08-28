# Changelog

All notable changes to the `mutation-testing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.10]

### Changed

- **Dynamic-context probe fallback made reachable.** The working-tree-status injection piped its
  probe into `head` before `||`, so the fallback could never run and a failed probe rendered an
  empty string under a label that reads as a clean tree. The fallback now sits in a brace group with
  the probe and the cap applies outside it. Whole-repo extract-ssot sweep.

- **Findings-file producer preamble normalized against its contract.** The four
  `persist-findings.md` preambles now carry byte-identical text apart from the run-name slot. The
  fifth producer surface, `testing:audit`, keeps its own shorter numbered-step form by design and
  regains the three load-bearing clauses it had dropped, including that the contract wins where the
  two disagree. Whole-repo extract-ssot sweep.

## [0.3.9]

### Changed

- **Long reference files carry a `## Contents` index.** 1 reference file in this plugin gained one.

  The predicate is `audit-progressive-disclosure`'s own: a reference file over 300 lines with no
  table of contents, which both official sources agree on by that length. Scope came from the
  detector's tier classification rather than a line count, so `SKILL.md` files are excluded by
  construction: they are invocation tier, not the on-demand reference tier the rule names. Files
  with fewer than five H2s were held out, because a three-row index on a long file earns nothing and
  the doctrine offers a grep recipe instead. Purely additive, with anchors generated from each
  file's own headings and verified to resolve. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.3.8]

### Changed

- **`audit`'s report template and restoration regimes move to spokes.** The report skeleton is
  artifact shape read at the start of Phase 5, so it is now `skills/audit/templates/report.md`.
  Phase 3's restoration-verification detail and its three mutant-write regimes are now
  `skills/audit/context/restoration-regimes.md`. Phase 3 keeps the per-mutant loop, the
  verify-the-revert requirement, and the not-delegated rule in the body, so the requirement is
  stated where the run meets it and the spoke owns only how it is proved. Docs-hygiene sweep,
  L2-progressive-disclosure.

## [0.3.7]

### Changed

- **The scaling-and-suppression pointer front-loads its subject (`principles`).** A reader matching
  on "scaling" or "suppression" had to read the filename to learn the pointer was for them.
  Docs-hygiene sweep, L7-write-for-agents.

## [0.3.6]

### Changed

- **Instruction-surface de-slop (#2891, mutation-testing cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change.

## [0.3.5]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.3.4]

### Changed

- **`audit`: the failing-test diagnosis chain names the Skill tool (#3002).** "Run
  `/testing:diagnose` when the `testing` plugin is installed" became "Invoke `/testing:diagnose`
  via the Skill tool …". Wording only; the presence gate and the diagnose-manually fallback are
  unchanged. The `/mutation-testing:setup` arrows stay prose — `setup` is
  `disable-model-invocation: true` and unreachable from a skill by the rubric's invocation-reach
  invariant.

## [0.3.3]

### Changed

- **The permissive-branch guard rule becomes a pointer.** `--persist-findings` skips the self-ignore
  guard where no checkout is detected as governing the destination; that rule now belongs to the
  [topic-docs convention](../../docs/conventions/topic-docs/README.md) "Runtime guards", which owns
  the guard, so the spoke cites it instead of deriving it locally. Behavior is unchanged — the rule
  moved to its owner, where it binds every consumer of that guard rather than this plugin alone.

## [0.3.2]

### Fixed

- **Eval case 3 now grades the node-kind bar it was supposed to grade (#2681).** 0.3.0 added the
  requirement that an arid verdict's proposed suppression entry bind a node kind from the closed
  vocabulary, but case 3's expected output asked only for "a complete entry whose reason names the
  behavior". A five-key entry carrying `claim: arid(logging noise here)` — free prose, no `kind=` —
  satisfies that wording while both Phase 4 and `context/suppression.md` reject it, so the eval
  passed an implementation the contract fails. It now requires the `claim` to bind a node kind and
  says outright that free prose fails even when the entry is otherwise complete.
- **Eval case 11's prompt and expectation disagreed, and the PROMPT was wrong.** It said "one arid"
  unqualified while the expectation asserted no row for the *demonstrated* arid survivor and exactly
  two rows — so an implementation reading the prompt correctly answers three rows and fails the
  rubric. The prompt already qualified the equivalent survivor's evidence status and not the arid
  one; that asymmetry is the defect. Qualifying the prompt keeps the expectation grading the
  contract, where patching the expectation would have made the suite agree with whatever shipped.
- **The aridity bar is stated one way rather than two.** 0.3.0 tightened it in Phase 4 and the
  crosswalk row but left the weaker form in the Gotchas bullet, which flatly called the bar a
  judgment about value where Phase 4 now says **otherwise** a judgment about value — the membership
  test being what makes it checkable. The bullet carries the same qualifier.
- **A two-hop pointer now names each owner directly.** The node-kind vocabulary is enumerated in the
  `principles` skill's `scaling-and-suppression.md`; `context/suppression.md` owns the rule that a
  survivor fitting none is not arid. Phase 4 previously attributed both to the latter.
- **Phase 4's own disposition table now states the arid bar it sits above.** Its `Downstream` cell
  read "propose a suppression entry, with a reason" — the pre-0.3.0 rule — while the bar twenty
  lines below required a node kind. A reader who takes the table as the summary got the superseded
  answer.
- **Four guard-conditioning statements restored after a merge reverted them.** The round that made
  the self-ignore guard conditional on a governing checkout being found landed in 0.2.0, and a later
  merge whose branch predated it silently reinstated the older unconditional wording on four
  surfaces: eval cases 9 and 13, this skill's read-only contract clause, Phase 6's invariant
  statement, and the plugin README's audit row. Two were **graded** artifacts, so the suite was
  certifying the behavior that round removed. Text restored from the merged commit rather than
  retyped. The detailed spoke was untouched, which made this worse rather than better: the summary
  and graded surfaces a reader meets first were wrong while the reference they consult last was
  right.

## [0.3.1]

### Fixed

- **`principles/reference/tooling.md` no longer names `--since` for Stryker4s (#2749).** That flag
  belongs to Stryker.NET only. Stryker4s has no git-diff scoping switch (re-verified against the
  Stryker4s configuration options list on 2026-08-15); the table now says `none` so Phase 2 does
  not invent a flag and fall back to a whole-project run. StrykerJS was already correct as
  `--incremental` (with `--incrementalFile` noted). When the flag is `none`, Phase 2 uses the
  manual protocol unless the tool can express Phase 1's changed-line scope — a file-level
  `mutate`/path selector alone is not enough.
- **Same table gains a Write-regime setting column** for Phase 0 of `/mutation-testing:audit`: the
  per-tool key to read (`inPlace` for StrykerJS) or `none — …` when the regime is a constant
  (Stryker.NET, Stryker4s, Infection by option enumeration; PIT's documented in-memory guarantee;
  mutmut's ≤2.x / ≥3.0.0 execution-model boundary). The column resolves the full three-way regime
  Phase 0 needs (out-of-tree / in-tree whole-file / in-tree per-mutant), not only out-of-tree vs
  in-tree. Evidence classes stay separated per row rather than blended into one cross-tool claim.

## [0.3.0]

### Added

- **Every persisted row leads its `Finding` cell with the rule id and the threshold that fired
  (#2681).** The Phase 4 verdict class now selects a named contract rule —
  `mutation-testing/audit/rule-survivor-productive`, `-unclassified`, `-arid`, `-equivalent` — and
  the rule, not this skill, decides the tier. Severity becomes auditable from the emitted file alone:
  a reader checks the row against its crosswalk entry with no return trip here. The id is written in
  full every time; the contract defines no short form, because an emitted id is resolved against a
  crosswalk row by exact match. It is **not** the `check:` value this skill's suppression proposals
  use — that keys to the mutation operator, deliberately finer, because a suppression retires per
  mutant while a rule classifies a disposition.
- **Declined candidates are reported as counts per rule id** in the returned-no-result limb of
  `## Surfaces`, so an equivalent or arid survivor is visible as coverage and readable as a trend
  across runs. Per-mutant equivalence rationale stays in the Phase 5 report to the human, where an
  argument belongs; the findings file carries the artifact.

### Changed

- **Phase 4's evidence bar now binds BOTH withholding verdicts, not only equivalence (#2681).** Arid
  and equivalent are the two classes that withhold a survivor, and only equivalence had to cite
  anything; an arid call could be asserted from inspection. Arid now requires a complete proposed
  suppression entry — all five keys, id derived — whose `reason` names the specific behavior the
  suite deliberately does not assert on, and a withholding verdict of either kind that cannot cite
  its evidence is reported *unclassified*, which emits. Aridity was the easier label to reach for
  precisely because its bar was a judgment about value rather than about observable behavior.
- **The bar sits at classification, so one survivor has ONE disposition.** Placing it at persist time
  would have split a single run in two: Phase 5 reports before Phase 6 persists, so the report would
  say "arid" while the findings file said "unclassified" for the same mutant, with nothing to explain
  the contradiction to an operator reading both. At classification, Phase 5 and Phase 6 speak from
  one verdict — and the bar binds a bare run too, which is where an unevidenced withholding claim is
  read by a human rather than by an apply relay.
- **The tier argument moved to the contract's crosswalk and is no longer stated here.** Why a
  productive survivor is IMPORTANT rather than CRITICAL is a rule-to-tier argument every consumer of
  the rule needs, and it was stated in two places. This spoke keeps the one part a mutation run owns:
  which Phase 4 class maps to which rule.
- **The off-site remediation is a declared property, not a routed limitation.** The consumer now has
  a disposition for a row whose fix belongs in another file (`review` 0.21.0), so this producer names
  the covering test in `Action` and the consumer surfaces the row to a human. A surfaced mutation row
  is the intended end of the route.

## [0.2.0]

### Added

- **`/mutation-testing:audit --persist-findings`** — an opt-in Phase 6 that writes the run's
  survivors as a findings file the `review:fanout` `fix` action consumes, making this skill the first
  adopter of the detector-findings producer contract
  (<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>).
  The destination, the self-ignore guard, and the producer-computed fields are resolved through that
  contract rather than restated. Bare invocation is unchanged: it reports and stops.
- **Each write this phase makes is proven outside tracked space before that write is made** — the
  findings file, and the self-ignore guard's own `.gitignore` where a governing checkout was found
  (where none was, neither write happens — see below). Per-write rather
  than both up front,
  because on a fresh root the guard's file is what makes the findings file's probe pass. The guard's
  write is proven *before the guard heals*, by requiring the resolved root to hold no tracked files, because writing `*` into a
  root that does would rewrite the ignore semantics of the consumer's own files; proving only the
  findings file would leave that write ahead of the proof. The governing checkout is resolved from
  **two signals that must agree** before the permissive branch is taken: a walk of the resolved
  root's ancestors for a `.git` entry, over a path made physical with `pwd -P` first so a symlinked
  ancestor cannot hide a checkout, and `git rev-parse --show-toplevel` run under the ambient
  environment. Neither is trusted alone — `rev-parse` fails with exit 128 alike for no-repository, a
  missing directory, a dangling `gitdir:`, and a discovery limit under which a repository does govern
  the path, while the walk cannot see a working tree designated by `GIT_WORK_TREE`/`GIT_DIR`. One
  topology defeats both — a repository whose `core.worktree` names the destination's tree — and the
  permissive branch is shaped around it: **where no checkout is found, the self-ignore guard does not
  run at all.** There is no repository to keep the write out of, and its create-when-absent rule
  would otherwise write straight over a `.gitignore` that is absent from disk but tracked in the
  undiscovered checkout, modifying committed content it could not even hide, since a tracked file is
  exempt from its own pattern. **The findings file is withheld on that branch too**, with one
  exception: the same undecidability applies to it, since its destination may be an index-tracked
  deletion in the undetected checkout, where writing produces a modified tracked file rather than a
  new untracked one (measured). The run reports the resolved destination and that nothing was
  persisted, rather than writing where it cannot rule that out. The exception is the contract's
  `${CLAUDE_PLUGIN_DATA}` fallback for a rootless directory — outside every checkout by
  construction, so no tracked deletion can hide there and refusing it would strand the one
  destination a headless run on such a directory is meant to use. With a governing checkout, `git check-ignore` decides, anchored there and never to the invoking
  worktree, where a memory root outside the worktree (a layout the `review:fanout` `fix` action
  supports explicitly) makes the probe fatal with exit 128 and every write a refusal. "The path is
  tracked space" and "the probe could not evaluate the path" are reported as the different states
  they are; both refuse. The obvious alternative is worthless: a `.gitignore` whose content is `*`
  matches itself, so a memory root resolving inside tracked space leaves `git status --porcelain`
  byte-identical whether the write was ignored or not.
- **`Action` names the covering test file**, since Phase 1 already cached that selection and
  withholding it is information loss.
- **Severity is computed from the Phase 4 verdict class, never from the finding's prose.** Productive
  and unclassified survivors emit `IMPORTANT` rows; arid and equivalent survivors emit no row at all —
  arid because its only remediation is a suppression entry the user must accept, which an apply relay
  must never be handed, and equivalent because it is not a defect. `Confidence` is `high` on every
  emitted row (Phase 3 executed the mutant) and is never `low`, which ranks below omitting the field.
- **A run that examined mutants and found nothing still writes the file**, with an empty `## Findings`
  table and a `## Surfaces` line. The consumer unions `## Surfaces` across producers, so "this surface
  ran and returned nothing" is coverage information a silent run destroys. A run that examined *no*
  mutants writes nothing — there is no coverage to report, and claiming one would fabricate it.

### Changed

- **The read-only invariant is narrowed from the working tree to tracked source.** A mutant is still
  applied, measured, and reverted, and a run still either ends with tracked source byte-identical or
  ends in failure naming what it could not restore — but
  the property no longer covers the whole tree, because `--persist-findings` writes into a memory
  tier proven to sit outside tracked space. That is a real widening of what the skill may do, disclosed here rather than folded
  into a wording note; what did *not* change is the skill's standing under the naming doctrine, whose
  verb table already permits mutation behind an explicit user override.
  `scripts/skill-leaf-name-registry.txt` records the amended grounds on which this plugin holds the
  `audit` leaf.
- **A failed restoration now ends the run instead of headlining a report.** Phase 3 verifies
  restoration against the Phase 0 snapshot at the earliest point the configured write regime permits
  — after every revert where mutants are applied to tracked source one at a time (`tool: manual`, and
  the trap's exit paths with it), and once at the end where the tool writes out of tree or rewrites
  the working file whole. Under mutant schemata there is no per-mutant revert to observe, so the
  in-loop rule is stated where it is real rather than promised everywhere. Phase 0 resolves which
  regime is in effect from the project's config rather than from the tool's reputation, and refuses
  outright where the regime is per-mutant in-tree but the tool offers no observability to gate on.
  The first tracked path it cannot confirm restored is terminal: no further mutants, no triage, no ranked report, and no findings file even
  under `--persist-findings`. Previously the failure was reported as the run's headline finding while
  the run continued, which let a normal-looking outcome — and, with the flag, a conforming findings
  file whose `Location`s assert a restored tree — be produced over source left mutated. That is the
  false-green class `docs/conventions/liveness-assertion/README.md` "Core contract" item 1 forbids,
  and it is what makes the read-only invariant enforced rather than asserted.

### Known limitations

- **A mutation finding's remediation site is not its `Location`.** The missing assertion belongs in
  the covering test, while `Location` names the mutated node, so a consumer that fences each
  remediation to `Location` cannot reach the target. This plugin neither retargets `Location` (which
  would destroy the row's cross-producer dedup key) nor invents a column the findings-file shape does
  not define; the disposition is routed to `melodic-software/claude-code-plugins#2681`. Until it
  lands, a mutation-survivor row is one a human dispositions.

## [0.1.0]

### Added

- **Initial release.** Three skills covering the mutation-testing concern: knowledge, provisioning,
  and a read-only diff-scoped run.
- **`/mutation-testing:principles`** — knowledge router over five source-attributed reference
  spokes: mutant states and operator catalogs, the metric family (mutation score, covered-code
  score, PIT's test strength, Infection's MSI, the oracle gap), the scaling protocol
  (diff-scoping, one mutant per line, arid-node suppression, review-time surfacing), tooling by
  ecosystem plus the manual protocol for languages with none, and the theory (competent programmer
  hypothesis, coupling effect, the equivalent-mutant problem). A quick decision guide answers the
  common questions with no reference load.
- **`/mutation-testing:setup`** — `check` inspects ecosystem detection, tool presence and
  runnability, test-runner support, baseline suite health, known flakiness, the effective config
  across cascade layers, diff-target resolution, suppression-record hygiene, and tracked-not-ignored
  status; `apply` interviews and writes `.claude/mutation-testing.md` plus an empty
  `.claude/mutation-testing-arid.md`. Proposes the tool's install command, never installs unprompted.
- **`/mutation-testing:audit`** — diff-scoped run generating at most one mutant per changed line,
  executing against a test selection cached once per target, with revert guaranteed on every exit
  path. Reports per file ranked by oracle gap.
- **Arid-node suppression adopts the finding-suppression convention in full** —
  `.claude/mutation-testing-arid.md`, kept as a surface separate from the config so a config diff
  reads as a policy change and a suppression diff reads as an accepted finding.
  `audit/context/suppression.md` owns this plugin's read of the contract: the five required keys
  mapped to a mutation finding (`check` as the qualified operator, `claim` as `arid(kind=…)` from a
  closed vocabulary, `sites`, `reason`, `date`), the `finding_id` and anchor derivations — binding
  the convention's `heading_path` to the mutated node's enclosing scope path, since source code has
  no headings — the policy-floor precedence inversion, and the four dispositions. Entries are
  proposed complete and never written unprompted; an equivalent mutant is never suppressed, because
  the convention's record is not for a finding that is simply wrong.
  Two reconciliations the contract needs against a *diff-scoped* consumer, both stated rather than
  left implied:
  - **The disposition obligation applies only to what this run examined.** An entry outside that is
    *not-examined* — left untouched and counted, never resolved. Running it through CLOSED would land
    it on UNEXPLAINED DISAPPEARANCE and fail the skill's own self-check on nearly every run, and a
    self-check that fails routinely is one nobody reads. Scope is tested at the **node**, not the
    file: mutant generation is line-scoped, so a file carrying a suppressed survivor at one line and
    an unrelated edit at another is "touched" while that node is never examined. The scope test's
    granularity has to match generation's.
  - **The arid `kind` vocabulary is enumerated in full** in
    `principles/reference/scaling-and-suppression.md` rather than illustrated, so `setup check`
    validates membership in a table instead of shape. An unenumerated vocabulary would make every
    suppression self-justifying, which is the failure a written `reason` exists to prevent.

### Notes on deliberate omissions

- **No score-threshold field and no build gate.** A mutation score has a permanent, unknowable
  ceiling below 100% because equivalent mutants cannot all be removed, and every point of score is
  purchasable by suppressing a mutant — so a gate selects for suppression over testing. The
  reasoning, with sources, ships in `principles/reference/scaling-and-suppression.md`.
- **Survivor triage is delegated, mandatorily.** Classifying a survivor as productive, arid, or
  equivalent is the `self-grade` bias class, so it runs in a fresh-context (non-fork) subagent; the
  equivalence call prefers a cross-vendor advisor when one is installed, with the same-vendor
  fresh-context subagent as the stated fallback. Executing a mutant is exempt as a deterministic
  gate — the tests' pass/fail is the verdict.
- **An equivalence verdict must cite a demonstration.** Asserted from inspection alone it is
  reported as *unclassified*, not as equivalent.
- **The oracle gap is defined once**, in `principles/reference/metrics.md`, as
  `mutation score − code coverage`. A large negative gap is the bad direction, so the audit ranks
  **ascending**. The audit does not restate the formula — an inverted second definition would silently
  reverse the ranking of the report's most important column.
- **Restoration is verified against the preflight snapshot, not against a clean tree.** Phase 0
  permits unrelated dirty files, so an unconditional clean-tree probe would report a false restore
  failure on any repo with work in progress — and teach the reader to ignore the one line that must
  never be ignored.
- **No review-time surfacing yet.** Surfacing mutants as review comments is the shape with the
  strongest industrial evidence, but that evidence is conditional on a suppression loop already
  existing — an un-suppressed run is roughly 85% noise at Google's reported starting ratio. Deferred
  until the suppression record carries real entries.
