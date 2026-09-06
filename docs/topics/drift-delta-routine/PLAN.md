# Plan: drift-delta routine on the ci-cron surface

Container: #3803 (Epic: drift discoverability). Planning slice: #3809. Remaining
implementation slice: #3819. Branch: `plan/3809-drift-delta-routine`.

Revision 2 (2026-09-06), after a fresh-context adversarial verification. The changes from
revision 1 are recorded in "Verification record" at the end.

## Status of the container's slices

| Slice | State | This plan's posture |
|---|---|---|
| #3810 codebase-health audit Boundary router | Shipped: PR #3828 merged 2026-09-06 (codebase-health 0.9.0; the audit's Boundary now routes to `/instruction-placement:delta` and `/overengineering:delta` and says each run is a full pass). #3810 is closed. PR #3829 was closed as a duplicate of #3828. | Not planned here. The merged Boundary text was re-read on `origin/main` and does not contradict this plan. |
| #3811 instruction-placement delta baseline slot | In flight: PR #3831 (open, review threads open, currently CONFLICTING against main). PR #3833 was closed as a duplicate of #3831. | Not planned here. Read for consistency only. |
| #3819 routine fan-out | Blocked by #3809. The only remaining implementation slice. | Planned below, one phase. |

Nothing in this plan edits a file either in-flight PR touches (the file lists are disjoint).
The one touch point is that the new routine leaf names `/instruction-placement:delta` by
slash name only, passes it no arguments, and names no artifact path, so #3831's relocation of
that lane's artifacts (from a plugin-data tree keyed by worktree hash to the memory tier)
cannot contradict the leaf whichever side of the merge a reader is on.

## Goal

Ship a standing routine class in the `autonomy` plugin's routine catalog whose tracked
definition leaf names the instruction-placement delta, the overengineering delta, and the
codebase-health audit skills as its fan-out, with the leaf as the instruction artifact an
org's scheduled handler points at, and with the run prerequisites those three skills actually
have stated where an adopting org will read them.

## Settled decisions (not reopened) and how the shipped contract expresses them

