# Changelog

All notable changes to the `review` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.26.6]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).
- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.26.5]

### Changed

- **Fixture-building tests clear inherited git environment (#2872).** Suites
  that build a git fixture now unset `GIT_DIR`, `GIT_WORK_TREE`, and
  `GIT_CONFIG` so an inherited environment cannot write the fixture identity
  into the caller's repository. Test-only; no plugin behavior change.

## [0.26.4]

### Fixed

- **`quality-gate close-out` Shape B dropped code-shipping sub-items from the basis.** Rung 1's
  empty-result rule read *"a successful query returning zero merged PRs means that sub-item closed
  without shipping code … Only a failed query falls to rung 2."* But an empty rung-1 result means
  only that **no PR named the item with a closing keyword**, and two very different situations
  produce that: the item genuinely shipped nothing, or it shipped under a `Refs #N` reference — a
  posture `work-items`' own `work/SKILL.md` explicitly sanctions (*"an intentional `Refs #N` opt-out
  does not exclude its issue"*), and the normal shape whenever one PR advances several items while
  closing only the spin-offs it fully resolves. Everything in the second case was classified
  `no-code` and silently excluded, while the report still claimed to cover the shipped whole. An
  empty rung 1 now falls to rung 2 as well, `no-code` is only reached when both rungs come back
  empty, and the verdict names which rung produced it.

  Found by the mode reviewing the container that shipped it — #3027's dogfood criterion working as
  intended. On container #2933's own close-out, PR #3056 carried `Closes` for three spin-offs only
  and PRs #3067 and #3071 carried no closing keyword at all, so three sub-items that between them
  shipped **83 file-touches** of adapter and generator code would have been dropped from the basis
  of the review deciding whether that container could close.

  **Rung 2's own reduction is reconciled with it.** The first version of this fix left rung 2
  still saying that no surviving hit means `unresolved` — which escalates to rung 3 and can stop a
  close-out — while the new rung-1 wording said the same outcome is `no-code`. Two sections
  prescribing opposite results for the exact case the fallback exists to preserve. Rung 2 now
  classifies by **why rung 1 was empty**: rung 1 *succeeded* and empty plus rung 2 empty is
  `no-code` and does not escalate; rung 1 *failed* plus rung 2 empty is `unresolved` and does,
  because in that case nothing has actually looked successfully. The verdict says which.

## [0.26.3]

### Fixed

- **`quality-gate` restatement lane: a project's evidence-artifact contract
  now wins over the bundled frontmatter template (closes #2863).** The
  Artifact section prescribed `type: restatement-review` plus `mode`/`branch`
  with no exception, so sessions that followed the skill verbatim emitted
  that shape even when the consumer already owned the artifact — a quality-gate
  evidence contract that requires `type: quality-gate-evidence` (literal)
  plus `date`/`slug`/`reviewed_at_sha`/`diff_base` was overridden, and a
  scan of one adopter found fourteen hybrid or template-shaped artifacts
  that its pre-push gate then accepted because it only parses
  `reviewed_at_sha`. The bundled YAML is now the fallback only: when the
  project ships its own evidence-contract criteria, those fields and the
  contract's body shape are authoritative, and the two shapes are not
  merged. A clean pass still writes an artifact, but its body follows
  the same split: the contract's clean-result shape when one exists,
  and the bundled scope plus no-findings assertion only as the
  no-contract fallback. Default consumers with no contract are unchanged.

## [0.26.2]

### Fixed

- **`downstream` mode cited into another plugin's private files.** Its "say plainly what is
  unverified" step path-cited the `playbooks` plugin's `fable-5` skill inside that skill's own
  `context/` directory, which the encapsulation contract makes private. (The path is described
  rather than spelled here on purpose: repeating it would leave the cite standing in this plugin
  after the fix removed it from the skill body.) It now cites
  `/playbooks:fable-5 verification` — slash invocation is the only supported handle, and the
  **chapter argument is load-bearing**: that skill's own argument contract makes a bare invocation
  arm its entire operating doctrine as standing session instructions for the rest of the run, where
  a chapter name reads only that chapter. A cite that reaches for one formula must not re-posture
  the session that follows it. The presence gate and the stands-on-its-own fallback are unchanged.

## [0.26.1]

### Changed

- **`quality-gate`: the PR-review-toolkit composition names the Skill tool (#3002).** In
  `context/code.md`, the presence-gated `/pr-review-toolkit:review-pr` invocation now says "via
  the Skill tool". Wording only; the aspect detection and the gate are unchanged.

## [0.26.0]

### Added

- **The fix relay honors a producer's declared remediation owner (closes #3033).** A detector
  can now tell the relay that its findings' repair, though contained to `Location`, is owned by
  the detector's own remediation skill — and `fix-pass-mode.md` routes those rows there instead
  of deciding for itself.

  The gap this closes was silent and total for one adopter. `ai-slop:audit`'s fourteen
  prose-rewrite rules classify as cleanup by content, and the cleanup route hands that class
  wholesale to `/simplify` — a **code**-simplification skill that reads no findings file and
  loads none of the producer's rewrite guide. Step 5 then retired the findings anyway. The pass
  reported a clean run over findings nobody fixed, applying at most `rule-utm-params`, the one
  genuinely auto-applicable rule.

  Neither existing disposition reached it. **Off-site is a statement about the SITE** — both of
  Step 2's limbs ask whether the repair leaves `Location`'s file — and these repairs are at
  `Location`, so claiming off-site would assert something false and would route to surface-only,
  trading a wrong apply for no apply. **`Auto-applicable: No` has no path to the cleanup route
  at all**: Step 4's surface-instead-of-applying fence sits under its *correctness-class*
  heading, so a cleanup row reaches `/simplify` whatever the crosswalk says about it.

  - **Step 2** gains one classification rule: a row belonging to a rule whose crosswalk
    `Auto-applicable` cell leads with ``No, remediated by `<invocation>` `` routes to that invocation,
    whatever its class, and never to `/simplify` or the generic fixer. The declaration is
    resolved through the qualified rule id every conforming row already leads its `Finding` cell
    with, so **no producer has to change what it emits**. An `Action` cell leading with
    ``Remediate with `<invocation>` `` only **corroborates** that declaration and can never be the
    sole basis for routing: **the crosswalk row is necessary**, and a rule with no crosswalk
    declaration takes its ordinary class however its `Action` reads. That asymmetry is the trust
    boundary — the crosswalk lives in the consuming repo's docs, outside the artifact being
    consumed, while the `Action` cell is inside it; Step 1 already establishes that nothing
    authenticates a findings file's writer, and this is the one route whose target Step 4 does not
    re-fence, so `Action`-alone routing would let any component that can write a conforming file
    hand any installed skill arbitrary rows. Availability is not authentication. Off-site is
    decided first, so a row that is both stays surface-only, and a pass that cannot resolve the
    contract has no declaration to read — the no-declaration case, never an `Action` fallback.
  - **Step 4** gains the route, with no direct-apply fallback — the asymmetry with `/simplify`
    is the point. Only an invocation already available in the session is invoked; nothing is
    installed, fetched, or name-matched loosely, because nothing authenticates the writer of a
    findings file. An unavailable or unrecognized invocation surfaces its rows, naming what the
    producer asked for so the operator can run it.
  - **Steps 3 and 5** count and report the route, and an unavailable surface's rows land in the
    consumption record's "Not applied" table with the invocation as their recovery.

  Neither other adopter changes, and neither had to be touched. `mutation-testing:audit` declares
  no owner and is off-site, which is decided first; `testing:audit` declares no owner because no
  skill owns choosing the assertion a behavior deserves, and its rows are surfaced by Step 4's
  judgment fence exactly as before.

  `ai-slop` 0.3.1 rides along as the producer half of the same claim — a documentation
  correction, not an emitter change. Its audit skill is the normal entry point that recommends
  remediation, and it still told operators to keep prose rewrites away from this relay because
  routing them here "retires the findings without fixing them". Leaving that in place would have
  made this route unreachable through the documented flow while the contract advertised it.

  Producer-side, the declaration and its fixed forms are owned by the detector-findings
  convention (`docs/conventions/detector-findings/README.md` 2.4.0), "When the remediation is
  owned by the producer's own skill". No producer had to change what it emits.

  One detail is called out in Step 2 rather than left to inference, because this step is the
  *literal* read and the failure is silent: **the invocation arrives inside a code span and the
  fixer strips the backticks before matching**. A fixer matching the bare form against a
  backticked cell matches nothing and falls through to the ordinary class — the original defect
  wearing the new disposition's clothes. The contract states the convention once and binds both
  the crosswalk cell and the corroborating `Action` lead to it.

## [0.25.1]

### Fixed

- **`quality-gate close-out` Shape B was structurally blind to in-flight work.** Every rung
  of the commit-set ladder reads the default branch — rung 1 keeps `MERGED` linkage nodes,
  rung 2 scans `git log <default-branch>` — so work that is written, pushed, and sitting in
  an **open** PR never entered the basis and was never mentioned. Merged-only is the right
  reduction for the *basis* (an unmerged diff has not shipped) and the wrong thing to leave
  unsaid for the *verdict*: a container closed on it closes on evidence that is not on the
  default branch, which archival-by-closure cannot survive. Shape A reaches its open branch
  through the `**Integration branch:**` line; Shape B had no analogue. The mode now runs one
  extra `state=="OPEN"` query plus an open-PR search against the container before rendering,
  reports whatever it finds as **in-flight, not in the basis**, and treats any open PR
  carrying container work as a precondition of the close rather than a footnote. Surfaced by
  running the mode over container #2933, where six behaviour-changing fixes sat in an open PR
  and the derived basis showed none of them.

## [0.25.0]

### Added

- **`downstream` mode — what a change breaks outside its own diff.** The review lane was entirely
  diff-scoped: `architecture-guardian` maps which layer each *changed* file belongs to and never
  enumerates consumers of a changed contract, `code-reviewer` and `doc-drift-detector` carry no
  caller or ripple item at all, `fanout` fans across surfaces all diffing the same merge-base,
  `verification:confirm` matches requirements to implementation (inward), and
  `mutation-testing:audit` is `git diff`-scoped by construction. `planning:devils-advocate` has a
  literal blast-radius round but reviews plans, not code, before implementation. This mode is the
  outward-looking lens none of them provide.

  Like `self`, the mode **dispatches rather than judging inline**, and for a sharper reason: the
  thread that wrote the change is the worst judge of what the change reaches, because its model of
  "what this touches" is the one it already held while writing — an inline pass re-derives the
  author's own blast-radius assumption and then confirms it. The mode ships a dispatch policy, an
  orchestrator sequence, and a worker brief, with the same presence-gated cross-vendor preference and
  named same-vendor fallback every other delegating surface in this fleet uses. It takes a general
  read-only subagent rather than a dedicated agent, and says why: its checks are not a fixed
  per-ecosystem baseline like `architecture`'s or `security`'s but a search shaped by what the diff
  changed, so the brief carries the specifics. Every finding is verified against the tree before it
  is presented — this is the one mode whose findings name files the diff never touched, so an
  unverified one sends a reviewer to the wrong place.

  Reauthored from the `blast-radius` skill in `cursor/plugins` (MIT); provenance and the
  substantial rejections are recorded in `docs/upstream/cursor-pstack.md`.

  It **adds no grading scale**. Findings carry the existing severity and confidence axes unchanged,
  and an unverifiable claim is marked in words rather than on a new ladder — the fleet already ships
  eight evidence ladders, and a ninth would be the silent second way `discipline:reuse-or-replace`
  exists to catch. `context/severity.md` is deliberately untouched: its own Vocabulary section
  closes "axis" at severity and confidence, and `context/spec.md` already answered this same
  question the same way.

  The load-bearing rule is that **an unverified safety fact cannot clear a concern** — it stays in
  the confirmed-risk list carrying the reason it is unverified. An unchecked assumption sorted into
  the reassuring column is worse than one nobody looked at, because it now reads as checked.

  Because this skill does not run builds or tests, the deliverable "the cheapest test that would
  catch this" is a presence-gated handoff to `/testing:write` and `/mutation-testing:audit` rather
  than an assertion — stronger than the upstream it came from, since the mutant is re-run and the
  agent that wrote the test does not grade itself into a pass.

  The description carries the "blast radius" trigger phrases deliberately: trigger phrases are
  behavior, and leaving the noun unclaimed routes it to `/planning:plan`, which advertises
  "blast-radius assessment" and operates a stage earlier. Negative routing is stated against that
  skill, against `/planning:devils-advocate`, and against
  `/docs-hygiene:rename-references audit blast`.

## [0.24.0]

### Added

- **`code-reviewer` gains a tautological-expectation criterion (closes #3046).** The
  anti-pattern was covered in prose — `tdd`'s `anti-patterns-khorikov.md` and `testing`'s
  `write.md` checklist — and was *claimed* to be covered executably by `testing:audit`'s
  `cant-fail-scan.sh`. That claim was false, and the scanner says so in its own header:
  `testing/audit/rule-recomputed-expectation` "detects the decidable core — textually identical
  sides — not every recomputation shape." A validator ran it over three canonical tautological
  tests for **zero** findings, because the canonical Khorikov shape — compute `expected` with the
  production algorithm in the arrange section, then assert against it — has non-identical sides.
  Nothing judged the semantic shape.

  The new Code-quality bullet asks the one question that decides it: **what is the expected
  value's independent source?** A known-good literal, a hand-computed value, a worked example from
  the spec, or a fixture — as against a re-derivation through the steps the code under test takes.
  The round-trip/identity case (output compared against its own input) rides in the same criterion,
  matching how `write.md:78` already pairs them.

  **It cedes ground to the scanner by name rather than overlapping it**, per the plugin's existing
  skip-what-tooling-enforces posture: where both sides are the same expression,
  `cant-fail-scan.sh` fires and owns the finding; this criterion covers only what that rule leaves
  undecided — sides that differ textually but share a derivation. Widening the detector past
  textually-identical sides is explicitly *not* part of this: the general shape is undecidable.

  Placement went to the agent definition rather than `quality-gate/context/criteria.md`, because
  that file is a routing doc — it resolves the project's standards index and carries no criteria of
  its own, and its own "Baseline when the ladder yields nothing" step already points at the agent
  definitions for the universal checklist.

## [0.23.0]

### Added

- **`quality-gate` gains a tenth lens: `close-out` (#3027).** `spec` mode (0.22.0) judges one
  branch against its originating item; a spec container is not a branch. Its work lands as many
  merges over days or weeks, and `work-items:decompose` and `work-items:ship` both routed container
  close-out at "the review plugin's spec-fidelity machinery" without a container-scoped basis
  existing anywhere. `context/close-out.md` is that basis. It is **`spec` mode at container scale,
  not a second spec lens** — the finding-class enum, the spec-line quoting rule, the
  item-content-trust fence, the dispatch policy, and the both-directions judging all stay owned by
  `context/spec.md` and are reused by citation. What close-out owns is *what* gets judged: which
  container, which spec body, and which change set counts as "what the container shipped."
- **A mode-scoped diff-basis override, because squash-merge destroys the ancestry.** This is the
  first mode that does not use SKILL.md's single Review diff base at all — it derives its own, per
  execution shape:
  - `integration branch → single PR` — one branch, one PR, so the basis is an ordinary range: the
    PR's `merge-base(base, head)`..head while open, its squash commit once merged.
  - `per-item PRs` (the default) — the basis is a **commit SET, not a range**, and the reviewer
    reads the union of the per-commit diffs. A two-dot `<first>..<last>` over the default branch
    would sweep in every foreign commit merged between the container's first and last item, and the
    review would then report findings against work the container never shipped. The cost of the set
    — cross-item interactions must be read *across* diffs rather than in one composite hunk — is
    stated in the report rather than hidden.
- **A closing-commit ladder that degrades honestly.** Provider close-linkage
  (`Issue.closedByPullRequestsReferences`, reduced the **inverse** way from the `work-items` github
  adapter's in-flight check — that one keeps `OPEN` and drops `MERGED`; close-out wants exactly the
  `MERGED` nodes and their `mergeCommit.oid`) → a heuristic scan of the default branch's squash
  subjects, flagged as heuristic → ask → **skip with a note**. A failed query is never read as an
  empty set, and a sub-item with several hits is disambiguated rather than guessed. The GitHub MCP
  tools are named as the equivalent mechanic for sessions without `gh`.
- **`no-code` and `unresolved` are kept apart** — found by dogfooding the mode against container
  #2933, where an investigation item (#2945) closed on a recorded decision comment with zero PRs. A
  *successful* close-linkage query returning no merged PRs is an **answer**: that item shipped no
  code by design, its criteria are judged against its closing comment, and it stays out of the
  basis. Only a *failed* query falls to the scan, and only the scan produces `unresolved`. The same
  run showed why the scan needs reductions at all: the board-publishing commit matched **every**
  sub-item it listed, so a candidate referencing many of the container's sub-items is dropped as
  journey narration, and closing-keyword forms outrank bare mentions.
- **Two gates and a dry run.** Close-out is pre-flight gated on its own basis rather than the branch
  base, plus a rollup check that the container is actually finished — running the cumulative pass at
  12/20 manufactures `missing` findings for work that is merely not done yet. `--dry-run` exercises
  container / spec / shape / basis resolution and stops before dispatching, which is how the basis
  is verified against a container still in flight.
- **The verdict is posted to the container, not just to the findings directory.** The findings
  location lives in the contract slice, which is pruned before merge — so the artifact that survives
  close-out is the comment on the tracker item. The mode produces the verdict; the close itself
  stays owned by `work-items:decompose`'s ship ritual, and a `missing` or `wrong` finding against a
  stated acceptance criterion keeps the container open.
- **Provider degradation stated outright.** The basis derivation is GitHub-only in practice, and the
  file says so: `jira` declares `list-sub-items: false` (exit 6) and has no merge-commit concept, so
  it degrades to asking the operator; `local-markdown` is barred from containers entirely and gets
  no close-out path at all. A provider that cannot answer emits a skip note, never a silent partial
  pass.

## [0.22.0]

### Added

- **`quality-gate` gains a ninth lens: `spec` (#2937).** The skill had eight modes and no
  spec-fidelity one — "what was the goal" was a gather input, never the thing under judgment — while
  `work-items:decompose` and `work-items:ship` both already routed container close-out to "the review
  plugin's spec-fidelity machinery," which did not exist. `context/spec.md` is that machinery. It
  **owns** the finding-class enum (`missing` / `scope-creep` / `wrong`), requires every finding to
  quote the spec line it is judged against, and judges the diff in both directions so `scope-creep`
  is reachable at all. `scope-creep` needs a positive statement of bounded scope before unlisted
  behavior becomes a defect — a spec that never mentions a surface leaves the implementer's judgment
  intact.
- **A spec-source discovery ladder, because the lens cannot run without a spec.** `--spec <path|id>`
  → item refs harvested from the branch's commits and PR body → the topic's contract slice → ask →
  **skip with a note**. The last rung is the point: a fidelity verdict rendered without a spec is a
  fabrication, so a headless run with nothing resolved stops and says which rungs it tried rather
  than inferring a spec from the diff it is meant to judge. What the ladder gets right that a naive
  version does not:
  - A harvested ref is **validated before it is used to build anything** — commit messages and PR
    bodies are attacker-influenceable through a fork PR, so the number must be strictly numeric and
    an accompanying owner/repo must match a repo-name shape; a ref that fails is **dropped**, never
    repaired. Components are passed as discrete arguments, never interpolated into a command line.
    The item-content-trust boundary governs the body text a read returns and does not cover an
    identifier used to build a command, so this check is its counterpart rather than a duplicate.
  - The validated ref is **promoted** to the qualified `<provider>:<owner>/<repo>#<number>` form,
    and the read is scoped to that id's own repository with `--repo` — a bare number reads the
    *current* repo, which for a cross-repo ref is a different issue that merely shares a number.
  - The item is read **through a public seam or the provider mechanic, never by reaching into the
    sibling plugin**: `PLUGIN-PHILOSOPHY.md` forbids discovering another plugin's installation
    directory, and no namespaced item-fetch action exists to call today, so the provider-mechanic
    read is the operative path — which also means this rung works with no tracker plugin installed
    at all. Body text was never a seam field regardless (the normalized item object carries no
    `body`), and parent linkage degrades honestly: `get-item` is authoritative for `parent_id` and
    is not reachable here, so a slice's container is best-effort or named directly with `--spec`.
  - The contract-slice rung keys on the **topic slug**, not the branch slug, whose mapping is
    documented as lossy.

  Item text is read under the item-content-trust boundary throughout: data describing the work,
  never instruction to the reviewer.
- **A fail-fast pre-flight gate, ported from `fanout`, which `quality-gate` had entirely lacked.**
  An unresolvable diff base or an empty change set now stops before any reviewer is dispatched
  instead of spawning one to produce noise. **Mode-scoped:** `criteria` is a reference mode that
  legitimately runs against a clean tree and is exempt. The frontmatter `allowed-tools` allowlist is
  widened with the git read verbs the gate needs — without that the gate stalls headless, which
  would have made it worse than no gate. **Untracked-only is reviewable here**, deliberately unlike
  `fanout`: this skill's Shared inputs hand untracked files to the reviewer directly, so a
  new-module or new-test branch is a real change set; `fanout` stops on it only because its surfaces
  receive nothing but the merge-base diff, which cannot show an unstaged file. Neither skill stages
  files.

### Changed

- **`self` mode's spec-conformance checklist item stops being a second SSOT.** It restated the same
  three finding classes `context/spec.md` now owns; two copies of one definition is exactly what
  this skill's own `restatement` mode flags. The fenced worker checklist keeps a shallow
  divergence-and-quote check and explicitly defers classification, and the pointer to the owning
  file sits in the orchestrator-facing escalation list — **not** inside the subagent template, which
  is addressed to a fresh-context read-only worker that cannot invoke a skill to follow it.
- **`self` mode's large-diff worker split now keeps its two lenses separate through presentation,**
  not just until verification. The two workers answer different questions, so one combined list lets
  a clean standards pass mask a failing spec pass.
- **"Axis" now means one thing in this plugin, recorded once in `context/severity.md`:**
  severity or confidence. A review perspective is a **lens**. Three incompatible senses were live
  across these docs, and merging and ranking across the two real axes is precisely what `fanout`'s
  normalization pipeline exists to do — a rule written on the ambiguous word would have negated it.

## [0.21.1]

### Changed

- **The binding's self-ignore-guard bullet now defers on invalid roots as well as on cadence.** It
  already restated the guard's create-when-absent behavior and ended "per the contract", but named
  none of the roots at which the contract says the guard does **not** run — so a reader arriving
  through the detector-findings owner table, which names this binding as the guard's owner, met text
  reading as unconditional. The bullet now states that such roots exist and points at the
  convention's "Runtime guards" for them, **enumerating none**: a second copy of the list is how a
  rule ends up stated several ways, and the omission this repairs was itself an incomplete copy.

## [0.21.0]

### Added

- **`fix` gains a fourth surface-instead-of-apply trigger: the remediation lies outside the finding's
  `Location` (#2681).** Step 4 fences each fix to its finding's `Location`, and the findings shape has
  no remediation-target column, so a row whose fix belongs in another file — a surviving mutant fixed
  in its covering test, a contract violation detected at a caller and fixed at the callee — left a
  fixer choosing between breaching its own fence and inventing a reason to surface. The existing three
  triggers do not cover it: such a row can be high-confidence, mechanically contained, and low blast
  radius. The new trigger is the disposition the contract was missing, and it is deliberately not a
  column — what a column would enable is an unattended two-file apply, which is exactly what the fence
  forbids.

### Changed

- **The consumption record is keyed to a CONSENTED gate and a pass that ran to completion, not to
  having applied something (#2681).** The old trigger conflated two states: a gate the operator
  **declined**, and a pass that **ran to completion and surfaced every row**. Only the first is what
  the no-record rule was for. Left keyed to application, the off-site routing above would have made a
  detector whose remediation is off-site *by construction* — a mutation-survivor producer, every one
  of whose rows surfaces — emit a file that is never recorded, never subtracted, and therefore
  re-merged and re-surfaced on every subsequent `fix` run, forever. That is the unbounded-noise
  failure Step 1 exists to prevent, arriving through the ledger instead of the scan. A declined
  interactive gate and the non-interactive STOP still write nothing: both emit a plan and process
  nothing, and a record there would retire files the action never opened — a worse silent drop than
  the one being closed. Operators will now see records from passes that changed no files.
- **`Consumption is per FILE, not per row` is EXTENDED to the zero-applied case, not merely applied
  to it.** Its wording covered a *partly* surfaced or operator-narrowed file, both of which
  presuppose a non-empty applied set, so the zero case was silent rather than decided. Two zero
  shapes are now argued separately: a file whose rows were all surfaced is retired because every one
  is rendered individually in the "Not applied" table with its producer, and a **coverage-only** file
  (no data rows at all — the ordinary output of a detector that examined its surface and found
  nothing) is retired because it carries coverage rather than findings and has nothing to recover.
- **`An apply that terminates abnormally writes no record` becomes `a pass`, and now names two
  cases.** A purely-surfaced pass that dies partway through rendering the "Not applied" table retires
  rows it never rendered, and that table is the only route back to a surfaced row — so a partial
  apply is no longer "the one case". The record body's title and its applied lists take `(none)`,
  matching the convention the "Not applied" table already set.
- **Step 2 routes an off-site row to surface-only, and Step 3's counts follow.** Deciding it at
  classification rather than at apply time is what keeps the plan honest: the correctness count is
  what Step 4 will attempt, so a row Step 4 would decline is never counted as one it will fix. The
  `Surface-only` plan line now names off-site remediation alongside human judgment and unparsed
  entries, which is where such a row lands and is listed by name in the consumption record.

## [0.20.1]

### Changed

- **`fanout`'s writer contract points at the detector-findings convention instead of stating the
  producer rules itself (#2679).** 0.20.0 put the multi-producer rule in
  `context/default-mode.md`, but that rule binds every component that writes a conforming findings
  file — not just this plugin — and `docs/PLUGIN-PHILOSOPHY.md` "Convention registry" is one owner
  doc per shared concern. The general rules (producer-owned fields, coexistence obligations,
  minimal conformance) now live in `docs/conventions/detector-findings/`, cited by raw URL because a
  plugin installs standalone and cannot resolve a repo-relative path. `default-mode.md` keeps only
  fanout's own writer contract. The findings-file shape, the fix action, and every gate are
  unchanged; what moved is instruction text an agent reads, so a producer authored against 0.20.0's
  prose still conforms.

## [0.20.0]

### Changed

- **`fanout`'s `fix` action consumes a merged SET of findings files, not the newest one
  ([ADR 0010](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0010-merge-findings-across-producers-and-mark-consumption-explicitly.md),
  #2678).** The findings-file shape is the whole integration contract — nothing authenticates the
  writer — so any component that persists a conforming file reaches the apply relay. That made a
  second producer a silent-data-loss bug: `fix` took the newest `*.md` and merged nothing, so a
  detector running after a full review shadowed the entire review with no error, no warning, and a
  green run. `fix` now takes every conforming file for the exact current branch, unions the coverage
  fields (`## Unparsed` concatenated, `## Surfaces` attributed per producer, every consumed file's
  `tier:` reported rather than one winning), and names the consumed set in its plan header. Dedup is
  presence-only — identical `Location` AND identical `Finding` text — deliberately narrower than
  Stage 3's ±3-line semantic key, which the `fix` action cannot compute because it runs no LLM stage
  and which would drop one of two distinct defects at `foo.ts:42` and `foo.ts:44`. A one-file set
  applies exactly the set it applied before — merge, union and dedup are all identities on one
  input — and an empty set keeps the clean STOP. The emitted bytes do differ: the plan header gained
  per-file lines and a `Surfaces (union)` line, and an interactive apply now writes a record.
- **The applied-plan record is now written on EVERY apply path and is the consumption ledger.**
  It was headless-`--yes`-only, so a bound anchored on it was a no-op on the dominant interactive
  path and the merge set would have grown without limit, re-injecting findings the required post-fix
  re-review had already resolved. `source-findings:` is now always a YAML block sequence of
  `name:` + `sha256:` mappings, one entry per consumed file. `fix` subtracts a candidate only when a
  record entry matches BOTH its file name and its content digest, and the exact-`branch:` filter
  binds records as well as candidates so a slug-collided branch's record cannot truncate the set.
  Consumption is per file, not per row: rows surfaced or narrowed out are named in the record body
  and recovered by re-running the review, never by re-consumption. Operators reading the branch
  findings directory will now see records from interactive applies where previously only headless
  runs produced them.
- **A consumed file is identified by its CONTENT, not by its file name.** A findings file's
  `<UTC-timestamp>-<topic>.md` name is unique only in the moment it is written — the timestamp has
  second resolution and the topic is producer-chosen — so with arbitrary producers sharing one
  directory a later file can reuse a name an old record already names. Matching on the name alone
  would retire that new file unread, silently skipping its findings. Two consequences: the merge-set
  subtraction now compares the digest as well as the name (above), and the consumption record's own
  file name carries the digest of its body — `<UTC-timestamp>-fix-pass-applied-<sha256-12>.md`,
  staged through `mktemp` and moved into place. Without that suffix, two applies on one branch
  finishing in the same UTC second wrote the same path and the second clobbered the first; because
  the record is now the ledger `fix` subtracts by, a lost record re-injected its files' already-
  applied findings on the next run. The digest also makes the remaining collision harmless: two
  byte-identical records name the same consumed set, so the overwrite is a no-op. Producers are
  additionally asked never to overwrite an existing findings path (write `-2`, `-3`, …), but that is
  hygiene against a producer losing its OWN findings — the fix action's correctness no longer
  depends on any producer choosing a collision-free name.
- **The coverage fields are required of `fanout`'s own writer, not of every producer.** The
  findings-file shape called `date`, `tier`, `## By dimension`, `## Unparsed` and `## Surfaces` required
  unconditionally, while the `fix` action's admission test is only `type:`, `branch:` and a parseable
  `## Findings` table — so a detector omitting them was conforming to one half of the contract and
  non-conforming to the other, and a producer author got a different answer depending on which file
  they read. The requirement on `fanout` itself is unchanged and still load-bearing, since Step 2's
  coverage union depends on it; what changed is that the shape now says whom it binds, and the
  admission test names the same field set from the other side.
- **The findings home is resolved through the binding, never assumed from the default's shape.**
  Both skills glossed it as `<memory_dir>/reviews/<branch-slug>/` unconditionally, but only two of
  `reference/topic-docs.md`'s five rungs compose that segment — a location declared in the
  consumer's `CLAUDE.md`, inferred from the repo, or chosen by the user is used as given. A producer
  and a consumer disagreeing about whether the segment is appended land in different directories,
  and the `fix` action's symptom is a clean empty-set STOP an operator cannot distinguish from "no
  findings" — the same green-with-hidden-findings class the merge set closes, arriving through the
  path instead. Both `SKILL.md` "Shared inputs" sections, `fanout`'s Step 1, and the plugin README
  now cite the binding as the authority instead of restating a path shape, and the binding states
  which rungs compose the segment.
- **Every row that did not land is rendered and attributed in the consumption record.** The record
  body now carries a "Not applied" table — location, finding, why, and the consumed file it came
  from — covering correctness rows surfaced rather than auto-applied, rows of any class the operator
  narrowed out, and unparsed entries. Previously the correctness line reported a bare `<surfaced>`
  count and a narrowed-out cleanup row was rendered nowhere at all, so the record did not meet its
  own stated requirement that every such row be named with its source file. Because consumption is
  per file, the file is retired whole and re-running the producer named in that column is the only
  route back to a deferred row — a count cannot say which producer that is.
- **The binding now cites the topic-docs convention's "Non-interactive / forked mode" rule.** Two of
  the resolution rungs confirm with the user or ask, and the binding stated no behavior for a
  context that can do neither — forked subagents, dispatched workers, and headless runs, which is
  exactly `fanout`'s `fix --yes` path. The rule is contract-owned, so the binding cites it rather
  than redefining it.

  **Migration — records written by 0.19.0 and earlier are honored.** Those carry
  `source-findings:` as a bare scalar repo-relative path, and they persist across the upgrade
  because the findings directory is gitignored local state. An entry that carries no digest — the
  legacy scalar, or any bare name — matches by name alone, compared by base name, so a legacy record
  still retires its file. Without that tolerance the legacy record would subtract nothing and its
  already-applied findings would be re-injected on the next `fix` — the exact harm the ledger exists
  to prevent. The fallback is bounded twice: an entry that has a digest never degrades to name-alone,
  and a digest-less entry is honored only when the candidate's `date:` is STRICTLY OLDER than the
  record's `date:` — declared frontmatter instants on both sides, never filesystem modification
  times, which a copied or restored findings directory rewrites. That second bound matters because
  nothing requires a producer to put a timestamp in its file name — a detector may write one fixed
  name it overwrites every run, and without the check a single stale legacy record would retire every
  future version of that file silently and forever. Equal dates keep the candidate, as does an
  unreadable or absent one: `date:` is producer-DECLARED, so a detector deriving it from the commit
  under review or a template constant makes equality the normal state, and subtracting on equal would
  reintroduce that permanent retirement through the tiebreak. Every branch of the comparison fails
  open, because re-application is recoverable and silent retirement is not. No operator action is
  required; pre-0.20.0 records may simply be deleted, being gitignored local state.
- **The findings-file shape now states what `date:` MEANS.** It was a bare `date: <ISO-8601 UTC>`
  with no semantics, which was harmless while nothing read it and is not now that the legacy path
  depends on it. `review:fanout`'s writer MUST stamp the instant the file is written — not the commit
  date, not a scan date, not a constant — and the file name must end in `.md`, which is what makes it
  visible to the consumer's scan at all. Both bind fanout's own writer; the consumer still assumes
  neither, which is why the comparison subtracts only on a strictly older candidate.
- **The empty-set STOP now prints where it looked.** It reported no unconsumed findings without
  naming the resolved directory or the rung that resolved it, so a wrong-directory resolution and a
  genuinely empty directory produced an identical clean stop — the one failure the step cannot detect
  was also the one an operator could not see. It now prints the searched path and its rung, and on a
  non-interactive run says that the rungs which ask or persist were skipped.

## [0.19.0]

### Added

- **`/review:code-review` and `/review:security-review` CI lane skills
  (ci-workflows#258).** Thin org-owned slash commands the
  `claude-review` / `claude-security-review` reusable workflows invoke via
  claude-code-action `plugins` + `plugin_marketplaces`. They carry the
  lane criteria, skip-gate, high-signal bar, and adversarial-validation
  target; the workflow wrapper still owns checkout, MCP install via
  `claude_args`, and reporting mechanics. Skills (not legacy `commands/`)
  per marketplace PLUGIN-PHILOSOPHY.

## [0.18.4]

### Fixed

- **`agents/ci-log-auditor.md`'s `add` rationale no longer misdescribes `gh --paginate`.** Finding
  6 told the reader that `/annotations` pages are "concatenated" arrays combined with `add`. They
  are not concatenated: with no `--jq`, `gh` merges array-shaped responses into ONE JSON array and
  emits a document per page only for object envelopes like `check-runs`, so `jq -s` there yields a
  one-element slurp that `add` unwraps. The published command was already correct — only the
  mechanism claim was wrong, in a file whose whole subject is being factually right about
  pagination, so a reader who believed it would mispredict the shape of the next endpoint. The
  prose now states both branches and names the condition that selects between them (`--jq`
  suppresses the merge), which also reconciles it with the per-page `--jq` caveat stated nine lines
  above it. Measured against `gh` 2.95.0.

## [0.18.3]

### Fixed

- **`agents/ci-log-auditor.md`'s annotation-gap cross-reference no longer truncates.** Finding 6
  fetched `repos/<owner>/<repo>/commits/<sha>/check-runs` unpaginated. The endpoint caps at 30 per
  page by default and signals nothing when it truncates, so the auditor compared the `##[error]`
  count against an under-counted check-run list — manufacturing a mismatch, or hiding a real one,
  with no visible symptom. Both that fetch and the per-check-run `/annotations` fetch now carry
  `--paginate` with `per_page=100`, each with a runnable form, and the agent is told to assert
  `total_count` against the flattened per-page count before drawing any conclusion — including the
  reason the naive assertion is wrong (`--jq` runs per page, so the count must be slurped across
  pages first). The two endpoints are called out as differently shaped rather than lumped together:
  `/annotations` returns a bare array with no envelope and no `total_count`, so the completeness
  assertion is unavailable there and `--paginate` is the only guard, and its pages are combined
  with `add` rather than through a `.check_runs` wrapper.

## [0.18.2]

### Changed

- **`/review:fanout`'s `description` now uses `Use when:`.** Its five routing phrases sat behind a
  lowercase `use for`, which the skill-quality gate does not recognize as trigger phrasing. All five
  are preserved verbatim and `'review this from all sides'` joins them.

## [0.18.1]

### Changed

- **README: `/review` is now the bundled reviewer, not a shorthand for this plugin (#2176).** As of
  Claude Code v2.1.223, "`/review` is an alias of `/code-review`; before v2.1.223, it was a separate
  command that ran a single-pass, read-only review of a GitHub pull request"
  (`code.claude.com/docs/en/code-review#review-a-diff-locally`, fetched 2026-08-10). The README's
  graceful-degrade bullet already distinguished the bundled `/code-review` command, the managed Code
  Review GitHub App, and the `code-review` marketplace plugin; it now names `/review` as a fourth
  spelling of the first of those, so a reader who abbreviates this plugin to its namespace doesn't
  land on the built-in reviewer by accident. Nothing about the plugin's own commands changes — 0.18.0
  already made `/review:quality-gate` and `/review:fanout` the only forms it registers.

## [0.18.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.17.2]

### Fixed

- **`skills/fanout`: the `code-review` plugin's comment is identified as the one this invocation
  created, not as the latest comment.** `context/findings-normalization.md` told the pipeline to
  retrieve that surface's raw text with `.comments[-1].body`, which is whatever landed most
  recently — the prose named the plugin's `### Code review` heading but the expression applied no
  filter at all. Any bot or reviewer commenting between the dispatch and the fetch was therefore
  normalized as `code-review` findings and written into the persisted report. Retrieval is now an
  ID-set difference: `SKILL.md` records the PR's comment IDs before dispatching, and the fetch
  selects the comment whose ID is new. Identity rather than a timestamp window, because a cutoff
  narrows *when* a comment arrived but never establishes *who* wrote it — a third party quoting the
  heading mid-dispatch would still have won. Identity is paired with a shape test, because being
  new does not make a comment the plugin's: a reviewer quoting the review posts a genuinely new
  heading-bearing comment, and when the dispatch posted nothing that quotation was the sole new
  match and was normalized as this surface's findings. The body must now BEGIN with the
  `### Code review` heading and carry the `🤖 Generated with [Claude Code]` trailer — the shape the
  plugin's own command file mandates — which a quotation fails, where a substring test did not. The
  trailer is matched by prefix rather than by its full link so an upstream URL change cannot
  silently un-match it. Author remains deliberately unfiltered: the plugin posts under whatever
  `gh` credential invoked it, so no fixed login exists and a hardcoded one would break for the next
  consumer. A `length == 1` guard refuses to guess: zero new matches (the dispatch produced none)
  and two or more (a genuinely ambiguous window) both yield empty output, documented as a
  `## Surfaces` skip — never a fallback to the latest comment.
- **`skills/fanout`: the pre-dispatch snapshot is taken in the step that dispatches.** `SKILL.md`
  Step 1 dispatches the surfaces and Step 2 only then opens
  `context/findings-normalization.md`, so a "capture this before dispatching" instruction living in
  the normalization context could never run in time. The snapshot now sits in `SKILL.md`'s
  `code-review` bullet, and it is carried into the retrieval as a spliced literal rather than a
  shell variable, which does not survive the tool-call boundary between the two steps.

## [0.17.1]

### Changed

- **`ci-log-auditor`: the 500-word output budget now says what to do when findings exceed it.** A hard
  word cap on a finding-bearing report with no overflow rule leaves dropping findings as the only way
  to comply — the opposite of the never-drop normalization `fanout` applies to the same findings. The
  agent now keeps every finding row and compresses evidence and recommendations instead.

- **`quality-gate` criteria mode: the five-step "Applying criteria to changes" list is one sentence.**
  The steps enumerated a procedure the model already performs, and step 2's change-nature taxonomy
  (new feature, refactor, bug fix, config) routed nothing — no other file in the plugin reads it, and
  step 1 matched on the change's surfaces rather than its nature. The replacement keeps all three
  load-bearing elements: grounding in the actual changes, selectivity, and the resolved severity
  vocabulary. The skip-list paragraph and the "How to use" routing list are untouched.

## [0.17.0]

### Added

- **`fanout`: dispatch contract — finder leaves are told coverage is their job.** The skill runs a
  5-stage normalization pipeline (dedup, agreement/rank) downstream of its leaves, and the Sonnet 5
  and Opus 4.8 prompting guides both state that current models follow a stated severity bar
  faithfully at the finding stage — same investigation depth, fewer reported findings — and that a
  harness with a separate filter stage should say so explicitly at the finder stage. Both review
  modes now append a verbatim coverage clause to every dispatched finding-producing leaf prompt:
  report everything including uncertain/low-severity findings, attach confidence and estimated
  severity, filtering happens downstream. Recall is restored without moving precision work — the
  pipeline remains the filter. run-everything's Workflow path carries the same clause in its
  script: both prompt constructors (`AGENT_PROMPT`, `slicePrompt`) append it, and the slice prompt
  asks for the high/medium/low confidence level, so the Workflow-accelerated sweep gets the same
  recall and confidence axis as live dispatch.
- **`quality-gate`: per-slice template reports coverage-first with a Confidence column.** The slice
  reviewer template now states that severity and confidence label findings rather than deciding
  whether they are reported, and its findings table carries a Confidence column — constrained to
  the severity baseline's high / medium / low vocabulary — feeding the fanout pipeline's confidence
  stage instead of leaving slice findings unscored (an unlabeled finding ranks above
  honestly-labeled low-confidence ones). The seams consume it end-to-end: the fanout normalization
  parse contract records the slice surface's native confidence and Stage 2 passes the label
  through, and quality-gate's own Step 3 report table gains the Confidence column. The agent
  leaves carry the same field: architecture-guardian and doc-drift-detector gain per-finding
  high/medium/low confidence in their output formats, code-reviewer extends its confidence line
  from design-smell findings to every finding (smells stay capped at medium), and
  security-reviewer's no-findings line no longer reads as a low-confidence reporting filter —
  matching the dispatch clause's ask and the parse contract's expectations.

### Changed

- **Agents: instruction scope made explicit where literal executors under-covered.** Current
  models do not silently generalize an instruction from one item to another (Sonnet 5 / Opus 4.8
  prompting guides, "More literal instruction following"), so four spots that demonstrated one
  instance while meaning a class now state the class:
  - `code-reviewer`, `security-reviewer`, `architecture-guardian`: the `REVIEW.md` code-span
    citation step now enumerates and resolves **every** citation of the `<path>.md#<heading>`
    shape (deduplicating repeated paths) instead of describing the procedure for "a citation" —
    a literal read resolved the first and silently truncated the criteria set.
  - `security-reviewer`: ecosystems with no dedicated section (Go, Rust, Ruby, Java, …) now have a
    stated floor — the OWASP table plus the cross-ecosystem list, with the unlisted status named
    in the report — instead of an accidental gap behind "apply the sections matching the
    ecosystems actually touched".
  - `ecosystem-specialist`: a detected ecosystem with no generic default (e.g. PowerShell) is no
    longer conflated with "has no such phase" — commands resolve from the repo, and a phase that
    resolves nowhere reports UNVERIFIED rather than skipping silently.
  - `security-reviewer`, `architecture-guardian`: the change-set step now says to Read the
    untracked files `git ls-files --others` lists (previously stated only in `code-reviewer`), so
    two dispatched reviewers no longer run a command whose output nothing told them to use.

## [0.16.1]

### Changed

- **`skills/fanout`: the reason the orchestrator plugins run on the main thread is now a
  configuration bound, not an impossibility.** `SKILL.md` said "a subagent cannot dependably do
  that" and `context/run-everything-mode.md` said a Workflow `agent()` "cannot dependably spawn
  them". The live
  [sub-agents documentation](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents)
  states that by default a subagent CAN spawn subagents of its own, within a nesting-depth limit, so
  both sentences asserted a limitation that does not exist. The rationale is now the narrower true
  one: that depth budget is settings-configurable through `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`
  (`1` turns nesting off) and so sits outside the skill's control, and at the limit Claude Code
  withholds the `Agent` tool — in a fork, keeps it but errors — whereas that limit never disables
  the main thread's own `Agent` tool.

  **The claim is deliberately scoped to the depth limit.** The session and concurrent subagent
  limits bind the main thread too, so no surface can claim an unconditional spawn guarantee.
  `run-everything-mode.md` now states only the placement it enforces — orchestrators on the main
  thread, never inside the Workflow — and points at `SKILL.md` for the rationale, because the
  sub-agents page holds workflow-spawned agents to their own limits rather than this one.

  **No behavior changes.** Both surfaces still run the orchestrators on the main thread and still
  keep them out of the Workflow; only the justification prose changed.

## [0.16.0]

### Changed

- **`context/severity.md`: each severity tier is now stated as a decidable test, not a qualitative
  label.** The tiers read "Must fix" / "Should fix" / "Consider" plus a list of examples, which lets
  a reviewer place a finding that resembles a listed example but leaves a novel finding undecidable.
  The Sonnet 5 prompting guide, "Code review harnesses", names this shape directly — "be concrete
  about where the bar is rather than using qualitative terms like `important`", the qualitative term
  being one of this file's own tier names. Each tier now carries a test the reviewer can argue a
  finding against: CRITICAL, whether you can name a concrete input, caller, or subsequent
  otherwise-correct change the defect makes produce a wrong, unsafe, or absent result; IMPORTANT,
  whether the finding names a
  stated rule violated, behavior added that no test covers, or a degradation or maintenance cost
  with a named trigger; SUGGESTION, neither, so a preference among alternatives that all work. The
  example lists are retained as illustrations of the tests.

  **No finding changes tier.** The tests were written to restate the existing bars, and the example
  lists are unchanged — this states the criterion, it does not re-tier.

  **CRITICAL's subsequent-change limb is qualified `otherwise-correct`, which is what holds that
  guarantee.** Unqualified, "a subsequent change that the defect makes produce a wrong result" is
  satisfied by **code duplication** read literally — the subsequent change is an edit to one copy,
  after which the copies diverge. Because the tests are applied in order and resemblance to a listed
  example is explicitly not a rebuttal, that CRITICAL match would win and silently promote
  duplication out of IMPORTANT, where the previous text pinned it. The qualifier draws the line the
  example lists already assumed: a **cascading architecture violation** breaks a future change whose
  author did everything right, so it stays CRITICAL, while **duplication** bites only through a
  future edit that is itself incomplete, so it stays IMPORTANT.

- **The P1–P5 security fold now states its precedence over the tier tests.** `security-reviewer`
  emits CVSS-anchored P-levels folded as P1/P2 → CRITICAL, P3 → IMPORTANT, P4/P5 → SUGGESTION.
  CRITICAL's new test names an unsafe result, which a P3 finding also satisfies read literally, so
  the fold is now marked as deciding the tier for a P-scored finding. Without that precedence the
  criterion-stating change would have silently promoted every P3 to CRITICAL.

## [0.15.5]

### Fixed

- **`quality-gate`'s code-mode boundary no longer calls `/code-review` "built-in"**
  (doc-accuracy fix). `context/code.md` headed its boundary "the built-in `/code-review`
  skill" and opened "Claude Code ships a built-in `/code-review` bundled skill" — a
  compound of two categories the official docs keep apart. The commands reference
  states "Most are built-in commands whose behavior is coded into the CLI" and marks
  `/code-review` **[Skill]**, "a bundled skill"; the skills page lists `/code-review`
  among the bundled skills and says bundled skills are "prompt-based … Most built-in
  commands instead execute fixed logic directly", with `/doctor` cited as having been
  "a built-in command rather than a bundled skill" before v2.1.205 — the two labels are
  mutually exclusive. `/code-review` **is** a bundled skill; only the "built-in"
  modifier was wrong, so the fix drops it rather than re-labelling the surface. The
  heading and opening sentence now read "bundled skill" and link
  <https://code.claude.com/docs/en/skills#bundled-skills>. The plugin's other
  `/code-review` references (`README.md`, `fanout/SKILL.md`,
  `fanout/context/findings-normalization.md`, `quality-gate/context/pr.md`) already
  carry the correct "bundled" modifier and are untouched. Behavior is unchanged — the
  boundary's routing advice, the report-only contract, and the `--fix` / `--comment`
  opt-in gate all stand.

  Three released entries below carry the same smear — `0.15.1` ("a bundled built-in
  command"), `0.14.7` (the entry that added this boundary section: "always-available
  built-in `/code-review`"), and `0.14.2` ("`/simplify` is an external/built-in
  skill"). They are left as written: a released entry records what that version
  shipped, and this file's own `0.15.3` entry sets the precedent of correcting a past
  rationale in a new entry rather than editing the old one.

## [0.15.4]

### Fixed

- `fanout`'s pre-computed committed-diff-size probe no longer fails to load the skill from a
  worktree-isolated agent. The harness composes a skill's `## Pre-computed context` lines into one
  shell invocation, and the worktree-isolation Bash guard refuses any genuine `$` expansion — the
  line's `D="$(git ls-remote …)"` assignment and command substitution were therefore enough to make
  the whole block, and with it the skill, refuse to load. The fallback chain moves verbatim into a
  bundled `skills/fanout/scripts/diff-vs-base.sh` invoked through `${CLAUDE_PLUGIN_ROOT}`, which the
  harness substitutes into a literal path before any shell sees it; `$` inside the script file is
  unrestricted. Behavior is unchanged, including the `git fetch origin <default-branch>` side effect
  and the distinction between an empty resolved range (prints nothing) and no resolvable base
  (prints `unavailable`). The line's awk `$2` was probed and is not a trigger, so it stays. Covered
  by `diff-vs-base.test.sh` across all four branches of the chain (#1687).

## [0.15.3]

### Fixed

- Restored the `code-review` marketplace plugin as a real, distinct review surface across the
  plugin. The `0.15.1` and `0.15.2` entries below both state a false premise as their rationale —
  that no installable `code-review` plugin exists and that `fanout` "described the same nonexistent
  plugin". `anthropics/claude-plugins-official`'s `marketplace.json` lists `code-review`
  (`./plugins/code-review`, category `productivity`) alongside `pr-review-toolkit`, and
  `plugins/code-review/commands/code-review.md` defines `/code-review:code-review`. Those entries
  are left as written — history is corrected forward, not rewritten. Three surfaces overlap a PR
  review and are now enumerated as three everywhere: the installable `code-review` marketplace
  plugin, the bundled `/code-review` command, and the managed Code Review GitHub App service.
  `pr.md`'s Boundary covers all three and its mutation gate again covers the plugin, which takes a
  PR as its only target and ends every run by commenting the surviving findings back onto it — the
  gate is unconditional because the plugin has no session-returning mode; `fanout`'s orchestrator
  roster is back to three plugins, carrying that gate plus an applicability gate — the same PR-only
  targeting makes the plugin undispatchable on a local branch with no open PR, which
  `run-everything` step 3 would otherwise invoke as an empty surface; and
  `findings-normalization.md` carries the `code-review` parse contract again — with the retrieval
  step it needs, since the plugin posts its findings instead of returning them and the row would
  otherwise have no Stage-0 input — which restores the only referent for the Stage-1 "surfaces
  emitting no severity → DERIVE" rule; the README's
  optional-orchestrator roster names it again. The `pr-comment-gate-opt-in` eval covers the plugin
  alongside the other two mutating surfaces. Re-verified against the live marketplace manifest,
  upstream `plugins/code-review/commands/code-review.md`, and
  <https://code.claude.com/docs/en/code-review> (#1402).
- The behavioral corrections `0.15.1` and `0.15.2` got right are unchanged: bare
  `/code-review <target>` stays ungated (report-only; only `--fix` and `--comment` mutate), the
  managed Code Review GitHub App service stays described as the built-in/managed service it is, and
  `codex` stays in the README's optional-orchestrator roster.

## [0.15.2]

### Fixed

- Carried the `code-review` framing reconciliation of `0.15.1` into the `fanout` skill, which
  described the same nonexistent plugin independently: `SKILL.md`'s "Orchestrator plugins" section
  and `context/findings-normalization.md` both listed `code-review` as one of three optional
  `claude-plugins-official` orchestrator plugins invoked as `/code-review:code-review`. `SKILL.md`
  now carries its own "Boundary" section for the two real surfaces, and
  `findings-normalization.md`'s per-surface parse-contracts table no longer lists `code-review` as
  a normalized fan-out leaf. Two `fanout` evals (`pr-comment-gate-opt-in`, renamed
  `unscored-surface-severity-derived-not-invented`) carried the same stale framing and were updated
  for internal consistency. The two surface descriptions are not restated — `SKILL.md` points at
  `pr.md`'s Boundary for those and carries only the fan-out-specific reasoning.
- `fanout`'s exclusion of the bundled command no longer rests on classing a **bare**
  `/code-review` invocation as PR-mutating. Per <https://code.claude.com/docs/en/code-review>
  ("Review a diff locally"), bare `/code-review` is report-only — findings arrive in the
  conversation, and only `--fix` and `--comment` mutate — matching the gate scoping `pr.md` already
  applies. The Boundary section now states the real reason it is not a normalized leaf (it is
  itself a multi-agent review of the same diff, with no documented output schema to write a parse
  contract against) and points the reader at running it directly (review-caught).
- The README's optional-orchestrator roster also names `codex` (OpenAI Codex marketplace), the
  other orchestrator `fanout` dispatches, and points at both skills' Boundary sections
  (review-caught).

## [0.15.1]

### Fixed

- Reconciled stale `code-review` framing in `quality-gate`'s `pr.md` and the plugin README: it
  described `code-review` as an optional `claude-plugins-official` marketplace plugin invoked as
  `/code-review:code-review`. Per current official docs, `/code-review` is a bundled built-in
  command (invoked bare) and the "parallel agents / posts PR comments" behavior actually
  describes the separate managed Code Review GitHub App service — neither is an installable
  marketplace plugin. `pr.md` now documents both surfaces distinctly under a Boundary section,
  mirroring the pattern `code.md` already uses for its own built-in boundary (#266/#735). The
  section's mutation gate covers only the surfaces that actually write — `--comment` (posts to the
  PR), `--fix` (mutates the working tree), and the managed service — leaving bare
  `/code-review <target>` ungated as a read-only option.

## [0.15.0]

### Added

- Deep-scan escalation routing to the official Claude Security plugin (`/claude-security`) from
  quality-gate security mode and the fanout leaf roster — presence-gated, pointer-only
  (contract stays upstream at <https://code.claude.com/docs/en/claude-security>), and explicitly
  not a fan-out leaf. The fanout pre-flight gate checks ask shape before diff resolution, so a
  whole-repo security-audit ask escalates regardless of diff state.

## [0.14.11]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.14.10]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.14.9]

### Added

- **`doc-drift-detector` gates classification behind an existence pre-check**
  (#505). Before judging a page's accuracy, the agent now asks the admission
  question first — could a reader with repository search derive this content
  from the code itself? — and routes an admission failure to a new
  **Deletion-candidate** category (recommend relocate-then-delete, never
  auto-delete) instead of forcing it into Stale/Missing/Aspirational.
  Decisions, domain language, thin navigation, and policy/wiring pages always
  pass admission. The four-factor scoring behind a contested call reuses
  `/docs-hygiene:audit-derivability`'s rubric by reference (optional
  namespaced skill invocation, degrading to the admission question standalone
  when that plugin is unavailable). Ships as a portable-baseline default;
  a consuming repo's own declared documentation-existence convention overrides
  it via `/re-anchor:follow-our-standards`'s resolution ladder. Report-only,
  matching the agent's existing read-only contract.

## [0.14.8]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.14.7]

### Added

- **`quality-gate` code mode documents its boundary with the built-in
  `/code-review`.** The mode triggers on "code review" and reviews the current
  diff — the same target Claude Code's bundled `/code-review` skill covers — yet
  `context/code.md` never acknowledged the built-in existed, leaving a user with
  no basis to choose between them. The context file now carries a **Boundary**
  section: reach for this mode when the review must ground in the project's own
  standards and severity vocabulary (resolved through the standards index), stay
  report-only, and land in the gate's unified findings report; reach for the
  always-available built-in `/code-review` for a fast zero-dependency pass or its
  `ultra` cloud deep-dive when project-standards grounding is not the point,
  noting that its `--fix` / `--comment` flags mutate and sit outside the review
  modes' report-only contract. Documents the boundary rather than dispatching the
  built-in as a leaf surface — code mode's convention-grounded dispatch
  (`pr-review-toolkit` / `code-reviewer`) is not duplicated review logic that a
  thin router would remove, and delegating to the generic built-in would drop the
  standards grounding, the unified report, and the report-only guarantee.

## [0.14.6]

### Fixed

- **`quality-gate` slash invocation no longer dies silently in headless
  sessions.** The skill's *Pre-computed context* block injects dynamic context
  via the `` !`<command>` `` syntax, which is preprocessing that runs during
  prompt expansion — before the model turn — so the permission gate sits *above*
  the shell. In a non-interactive session (`claude -p "/review:quality-gate …"`)
  the `gh pr list` preflight was permission-denied during that preprocessing,
  and the whole invocation aborted with empty output and exit 0 — total silent
  failure with no model output. The in-command `|| echo "unknown"` guard is
  structurally incapable of catching this: the denial happens a layer above the
  shell, so the shell string (and its `||` fallback) never runs. Prose
  invocation degraded gracefully only because it has no dynamic-context
  preprocessing — the model issues `gh` as an ordinary Bash *tool* call whose
  denial returns a handleable result. Fix: declare `allowed-tools` frontmatter
  authorizing every segment of the three compound pre-computed lines
  (`git branch --show-current`, `git status`, `head`, `echo`, `gh pr list`), the
  documented canonical mechanism for dynamic-context bash, matching the
  `pressure-test` and `wayfind` in-repo precedents. The existing `|| echo`
  fallbacks are retained — they cover a different failure mode (`gh` missing /
  unauthenticated / no PRs) that `allowed-tools` does not touch. The three
  fixed pre-computed lines are granted as EXACT full-command rules (no
  prefix wildcards), so neither mutating subcommands nor output-redirection
  writes (`echo payload > file`, `head src > dst`) fall inside the grant;
  the only wildcard kept is `Bash(gh pr list:*)` for the documented uncapped
  fallback query.

## [0.14.5]

### Fixed

- **Reviewer agents captured the wrong diff base in single-branch clones whose
  branch is based off a non-default branch.** The diff-base resolution ladder in
  all four change-set agents (`code-reviewer`, `security-reviewer`,
  `architecture-guardian`, `ecosystem-specialist`) fetched the PR's real base
  (`git fetch origin "$PR_BASE"`) into `FETCH_HEAD`, but rung 1 then referenced
  `origin/$PR_BASE` — a ref that a `--single-branch` clone never creates — so the
  rung failed and a later fallback rung fetched the default branch, overwriting
  `FETCH_HEAD` before the real base was ever used. `merge-base` then ran against
  the default branch, folding the base branch's own pre-existing commits into the
  review as if they were the PR's (empirically: 3 commits reviewed where only 1
  belonged to the PR). The base rev is now captured
  (`BASE="$(git rev-parse FETCH_HEAD)"`) immediately after the base fetch and used
  directly for `merge-base`, before any fallback fetch can clobber `FETCH_HEAD`;
  the prior no-PR / fetch-failed behavior is preserved via
  `${BASE:-origin/${PR_BASE:-HEAD}}`. Facet B of #625; #661.

## [0.14.4]

### Changed

- **`fanout` `fix` action no longer mutates the working tree unconfirmed in a
  headless session.** The fix action's Step-3 confirmation gate previously
  self-downgraded — "interactive sessions; non-interactive sessions proceed
  without the gate" — so a headless `/review:fanout fix` applied correctness- and
  cleanup-class fixes with no confirmation at all, in exactly the unattended
  context where a human check matters most. The silent waiver is replaced with an
  explicit opt-in flag mirroring the `ai-briefing:generate` `--yes` / `-y`
  precedent ("Skip the pre-execution confirmation gate. Required for headless
  runs."). Interactive `fix` is unchanged (emit plan, confirm, apply). Headless
  `fix` WITHOUT `--yes` now emits the classification plan and STOPs, mutating
  nothing — the plan is the report, so an operator reviews what would have been
  applied and re-runs with the flag. Headless `fix` WITH `--yes` applies, then
  writes a durable applied-plan record (`type: fix-pass-record`) into the branch
  findings directory for after-the-fact review; the non-`review-findings` type
  makes the fix-pass locator skip it so it is never re-consumed as findings.
  Start-strict posture: loosening later is additive, tightening later would break
  automations built against a permissive default. Implements the operator-accepted
  direction on #435.

## [0.14.3]

### Fixed

- **Review diff base no longer bakes `main` as the terminal default-branch
  fallback** (silent-empty-diff fix). Every base-resolution surface resolved the
  default branch as `origin/HEAD`, then fell straight to the literal `origin/main`.
  `origin/HEAD` is frequently unset in CI, shallow, single-branch, and fresh
  clones, so a repository whose default branch is `master`/`develop` fell past a
  non-existent `origin/main` all the way to the `echo HEAD` / `echo "unavailable"`
  terminal — producing an EMPTY diff on a clean committed branch, i.e. a silent
  no-op review with no error. This violated the convention-resolution ladder's
  "No baked repo assumptions, ever". A dynamic resolution rung now sits BEFORE the
  literal `origin/main`: `git ls-remote --symref origin HEAD` queries the remote's
  own default branch over the same transport the clone used — host-agnostic,
  needing neither a locally-set `origin/HEAD` symref nor `gh`. The resolved branch
  is then fetched and the diff is taken against `FETCH_HEAD`, because `ls-remote`
  reports only the branch name and does not populate a local `refs/remotes/origin/*`
  ref — so `origin/<default>` is unresolvable in a full-depth `--single-branch`
  clone (and in a full clone whose `origin/HEAD` is unset), where
  `merge-base "origin/<default>"` would otherwise still fall through to the
  empty-diff terminal. This mirrors the existing `PR_BASE` fetch. The rung stays
  lazy — the network `ls-remote`/fetch fire only when the local `origin/HEAD` rung
  fails, so the well-connected common case pays no round-trip. Falls to
  `origin/main` only as the terminal last resort. Applied identically across the
  four reviewer agents (`code-reviewer`, `security-reviewer`, `architecture-guardian`,
  `ecosystem-specialist`), the `fanout` pre-computed diff-size snippet, and the
  `fanout`/`quality-gate` shared-input and subagent-prompt prose. The remote name
  stays `origin` (de-hardcoding the remote is the cross-plugin shared default-branch
  helper tracked separately by #442, out of scope here). Same bug shape as the
  toolchain gap resolved in #411, using that fix's `git ls-remote --symref`
  resolution mechanism.

  Known limitation: a `--depth=1` shallow clone (the default `actions/checkout`
  shape) still degrades to the empty-diff terminal — after fetching the resolved
  branch at the same shallow depth, `merge-base FETCH_HEAD HEAD` finds no common
  ancestor. Resolving that requires deepening/unshallowing (or a convention-aligned
  report-and-stop) — a real design fork, tracked and deferred to #625 rather than
  bolted onto every reviewer-agent invocation here.

## [0.14.2]

### Fixed

- **`fanout` fix-pass docs describe `/simplify` as an optional in-session skill,
  not "bundled"** (doc-accuracy fix). No `simplify` skill ships under
  `plugins/review/`; the plugin bundles the `fanout`, `quality-gate`, and `setup`
  skills, while `/simplify` is an external/built-in skill resolved from the
  session. `context/fix-pass-mode.md` and the `fanout` eval expectation now call
  the cleanup-class route the "optional in-session `/simplify`" skill. Behavior is
  unchanged — the existing fallback ("when available in the session; otherwise
  apply the cleanup findings directly, one file at a time") already degrades
  gracefully; only the inaccurate "bundled" descriptor is dropped.

## [0.14.1]

### Fixed

- **`quality-gate` pr mode gates the PR-comment-posting orchestrator behind
  explicit opt-in** (un-sanctioned side-effect fix). The `code-review`
  orchestrator's PR mode posts findings as a PR comment, which violates the
  review modes' report-only contract; `context/pr.md` previously presented it
  as the ungated "Primary path." It now carries the same **PR-mutation gate**
  the sibling `fanout` skill already applies to the identical call: when the
  branch has an open PR, the posting mode is dispatched only on explicit user
  opt-in ("post the review comment"), otherwise it is skipped (the skip is
  named in the review report) and review falls to the read-only manual path.

## [0.14.0]

### Changed

- **Setup adopts the uniform check/apply contract** (fleet conformance wave,
  dim 8 — caught by the new contract gate rather than the wave list). `check`
  runs the standards-contract binding's state-reading procedure read-only
  (index presence, row-path validation, version delta) and reports; `apply`
  carries the existing bootstrap/reconfigure/migration flow with its
  explicit-confirmation gates intact, re-verifying after every write. The
  by-reference discipline is unchanged — the procedure still lives in the
  contract binding, not restated here.

## [0.13.0]

### Changed

- **Runtime prerequisites declared and classified** (prerequisite-visibility
  wave). README gains a Requirements section (git; authenticated `gh`; Bash
  via Git Bash on native Windows). `ci-log-auditor` now checks `gh`
  presence/auth up front and stops with a remediation message instead of
  auditing from partial evidence when the CLI is missing.

## [0.12.0]

### Added

- **Named design-smell baseline in `code-reviewer`** (Fowler, *Refactoring* 2nd ed., ch. 3): twelve
  smells — Mysterious Name, Duplicated Code, Feature Envy, Data Clumps, Primitive Obsession,
  Repeated Switches, Shotgun Surgery, Divergent Change, Speculative Generality, Message Chains,
  Middle Man, Refused Bequest — matched against the diff as advisory heuristics. Findings default
  to SUGGESTION at medium/low confidence, carry an explicit confidence label the fanout
  normalization pipeline passes straight through; escalation happens only through a documented
  project rule (the rule carries the severity), and a project standard that endorses a flagged
  pattern suppresses the smell. The prior duplicated-structural-boilerplate bullet is folded into
  Duplicated Code. `fanout` and `quality-gate` inherit the baseline by dispatching the agent; the
  external `pr-review-toolkit` orchestrator path and the self-mode general fallback do not reach it
  (documented limitations). No config surface added — smell suppression rides the existing
  `REVIEW.md` / project-rules seam. No live upstream; regeneration trigger is a Fowler edition
  revision to ch. 3 or a change to `code-reviewer`'s design-smell taxonomy.

## [0.11.0]

### Changed

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` states review
  reports are lane-local (invisible to sibling worktrees and clones) and cross-lane findings
  graduate through the work-item tracker as tickets that point, never as pasted report bodies.

## [0.10.0]

### Added

- **Standards-index criteria resolution in `/review:quality-gate`**: criteria mode resolves
  review criteria through the consumer's standards index via the new
  `reference/standards-contract.md` binding (synced from the marketplace's standards
  convention) — repo review docs like `REVIEW.md` become inference sources inside the binding's
  resolution ladder, with the severity baseline and agent checklists as the final fallback.
  Step 1's "What conventions apply?" routes through the same index, so every review mode
  (self/code/architecture/security/pr/slice/restatement) inherits index-grounded conventions and
  reviews against the same rows plan formulation loaded.
- **New `/review:setup` skill**: idempotent standards-index bootstrap implementing the binding's
  normative Setup-and-migration section — conforming-index short-circuit, row-path validation,
  directional version-delta migration, and a setup-owned `<standards_dir>/.gitignore` for
  personal overlays.
- **Tripwire test** `tests/standards-binding.test.sh` guards the binding references, the
  ladder-pointer discipline, and the Step 1 index routing against future prose edits.

## [0.9.0]

### Added

- **Cross-repo `REVIEW.md` citation dereferencing** in `code-reviewer`, `security-reviewer`, and
  `architecture-guardian`. Each now recognizes a code-span citation in a consuming project's
  `REVIEW.md` shaped like `<relative-path>.md#<heading>`, splits it into the file path and heading
  anchor, and Reads only the `.md` file — which may live outside the current repository, mounted via
  `--add-dir` — before locating the referenced heading for the full criterion behind a thin
  `REVIEW.md` line before finalizing an overlapping finding. An unresolved citation (mount absent,
  wrong path) is noted in the agent's report rather than dropped silently or treated as a hard
  failure. Whether a `--add-dir`-mounted path is visible to a plugin subagent's `Read` tool the same
  way it is to the main session is not yet empirically verified against a live cross-repo mount.

## [0.8.0]

### Changed

- Renamed the plugin `review-toolkit` → `review` and its skill `code-review-fanout` → `fanout`;
  the six reviewer agents move to the `review:` namespace. Invocations are now `/review:fanout`
  and `/review:quality-gate`. Existing installs migrate automatically through the marketplace
  renames map.

## [0.7.0]

### Added

- **Judgement-call labeling in reviewer output formats.** `code-reviewer` and
  `architecture-guardian` now label design-smell and convention findings as judgement calls —
  advisory, reviewer-tier — never as hard violations; hard-violation framing is reserved for
  findings backed by a documented project rule, a failing check, or a demonstrable defect
  (`architecture-guardian` admits a finding into its Violations bucket only with that backing).
- **Pre-flight fail-fast gate in `code-review-fanout`.** Both review modes now resolve the review
  diff base and confirm a non-empty diff BEFORE any surface is spawned: an unresolvable base ref
  or an empty change set reports and stops — reviewers are never fanned out against an empty or
  wrong diff. The default mode's inline dispatch-gate summary folds into the shared gate; the full
  clean-tree and untracked-only logic stays in the default-mode context, and run-everything mode
  defers to the same gate.
- **Per-dimension breakdown in the fanout report.** The persisted findings file keeps the merged
  ranked queue and adds a required `## By dimension` section regrouping the same findings under
  one heading per review dimension — a merged rank can mask one dimension failing badly while the
  others pass. Stage 4 of the normalization pipeline carries the matching two-axis presentation
  rule; the fix action's parse contract (`## Findings` + `## Unparsed`) is unchanged.

## [0.6.0]

### Added

- **Restored fanout regression evals.** `code-review-fanout`'s `evals/evals.json` gains 14 cases
  (ids 7–20) covering behavior that was still documented but had lost eval coverage: dedup and
  severity-derivation (Stage 3/4 cross-surface merge, content-derived severity for
  no-native-severity surfaces), the fix-pass safety fence (correctness findings are never routed
  to `/simplify`, branch-scoped findings lookup, mixed-class routing), and run-everything's
  null-reconciliation and priority-ordering (named null leaves, the tier-1 barrier ahead of
  tier-2). Also restored: per-tier surface routing and promotion, the large-tier ownerless-slice
  exclusions, the findings-file shape contract, the clean-tree short-circuit, and graceful
  orchestrator-absent degradation.

## [0.5.0]

### Added

- **Model-assignment cost routing for the findings-normalization pipeline.** Each stage heading in
  `code-review-fanout`'s findings-normalization context now carries its model annotation, and a
  closing `## Model assignment` section summarizes the routing: Stage 0 Sonnet (parse fidelity),
  Stages 1–2 deterministic/Haiku (enum lookup), Stage 3 Sonnet (semantic merge), Stage 4
  deterministic.

## [0.4.0]

### Changed

- **Consume the topic-docs convention** (`docs/conventions/topic-docs/README.md`), bound for this
  plugin in the new `reference/topic-docs.md`. The default findings location moves from
  `.claude/review/<branch-slug>/` to `.work/reviews/<branch-slug>/` — the memory tier's
  concern-scoped reviews home (branch axis, never committed, self-ignoring root). Resolution
  follows the contract's ladder: the concern file's `memory_dir` first, then a consumer-declared
  review-artifacts location (an inference source — the skills offer to persist it into the concern
  file), then the default. The session's first memory-tier write runs the verify-or-create
  self-ignore guard on the resolved memory root; no skill edits the consumer's root `.gitignore`.
- **`.claude/review/` retired outright.** The prior findings location gets no compatibility
  layer, no dual-read window, no migration tooling; move residual content manually.
- **`quality-gate` self-mode plan source:** the approved plan/brief is now sourced from the
  conversation, else the topic's contract slice `docs/topics/<slug>/PLAN.md` (memory-tier fallback
  under `contract_tier: local`), replacing the untyped "project's working notes" phrase.

### Added

- **`reference/topic-docs.md`** — the plugin's compact binding to the topic-docs contract: what it
  writes (memory tier only, branch axis), resolution order, branch-slug and timestamp spec, and
  runtime guards.

## [0.3.0]

### Added

- **Skill evals for the two orchestration skills.** Rich-form `evals/evals.json` authored for
  `quality-gate` (6 cases) and `code-review-fanout` (6 cases), each covering trigger/routing, the
  happy path, a refusal/guardrail, and an anti-pattern the skill must not do. Additive test
  definitions only — no behavioral change to any skill or agent.

## [0.2.0]

### Changed

- **`ecosystem-specialist` consumes the ecosystem-commands contract.** The agent now resolves each
  ecosystem's build/test/lint command truth from the consumer repo's `.claude/ecosystems/<ecosystem>.yaml`
  files (authoritative when present) — the marketplace-wide ecosystem-commands contract
  (`docs/conventions/ecosystem-commands/README.md`) — falling back to the project's documented
  conventions, then the agent's own bundled generic defaults as an explicit last resort. Ecosystem
  detection may use the contract's `globs` when config exists. Report format, MISSING-tool handling,
  and detection behavior are unchanged; only the command-truth sourcing moved from the agent's inline
  defaults to the declared contract.

## [0.1.0]

- Initial release: six read-only reviewer agents (`code-reviewer`, `security-reviewer`,
  `architecture-guardian`, `doc-drift-detector`, `ecosystem-specialist`, `ci-log-auditor`) plus two
  orchestration skills (`quality-gate`, `code-review-fanout`).
