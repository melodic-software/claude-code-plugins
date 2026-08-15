# Changelog

All notable changes to the `mutation-testing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Added

- **`/mutation-testing:audit --persist-findings`** — an opt-in Phase 6 that writes the run's
  survivors as a findings file the `review:fanout` `fix` action consumes, making this skill the first
  adopter of the detector-findings producer contract
  (<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/detector-findings/README.md>).
  The destination, the self-ignore guard, and the producer-computed fields are resolved through that
  contract rather than restated. Bare invocation is unchanged: it reports and stops.
- **The destination is proven outside tracked space before anything is written**, and a destination
  that cannot be proven is not written to at all. The probe is `git check-ignore` anchored to the
  repository that governs the destination — never to the invoking worktree, where a memory root
  resolving outside the worktree (a layout the `review:fanout` `fix` action supports explicitly)
  makes the probe fatal with exit 128 and every write a refusal. A destination no repository governs
  is untrackable and needs no ignore rule. The obvious alternative is worthless: a `.gitignore` whose
  content is `*` matches itself, so a memory root resolving inside tracked space leaves
  `git status --porcelain` byte-identical whether the write was ignored or not.
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
  applied, measured, and reverted, and tracked source is still byte-identical when the run ends — but
  the property no longer covers the whole tree, because `--persist-findings` writes into the ignored
  memory tier. That is a real widening of what the skill may do, disclosed here rather than folded
  into a wording note; what did *not* change is the skill's standing under the naming doctrine, whose
  verb table already permits mutation behind an explicit user override.
  `scripts/skill-leaf-name-registry.txt` records the amended grounds on which this plugin holds the
  `audit` leaf.
- **A failed restoration now ends the run instead of headlining a report.** Phase 3 verifies every
  revert against the Phase 0 snapshot *inside* the mutant loop, and the first path it cannot confirm
  restored is terminal: no further mutants, no triage, no ranked report, and no findings file even
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