- **The scheduling surface is `ci-cron`, not a cloud scheduling surface.** That is a
  decision about this organization's binding of the class, and the shipped contract must
  express it without breaking its own hosting rules. Constraints found in the tree: the
  catalog's Hosting stance fixes four invariants only and calls hosting a deployment-owned
  binding with non-normative profiles; a class parameter binds every adopter; five of the ten
  leaves carry the clause "No vendor scheduling surface is named here; guided setup
  researches scheduling surfaces live"; the token `ci-cron` is defined in the setup skill's
  wiring template (`skills/setup/templates/routine-definitions.md`) and appears nowhere under
  `reference/` today; and a CI surface is itself a fresh checkout per run, so "clone-per-run"
  does not separate it from a hosted surface. So the leaf states the **run predicate** as a
  fact of the fan-out (a run that resolves no branch identity and persists no memory-tier
  home compares nothing, and the report says so), then gives one **illustrative binding, not
  a fixed requirement**, in the same shape the catalog's "Instruction provenance" section
  uses: a scheduled job on the CI-orchestration home whose runner restores that home and
  checks out the branch, which guided setup records as the `ci-cron` scheduler class. The
  leaf keeps the "No vendor scheduling surface is named here" clause verbatim, excludes
  nothing, and makes `ci-cron` neither a class parameter nor a declaration. Nothing in this
  container registers a surface; the org-side binding (this repository's own, when it comes)
  is where `ci-cron` is actually chosen and where the "no cloud surface" half is enforced.
- **Instruction content lives in the tracked leaf.** The catalog row points at the leaf. No
  stored prompt carries instructions (`routines.md`, "Instruction provenance").

## The extend-versus-sibling decision: sibling row `drift-delta-sweep`

The planning slice asked which of two shapes to build. The answer is a **new `v1` class row,
`drift-delta-sweep`, with its own leaf**, not an extension of `doc-freshness-sweep`.

Why, in order of weight:

1. **Identity ratification.** `doc-freshness-sweep/advisory` and
   `doc-freshness-sweep/docs-change` are routine identities an adopting org ratifies as
   admission data on its security binding (`admission.classification.temporal`; the setup
   evals' fixtures bind `doc-freshness-sweep/advisory` to a surface named for doc freshness).
   Broadening what the advisory posture does, to enforcement-surface and instruction-placement
   drift, changes what a ratified entry authorizes without the org re-reviewing it. The
   routine slice's reconciliation rule is that an existing binding is "surfaced as the diff
   and reconciled, never silently overwritten". A new identity is fail-closed human-gated
   until an org binds it, so no adopter's behavior changes on upgrade.
2. **Class purpose.** `doc-freshness-sweep` is the semantic reread of docs against their
   subject. Two of the three fanned-out lanes (instruction placement, enforcement-surface
   clutter) are not doc freshness.
3. **Catalog precedent.** Two classes with overlapping cells and a class parameter stating
   the distinction is an established shape (`clone-trend-gate` vs `coverage-mutation-watch`).

The overlap is stated, not hidden: `/codebase-health:audit`'s documentation dimension covers
ground `doc-freshness-sweep` also covers. A class parameter records it.

### Why `v1` and not `join: proven recurring manual pattern`

This is the reviewer judgment call in the plan, and it is flagged as one. The catalog's `v1`
legend reads "proven manual pattern; definition leaf ships under `routines/`", and the
plugin's CHANGELOG `[0.19.1]` refused to flip `cant-fail-test-repair` to `v1` on the ground
that "a detector proves detection, never the repair pattern that trigger names".

That ruling turned on the routine's judgment portion (the repair) being unbuilt. Here all
three lanes are built skills, and the routine's substance is to run them on a cadence and
report movement. What the evidence does and does not show, stated plainly:

- The pattern at class level, an operator re-running report-only drift detectors on a
  cadence and reading what moved, is proven: this repository's `.github/recurring-schedule.json`
  carries two such rows (`stale-doc-drift-watch`, `listing-budget-watch`, quarterly), and the
  other `v1` leaves cite their precedent at this pattern level too (`doc-freshness-sweep`:
  "the periodic docs review pass").
- No run record exists for these three lanes specifically. The owning plugin's
  `recurring-wiring.md` recommends a recurring tracker item and ships no schedule;
  `/instruction-placement:delta`'s "from a scheduled lane" is a trigger phrase, not a run;
  the recurring schedule names none of the three.
- The container Brief itself presupposes a leaf ("Routine instruction content lives in the
  tracked leaf"), and only a `v1` row ships one. A `join:` row would make #3819's leaf
  criteria and #3803's criterion 2 unsatisfiable as written and send the slice back to
  `/work-items:decompose`.

The plan therefore proposes `v1` on the class-level pattern and records the ruling as the
reviewer's (deferred question 4). If the reviewer wants a lane-specific run record first,
the cheapest way to produce one is deferred question 3 (a recurring-schedule row for this
repository), after which the row flips to `v1` on evidence.

### A first-of-kind shape, stated

No file under `plugins/autonomy/reference/` names another plugin's slash command today
(`grep -rnoE '/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*' plugins/autonomy/reference/` returns nothing;
the one backticked skill token, `testing:audit` in `routines.md`, is descriptive, not an
instructed invocation). This leaf instructs three. The justification is the catalog's own
"Instruction provenance" section: the instruction content lives in a version-controlled
artifact, and the container settled that the artifact is the leaf. The leaf's normative
sections name capability classes (an instruction-placement delta lane, an enforcement-surface
delta lane, a repository drift audit lane); the concrete slash names appear in the `Fan-out`
section as the instructed, presence-gated invocations. The vendor-name ban on `reference/`
(`scripts/validate-plugin-contracts.mjs`, tokens `github|gitlab|bitbucket|slack|anthropic|claude|openai|copilot|cursor|devin`)
is unaffected: sibling plugin names carry none of those substrings, and the leaf must not
say "Claude Code", "GitHub", or use `${CLAUDE_PLUGIN_ROOT}`.

## What the chain actually looks like (traced, not assumed)

| Hop | What it reads | Consequence for the plan |
|---|---|---|
| Catalog row → leaf | `routines.md` "v1 leaves" list links each leaf by path | Row, class parameter, v1 list, and the count "ten `v1` classes" all change. The count in `docs/adr/0011-*.md` and in CHANGELOG history is historical and stays. |
| Leaf → generated emission | `plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs` reads every `reference/routines/*.md`, extracts the `Prerequisites` H2 section, requires either H3 headings whose text is a backticked identity or a "Single-posture identity:" line with a backticked token, and reads five axis rows from the two-column table: `Access class`, `Isolation floor`, `Connector entitlements`, `Connector entitlement rung`, `Repo needs`. The sixth row every leaf carries, the `executor_class` merge cap, is not parsed (the emission hardcodes `security-binding`) but is part of the shape the leaves share. | The leaf's `Prerequisites` section copies `tech-debt-sweep.md` lines 50–69 exactly: the identity line and the six-row table. Any run or fan-out content lives in its own H2 section. |
| `Repo needs` cell → `needs[]` | A closed regex vocabulary (`NEED_PATTERNS`). Unrecognized phrasing yields no need, silently. No pattern expresses "a sibling plugin is installed" or "a home persisted across runs". | The cell reuses recognized phrases only: `repository source tree`, `documentation corpus`, `tracker binding when filing work items through the work-item tracker seam`. The class's substantive prerequisites (three optional plugins present; a persisted home; a branch identity) are unrepresentable in the emission, so the resolver's `supported` verdict over-reports for this class. The class parameter says so; extending the vocabulary is a deferred question. |
| Generated emission → CI | `scripts/validate-plugins.sh` runs the generator `--check` and `validate-plugin-contracts.mjs`; `resolve-prerequisites.fixtures.test.mjs` grades every identity across seven fixtures. | Regenerate the emission; both suites must stay green with the eleventh leaf, which is the fourteenth identity (the emission holds thirteen today; several classes are multi-posture). On the bare-repo fixture the `tracker` need cannot resolve, so the identity lands outside `supported`/`conditional`, which is what that fixture asserts. |
| Leaf → runtime | Nothing in this repository executes a routine's instructions. `check-signal-envelope.mjs` validates a `signal.routine` claim against a `routines.enabled` entry and the security binding and is fail-closed on an absent entry; the runner is design-only (`reference/runner.md`). | The plan claims the leaf is the instruction artifact an org's handler points at. It does not claim the fan-out runs anywhere this repository ships. |
| Handler → surface | `templates/routine-definitions.md`: any handler enqueues one `temporal` signal for one identity and runs no work; `scheduler_class` is a closed two-value discriminator keyed on the raw-link form, and a vendor-hosted preview scheduler wires as `ci-cron` when it issues an https run permalink. | `ci-cron` alone excludes nothing, and the leaf excludes nothing either. The leaf states the predicate as a fact and names the CI-orchestration job as an illustrative binding; the "no cloud surface" decision is enforced where surfaces are actually bound. |
| Fan-out → `/overengineering:delta` | Accepts `unattended` (mandatory when unwatched). Needs a resolvable branch identity: a branch checkout, or a logical ref the runner supplies that passes normalize-then-validate; on neither, the audit still runs and reports inline but no baseline is compared or captured. Keeps its baseline in the memory-tier home it resolves through a five-rung ladder (never assume the path). `recurring-wiring.md` says a mature surface does not fit one context window and instructs a layer rotation, one or two layers per cycle, with a coverage line in the report. | The leaf instructs `unattended` and a two-layer rotation over the ten-layer vocabulary in its stated order: pair index = (ISO week − 1) mod 5, week read with `date -u +%V`, index 0 = `agent-hooks agent-instructions`, 1 = `repo-hooks vcs-hooks`, 2 = `ci-lanes gate-scripts`, 3 = `satellite-workflows branch-protection`, 4 = `forge-apps external-integrations`. Stateless; a 53-week year repeats one pair across the year boundary, an accepted anomaly the coverage line records. The routine's report carries the lane's coverage line. |
| Fan-out → `/instruction-placement:delta` | On main: with no prior artifact it says so and routes to the full audit rather than running one; the artifact lives in a plugin-data tree keyed by a worktree-root hash. Under #3831: the artifacts move to the memory tier and the first baseline bootstraps from the audit's findings artifact, but a run with no artifact at all still routes out. Either way the lane never establishes its own first artifact. | The leaf carries a bootstrap rule: when the delta lane reports no prior artifact, the run invokes `/instruction-placement:audit` (read-only; its only write is its own findings artifact) so the next cycle has something to compare against, and records the cycle as a bootstrap. This is the lane's own bootstrap, not a fourth lane. |
| Fan-out → `/codebase-health:audit` | No `unattended` token. Unattended blockers, all read from the skill and its `discovery-method.md`: a target ladder that asks the user when config cannot resolve targets and offers to persist inferences; a mandatory scope gate that requires a `[scope]` or dimension filter for large targets; a confirm-with-the-user stop past roughly twenty enumerated files; a checklist copied into the repo's task notes "or kept in-response"; persist offers in the report; a no-auto-invoke rule under `--fix`. It is a full pass, never a delta. | The leaf instructs: invoke without `--fix` and with one dimension flag, index = (ISO week − 1) mod 4, 0 = `--docs-only`, 1 = `--config-only`, 2 = `--code-only`, 3 = `--arch-only`, which satisfies the scope gate. Before invoking, the run reads the audit's tracked config itself and expands that dimension's `primary-sources` globs; where the config resolves no targets for the dimension, or the expanded list exceeds twenty files (the audit's confirm threshold, which an unattended session cannot answer), the run does not invoke the audit and records the lane as not run with the dimension and the file count. Keep the checklist in-response; take no persist offer. The lane is therefore viable unattended only for small dimensions until the audit gains an unattended collapse (deferred question 2, the recommended follow-up). |

## Reuse-or-replace: the owning plugin's recurring-wiring contract

`plugins/overengineering/skills/delta/context/recurring-wiring.md` is the established way of
scheduling one of the three lanes. It offers four shapes, prefers Shape 4 (a recurring item
in the consumer's tracker), and warns that Shape 3 (a CI schedule) is itself an
enforcement-surface item and has the worst ephemerality. This plan does not silently diverge
from it:

- A catalog routine's handler runs no work; it enqueues one `temporal` signal onto a governed
  queue item, which the standing drain dispatches. The durable record is a tracker-held queue
  item, so the routine model has Shape 4's durable-record property with Shape 3's
  surface cost (the scheduled tick is itself an enforcement-surface item). The leaf says so,
  so an adopter reads the two documents as one shape.
- The Shape 3 cost is accepted with its evidence: the leaf requires each cycle's report to
  carry what moved and what was covered, which is the record the overengineering audit will
  later judge the lane on.
- Shape 4 as this repository's own binding of the class (a row in
  `.github/recurring-schedule.json`) is a deferred question, not this lane's scope.

## Phase 1 (the whole of #3819): add the `drift-delta-sweep` class

### Files

| Path | Change |
|---|---|
| `plugins/autonomy/reference/routines/drift-delta-sweep.md` | New leaf. Sections, in order: intro line, `Purpose`, `Trigger and cadence`, `Access scope`, `Output contract`, `Fan-out`, `Derived guardrail row`, `Prerequisites`, `Admission and escalation`, `Precedent` (all H2). |
| `plugins/autonomy/reference/routines.md` | Catalog row under **Code quality / knowledge**, after `doc-freshness-sweep`: `\| drift-delta-sweep \| AGT \| R + WI \| repo \| C1 \| v1 \|`. One class-parameter bullet (exact text below). Add the leaf to the v1 leaves list after `doc-freshness-sweep`. Change "ten `v1` classes" to "eleven `v1` classes". |
| `plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs` | Header comment "ten v1 routine definition leaves" becomes "eleven v1 routine definition leaves". No logic change. |
| `plugins/autonomy/generated/identity-prerequisites.json` | Regenerated by running the generator with no arguments. Never hand-edited. |
| `plugins/autonomy/CHANGELOG.md` | New `## [0.23.0]` section, `### Added`. |
| `plugins/autonomy/.claude-plugin/plugin.json` | `version` 0.22.30 → 0.23.0. Minor, per the in-CHANGELOG precedents `0.17.0` (nine new catalog classes) and `0.19.0` (a new section on every leaf). The ten leaves themselves landed in #600 before the CHANGELOG existed (it starts at 0.7.1), so that precedent is not citable from the file. `0.19.1`, a row amendment with no leaf, was a patch. No repo-wide written bump rule exists. |
| `plugins/autonomy/README.md` | No change. The README describes the v1 subset generically and enumerates no leaves (lines 39–47). The worker states this in the PR body. |

### Leaf content contract

The leaf is org-agnostic and vendor-agnostic: no publisher, fleet repository, organization
environment key, and none of the banned `reference/` substrings above. Every cross-plugin
reference names the plugin (never a marketplace), is presence-gated at the invocation, and
states its fallback in the same sentence, per `docs/conventions/seam-phrasing/README.md`.
The leaf restates what it needs and defers to no path under `docs/conventions/` at run time.
It names no artifact path of any lane.

- **Intro line.** "Normative leaf of the [routine catalog](../routines.md): the
  `drift-delta-sweep` v1 class definition", with the link, in the shape of the other leaves'
  first sentence.
- **Purpose.** The repository's installed drift lanes run only when a human remembers; the
  sweep runs them on a cadence and reports movement.
- **Trigger and cadence.** Slot `schedule`; `temporal` signal through the trigger-dispatch
  adapter; suggested cadence weekly, org-bindable. Then the run predicate, as a fact: the two
  delta lanes compare and capture only when the executing session resolves a branch identity
  (a branch checkout, or a logical ref the runner supplies) and finds its memory-tier home
  persisted across runs; a run without them still reports, compares nothing, and says so.
  Then one illustrative binding, not a fixed requirement: a scheduled job on the
  CI-orchestration home whose runner restores that home and checks out the branch, which
  guided setup records as the `ci-cron` scheduler class. Close with the verbatim clause "No
  vendor scheduling surface is named here; guided setup researches scheduling surfaces
  live." No exclusion of any surface.
- **Access scope.** `repo`. Reads the repository tree; writes through the governed queue and
  tracker only. No merge path. The audit lane runs without `--fix`.
- **Output contract.** One advisory report per run with one section per lane, a coverage
  line (which layers and which dimension this cycle walked), and a "lanes not run" section
  naming each absent or blocked lane and why; work items through the governed queue for
  movement needing authorial judgment. The report is the evidence the class keeps its own
  place on the enforcement surface with.
- **Fan-out.** The instruction content. Three instructed invocations, in this order:
  1. The instruction-placement delta lane: invoke `/instruction-placement:delta` (when the
     `instruction-placement` plugin is installed; absent, record the lane as not run). It
     owns what moved in the instruction-placement findings since its last run. Bootstrap
     rule: when it reports no prior artifact, invoke `/instruction-placement:audit`
     (read-only; its only write is its own findings artifact) so the next cycle has a
     baseline, and record the cycle as a bootstrap.
  2. The enforcement-surface delta lane: invoke `/overengineering:delta` with `unattended`
     and two layers (when the `overengineering` plugin is installed; absent, record the lane
     as not run). It owns what moved in the enforcement surface since its last run. The two
     layers rotate through the ten-layer vocabulary in its stated order: pair index =
     (ISO week − 1) mod 5 with the week read by `date -u +%V`; 0 = `agent-hooks
     agent-instructions`, 1 = `repo-hooks vcs-hooks`, 2 = `ci-lanes gate-scripts`,
     3 = `satellite-workflows branch-protection`, 4 = `forge-apps external-integrations`.
     Stateless; a 53-week year repeats one pair, which the coverage line records. The report
     carries the lane's coverage line.
  3. The repository drift audit lane: invoke `/codebase-health:audit` without `--fix` and
     with one dimension flag (when the `codebase-health` plugin is installed; absent, record
     the lane as not run). It owns the full drift pass over docs, config, code, and
     architecture claims and is a full pass, never a delta. Dimension index = (ISO week − 1)
     mod 4; 0 = `--docs-only`, 1 = `--config-only`, 2 = `--code-only`, 3 = `--arch-only`.
     Before invoking, read the audit's tracked config and expand that dimension's
     `primary-sources` globs; where the config resolves no targets for the dimension, or the
     expanded list exceeds twenty files (the audit's confirm threshold, which an unattended
     session cannot answer), do not invoke the audit and record the lane as not run with the
     dimension and the file count. Keep its checklist in-response; take no persist offer.
- **Derived guardrail row.** `AGT` judgment; `R + WI` output → `C1`; no structural or
  configuration change (no `C4`); repo access, no external content (no `C5`); `L2` floor.
- **Prerequisites.** Copy `tech-debt-sweep.md` lines 50–69 and substitute: the line
  "Single-posture identity:" followed by the backticked token `drift-delta-sweep`; the
  six-row axis table with `Access class` `repo`, `Isolation floor` `L2` cited from the matrix
  `C1` row and the unattended floor, `Connector entitlements` none, `Connector entitlement
  rung` n/a, the `executor_class` merge cap row verbatim with "Merge policy for this identity
  is n/a (`C1`)", and `Repo needs` "repository source tree; documentation corpus; tracker
  binding when filing work items through the work-item tracker seam. The class's substantive
  prerequisites, three optional sibling plugins present and a run that resolves a branch
  identity and persists its memory-tier home, are not representable in the generated
  emission" (one line; recognized phrases first; the trailing sentence is self-contained,
  matches no pattern, and adds no need).
- **Admission and escalation.** Imported by citation, as every leaf does.
- **Precedent.** The proven manual pattern is the operator-run cadence pass over the
  repository's drift lanes, documented by the enforcement-surface lane's own recurring-wiring
  guidance and by report-only drift-watch rows in a consumer's recurring schedule.

### Class parameter (exact text, house format)

```markdown
- **`drift-delta-sweep` and `doc-freshness-sweep` are distinct classes.** `doc-freshness-sweep`
  judges whether prose still describes its subject; `drift-delta-sweep` runs the repository's
  installed drift lanes and reports their movement. Its repository-drift-audit lane is a full pass
  whose documentation dimension overlaps `doc-freshness-sweep`; an org enabling both accepts that
  one dimension is covered twice. The class's substantive prerequisites, three optional sibling
  plugins present and a run that resolves a branch identity and persists its memory-tier home
  across cycles, are not representable in the generated prerequisite emission, so a `supported`
  verdict for this identity over-reports; the leaf states the predicate and the routine binding
  owns satisfying it.
```

### Sanity Checks

Run from the repository root. Each of the thirty executable lines was run in isolation on
the unmodified tree on 2026-09-06. Seven pass there and are not presence checks: the
generator `--check`, the two `if grep` absence checks (vacuous while the leaf is absent;
`test -f` aborts the block first), the two test suites, `validate-plugin-contracts.mjs`, and
`markdownlint` (which skips a missing path). The other twenty-three, including `lychee`,
fail on the unmodified tree. All must pass after the phase.

```sh
set -e
LEAF=plugins/autonomy/reference/routines/drift-delta-sweep.md
CAT=plugins/autonomy/reference/routines.md
GEN=plugins/autonomy/generated/identity-prerequisites.json
test -f "$LEAF"
grep -q '^| drift-delta-sweep | AGT | R + WI | repo | C1 | v1 |$' "$CAT"
grep -q 'routines/drift-delta-sweep.md' "$CAT"
grep -q 'eleven `v1` classes' "$CAT"
grep -q 'eleven v1' plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs
node plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs --check
grep -q '"identity": "drift-delta-sweep"' "$GEN"
grep -q 'Single-posture identity: `drift-delta-sweep`' "$LEAF"
grep -q '`executor_class` merge cap' "$LEAF"
grep -q '^## Fan-out' "$LEAF"
grep -q '/instruction-placement:delta' "$LEAF"
grep -q '/instruction-placement:audit' "$LEAF"
grep -q '/overengineering:delta' "$LEAF"
grep -q '/codebase-health:audit' "$LEAF"
grep -q 'without `--fix`' "$LEAF"
grep -q 'ci-cron' "$LEAF"
grep -q 'No vendor scheduling surface is named here' "$LEAF"
grep -qi 'is installed' "$LEAF"
grep -qi 'persisted across' "$LEAF"
grep -qi 'branch identity' "$LEAF"
grep -qi 'coverage line' "$LEAF"
if grep -qiE 'github|gitlab|bitbucket|slack|anthropic|claude|openai|copilot|cursor|devin|melodic' "$LEAF"; then echo "banned token in leaf"; exit 1; fi
if grep -qE 'CLAUDE_PLUGIN_DATA|\.work/|memory_dir|<branch-slug>|state-key|baselines/|spine-baseline' "$LEAF"; then echo "leaf names an artifact path"; exit 1; fi
grep -q '"version": "0.23.0"' plugins/autonomy/.claude-plugin/plugin.json
grep -q '^## \[0.23.0\]' plugins/autonomy/CHANGELOG.md
bash plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.test.sh
node plugins/autonomy/skills/setup/scripts/resolve-prerequisites.fixtures.test.mjs
node scripts/validate-plugin-contracts.mjs
lychee --offline --config lychee.toml "$LEAF" "$CAT"
npx markdownlint-cli2 "$LEAF" "$CAT" plugins/autonomy/CHANGELOG.md
```

Absence checks use `if grep -q ...; then exit 1; fi`. A bare `! grep -q` does not abort
under `set -e` (bash exempts a `!`-prefixed command from errexit), and `grep -c` prints `0`
but exits 1 on no match. No brace expansion inside a quoted path. `lychee` is installed on
the planning machine (0.24.2); where it is absent the worker states so and relies on the CI
offline link lane. `npx markdownlint-cli2` needs the repo's `node_modules`.

## Test strategy

- `generate-identity-prerequisites.test.sh` (auto-discovers leaves; its leaf-to-emission
  parity case picks the new leaf up with no manifest edit).
- `resolve-prerequisites.fixtures.test.mjs` (grades every v1 identity across seven fixtures;
  the new identity must land outside `supported`/`conditional` on the bare-repo fixture).
- `scripts/validate-plugins.sh` (generator `--check`, `validate-plugin-contracts.mjs` with
  the fleet-token and vendor-token bans on `plugins/autonomy/`).
- `lychee --offline` on the leaf and the catalog (`lychee.toml` sets
  `include_fragments = "full"`, so every relative anchor the leaf copies from
  `tech-debt-sweep.md` must resolve).
- `npx markdownlint-cli2` on every changed markdown file.
- The `typos` gate splits hyphenated tokens into words; `drift-delta-sweep` splits into
  three English words and needs no directive.
- No SKILL.md changes, so `/skill-quality:check` has nothing to check. #3819's criterion is
  amended in the issue body (see "Issue amendments").

## Blast radius

- This PR's diff: `autonomy` plugin only. One new leaf, one catalog hub edit, one generated
  file, one comment, changelog, version. No skill body changes in this PR's diff (#3828 edits
  a codebase-health skill body separately; that is #3810's slice).
- No change to what the three fanned-out skills detect.
- No org binding, workflow, or schedule is created. The new identity is unclassified and
  fail-closed until an org binds it.
- This repository's own `.github/recurring-schedule.json` is untouched.

## Execution shape

Per-item PRs (container). One slice, one worker, one PR. No parallelism inside the phase:
the generated file depends on the leaf, and the catalog count depends on the leaf existing.
Order inside the PR: leaf → catalog → generator comment → regenerate → changelog + version.

## Alternatives considered

| Alternative | Why not | Switch condition |
|---|---|---|
| Extend `doc-freshness-sweep` (advisory posture) | Changes a ratified identity's substance; class purpose mismatch. | A reviewer ruling that a new v1 row is not earned (see "Why `v1`"). |
| Add a third posture `doc-freshness-sweep/drift-delta` | Cleaner than extending advisory, but still misfiles two non-doc lanes under a doc-freshness class. | Same as above; this is the fallback shape. |
| File the row as `join: proven recurring manual pattern` | Ships no leaf, so #3819's leaf criteria cannot be met; the slice would go back to decompose. | The reviewer ruling above. |
| Bind the class for this repository via `.github/recurring-schedule.json` (recurring-wiring Shape 4) | A consumer-side binding, not the shipped catalog; out of the container's scope. | Deferred question 3. |
| Extend the generator's `NEED_PATTERNS` with plugin-presence and persisted-home needs | Widens blast radius into the resolver and its probes; #3819 is a catalog change. | Deferred question 1. |

## Risks

- **A worker writes the `Prerequisites` section in a shape the generator does not parse, or
  drops the merge-cap row.** Mitigated by the copy-source line range, the `--check` plus
  presence grep, and the merge-cap grep.
- **A worker names an artifact path or a banned substring in the leaf.** Mitigated by the
  two absence checks and `validate-plugin-contracts.mjs`.
- **A worker registers a surface or writes a workflow.** The issue body says no surface,
  binding, or workflow is created.
- **#3831 changes the delta skill's argument surface or artifact home.** The leaf names the
  skill by slash name, passes no arguments, and names no path.

## Deferred questions

1. Should `generate-identity-prerequisites.mjs` gain needs for "sibling plugin installed"
   and "memory-tier home persisted across runs" so the resolver can probe this class's real
   prerequisites instead of over-reporting `supported`?
2. Should `/codebase-health:audit` gain an `unattended` token (the collapse
   `/overengineering:delta` already has) so a scheduled run never hits its target-ask and
   twenty-file confirm stops? That is a codebase-health change outside this container's
   "discoverability and persistence only" scope.
3. Should this repository bind the new class for itself (a `.github/recurring-schedule.json`
   row per recurring-wiring Shape 4, or an autonomy binding once the runner ships)?
4. Reviewer ruling: `v1` on the class-level pattern (the plan's proposal), or
   `join: proven recurring manual pattern` until a lane-specific run record exists (which
   ships no leaf and makes #3819's leaf criteria and #3803's criterion 2 unsatisfiable as
   written, re-slicing #3819)? This must be settled before #3819 is dispatched.

## Contract-slice lifecycle for this plan

`scripts/check-contract-slice-prune.sh --check-diff` red-lines any PR leaving a path under
`docs/topics/` (`scripts/contract-slice-baseline.txt` is empty; exemptions read from the base
revision). No PR is opened for this plan branch: the plan's durable homes are the #3819 issue
body (every worker-facing contract above) and the #3809 close comment, which names the
pre-prune commit SHA on `plan/3809-drift-delta-routine`. The #3819 implementation PR carries
no path under `docs/topics/`.

## Issue amendments

- **#3819**: the extend-versus-sibling ruling written into the body (title, summary,
  desired behavior); the Files table, exact catalog row and placement, exact class-parameter
  bullet, intra-PR ordering, and the no-`docs/topics/` rule; criterion 3 reshaped (the leaf
  states the run predicate as a fact and gives the CI-orchestration job as an illustrative
  `ci-cron` binding; nothing registers a surface); criterion 4 marked not applicable (no
  SKILL.md touched); criterion 7 names `routines.md`'s v1 leaves list and records that the
  README enumerates no leaves; new criteria for the six-row `Prerequisites` shape, the
  regenerated emission with `--check` green, the bootstrap rule, the two rotations with their
  index tables, the audit's pre-check, the no-path and no-banned-token rules, and the two
  test suites; the full leaf content contract and Sanity Checks pasted in; the reviewer
  ruling on `v1` recorded as a dispatch gate.
- **#3803 Brief**: dated note under criterion 2 recording the sibling-row ruling, how "on
  the ci-cron surface" is satisfied by a shipped contract (run predicate as fact; the CI job
  as an illustrative `ci-cron` binding; surface binding stays org-owned and nothing is
  registered), that a `join:` ruling would leave criterion 2 unsatisfiable as written, and
  that the reuse-or-replace constraint is met by citing the overengineering recurring-wiring
  contract. Criteria 1, 3, 4 (#3810/#3811) untouched.

## Verification record

Revision 2 was verified by a second fresh-context reviewer, which confirmed the revision-1
fixes for the Prerequisites shape, the bootstrap rule on both sides of PR #3831, the
absence-check form, the class-parameter format, the added test gates, the contract-slice
lifecycle, and the `Repo needs` vocabulary (exactly `documentation_corpus`, `source_tree`,
`tracker`), and returned one CRITICAL and six MAJOR findings, each checked and applied:
the `v1` evidence restated as class-level pattern with no lane-specific run record and the
ruling made a dispatch gate; the `ci-cron` text reduced to a fact plus an illustrative
binding with no exclusion, and "every leaf carries the clause" corrected to five of ten;
the audit lane given a deterministic pre-invocation check instead of a "narrow" instruction;
the no-path grep widened to the homes the lanes actually use; "eleventh identity" corrected
to eleventh leaf, fourteenth identity; the version precedent corrected to `0.17.0` and
`0.19.0` with #600 noted as pre-CHANGELOG; the passing-line count corrected to seven; both
rotations given explicit index tables and a week source; the intro line given its link; the
`Repo needs` trailing sentence made self-contained; the Shape 4 reconciliation qualified;
the status table refreshed for PR #3828's merge.

Revision 1 was verified by a fresh-context reviewer that returned five CRITICAL and eleven
MAJOR findings; each was checked against the files before acting. Changes made: `v1`
justification rewritten against the `[0.19.1]` ruling and flagged as a reviewer call; the
first-of-kind slash-invocation shape stated; `ci-cron` moved from a binding class parameter
to a run predicate plus reference binding, keeping the leaves' verbatim hosting clause; the
instruction-placement chain row corrected (plugin-data tree on main, memory tier under
PR #3831, route-out in both) and a bootstrap rule added; the overengineering row corrected
(logical-ref hatch; audit still runs when detached; home resolved by ladder, no path) and a
layer rotation added; the audit's blockers enumerated and answered with a dimension rotation;
the six-row `Prerequisites` shape named; `! grep -q` replaced with `if ... exit 1`; the
`.work/` presence check inverted to an absence check; `validate-plugin-contracts.mjs`, the
resolver fixture suite, and `lychee --offline` added; the version precedent corrected to
`0.6.0` and `0.17.0`; the spell-gate risk removed; the class parameter given in house format;
the blast-radius sentence scoped to this PR's diff; the ADR count reference noted as
historical; the recurring-wiring contract cited and reconciled; the contract-slice lifecycle
stated; the plugin-presence gap recorded as a class parameter and a deferred question.
