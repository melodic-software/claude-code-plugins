# Plan: drift-delta routine on the ci-cron surface

Container: #3803 (Epic: drift discoverability). Planning slice: #3809. Remaining
implementation slice: #3819. Branch: `plan/3809-drift-delta-routine`.

## Status of the container's slices

| Slice | State | This plan's posture |
|---|---|---|
| #3810 codebase-health audit Boundary router | In flight: PR #3828 (open). PR #3829 was closed as a duplicate of #3828. | Not planned here. Read for consistency only. |
| #3811 instruction-placement delta baseline slot | In flight: PR #3831 (open, review threads open, currently CONFLICTING against main). PR #3833 was closed as a duplicate of #3831. | Not planned here. Read for consistency only. |
| #3819 routine fan-out | Blocked by #3809. The only remaining implementation slice. | Planned below, one phase. |

Nothing in this plan edits a file either in-flight PR touches. The one touch point is
that the new routine leaf names `/instruction-placement:delta` by slash name only, never
by its baseline path, so #3831's relocation of that baseline cannot contradict the leaf.

## Goal

Ship a standing routine class in the `autonomy` plugin's routine catalog whose tracked
definition leaf names the instruction-placement delta, the overengineering delta, and the
codebase-health audit skills as its fan-out, with the leaf as the instruction artifact an
org's `ci-cron` handler points at, and with the run prerequisites those three skills
actually have stated where an adopting org will read them.

## Settled decisions (not reopened)

- The scheduling surface class is `ci-cron`, the closed `scheduler_class` discriminator the
  routine wiring template already defines (`plugins/autonomy/skills/setup/templates/routine-definitions.md`).
  No vendor-hosted or cloud scheduling surface.
- Instruction content lives in the tracked leaf under `plugins/autonomy/reference/routines/`.
  The catalog row points at the leaf. No stored prompt carries instructions
  (`routines.md`, "Instruction provenance").

## The extend-versus-sibling decision: sibling row `drift-delta-sweep`

The planning slice asked which of two shapes to build. The answer is a **new v1 class row,
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
   clutter) are not doc freshness. Folding them in would make the leaf's Purpose, Precedent,
   and derived-row reasoning describe a different class.
3. **Catalog precedent.** Two classes with overlapping cells and a class parameter stating
   the distinction is an established shape (`clone-trend-gate` vs `coverage-mutation-watch`).

The overlap is real and is stated, not hidden: `/codebase-health:audit`'s documentation
dimension covers ground `doc-freshness-sweep` also covers. A class parameter in
`routines.md` records it, and says an org enabling both accepts the double coverage of that
one dimension.

Switch condition: if a reviewer produces a rule in `routines.md` or `trigger-dispatch.md`
that forbids a new v1 row without a join trigger having been recorded first, fall back to
extending `doc-freshness-sweep` with a third posture `doc-freshness-sweep/drift-delta`
(a new posture-qualified identity is also unbound until ratified, which preserves reason 1).
No such rule was found: `v1` requires a "proven manual pattern", and the three skills exist
and are run by hand today (this repository's own `.github/recurring-schedule.json` carries a
report-only `stale-doc-drift-watch` row as the consumer-side precedent).

## What the chain actually looks like (traced, not assumed)

Each hop was read before the phase below was written.

| Hop | What it reads | Consequence for the plan |
|---|---|---|
| Catalog row → leaf | `routines.md` "v1 leaves" list links each leaf by path | Row, class parameter, v1 list, and the "ten `v1` classes" count all change. |
| Leaf → generated emission | `plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs` reads every `reference/routines/*.md`, extracts the `Prerequisites` H2 section, requires either H3 headings whose text is a backticked identity or a "Single-posture identity:" line with a backticked token, and a two-column axis table with exactly the rows `Access class`, `Isolation floor`, `Connector entitlements`, `Connector entitlement rung`, `Repo needs`. | The leaf's `Prerequisites` section must match the `tech-debt-sweep.md` shape exactly. Any run or fan-out content lives in its own H2 section. |
| `Repo needs` cell → `needs[]` | A closed regex vocabulary (`NEED_PATTERNS`). Unrecognized phrasing yields no need, silently. | The cell reuses recognized phrases only: `repository source tree`, `documentation corpus`, `tracker binding when filing work items through the work-item tracker seam`. The persisted-baseline prerequisite cannot be encoded; it goes in prose and in Deferred questions. |
| Generated emission → CI | `scripts/validate-plugins.sh` runs the generator with `--check`. | The worker regenerates `generated/identity-prerequisites.json` and the check must pass with the new identity present. |
| Leaf → runtime | Nothing in this repository executes `signal.routine`. `grep -rn "signal.routine" plugins/work-items` returns nothing; the runner is design-only (`plugins/autonomy/reference/runner.md`). | The plan claims the leaf is the instruction artifact an org's handler points at. It does not claim the fan-out runs anywhere this repository ships. |
| Handler → surface | `templates/routine-definitions.md`: a `ci-cron` handler enqueues one `temporal` signal for one identity and runs no work; `scheduler_class` is a closed two-value discriminator. | The leaf may name `ci-cron` as the class's conforming scheduler class because the token is contract-owned, not a vendor name. Surface *binding* stays org-owned in the repo-local `routines` section and the security binding. |
| Fan-out → the three skills | `/overengineering:delta` accepts `unattended`, refuses a detached checkout (`git symbolic-ref` fails, no baseline is written), and keeps its baseline in never-committed `.work/overengineering/<branch-slug>/`. `/instruction-placement:delta` routes out on a missing prior artifact; its baseline is also memory-tier (unchanged by #3831, which only moves it into the `baselines/` slot of the same tier). `/codebase-health:audit` has no `unattended` token, asks the user when it cannot infer targets, and confirms before dispatching past ~20 files. | The leaf states two run prerequisites (branch checkout, not detached; a memory-tier home persisted across runs by the runner) and the audit's two interactive stops as an unattended limitation. These are what make `ci-cron` the right class: a CI runner can restore a cache and check out a branch; a clone-per-run cloud surface can do neither. |

## Phase 1 (the whole of #3819): add the `drift-delta-sweep` class

### Files

| Path | Change |
|---|---|
| `plugins/autonomy/reference/routines/drift-delta-sweep.md` | New leaf. Sections, in order: intro line, `## Purpose`, `## Trigger and cadence`, `## Access scope`, `## Output contract`, `## Fan-out` (the instruction content), `## Derived guardrail row`, `## Prerequisites`, `## Admission and escalation`, `## Precedent`. |
| `plugins/autonomy/reference/routines.md` | Catalog row under **Code quality / knowledge**: `\| drift-delta-sweep \| AGT \| R + WI \| repo \| C1 \| v1 \|`. One class-parameter bullet. Add the leaf to the v1 leaves list. Change "ten `v1` classes" to "eleven `v1` classes". |
| `plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.mjs` | Header comment "ten v1 routine definition leaves" becomes "eleven". No logic change. |
| `plugins/autonomy/generated/identity-prerequisites.json` | Regenerated by running the generator with no arguments. Never hand-edited. |
| `plugins/autonomy/CHANGELOG.md` | New `## [0.23.0]` section, `### Added`. |
| `plugins/autonomy/.claude-plugin/plugin.json` | `version` 0.22.30 → 0.23.0 (minor: a new catalog class; precedent 0.19.0 and 0.20.0 for leaf-tier additions). |
| `plugins/autonomy/README.md` | No change. The README describes the v1 subset generically and enumerates no leaves (lines 39–47). The worker states this in the PR body. |

### Leaf content contract

The leaf is org-agnostic: no publisher, fleet repository, or organization-scoped
environment key. Every cross-plugin reference names the plugin (never a marketplace), is
presence-gated at the invocation, and states its fallback in the same sentence, per
`docs/conventions/seam-phrasing/README.md`. The leaf restates what it needs and defers to no
path under `docs/conventions/` at run time.

- **Purpose.** The three drift lanes run only when a human remembers; the sweep runs them on
  a cadence and reports movement.
- **Trigger and cadence.** Slot `schedule`; `temporal` signal through the trigger-dispatch
  adapter; suggested cadence weekly, org-bindable. The conforming scheduler class for this
  identity is `ci-cron` (a surface issuing an https run permalink), for the reason stated
  under the chain table: the fan-out's two delta lanes need a branch checkout and a
  persisted memory-tier home across runs, which a CI runner provides and a clone-per-run
  hosted surface does not. A vendor-hosted or cloud scheduling surface is excluded for this
  class, not deferred. Surface binding itself stays org-owned.
- **Access scope.** `repo`. Reads the repository tree; writes through the governed queue and
  tracker only. No merge path. `/codebase-health:audit` is invoked without `--fix`.
- **Output contract.** One advisory report per run, three lane sections plus a
  "lanes not run" section; work items through the governed queue for movement needing
  authorial judgment.
- **Fan-out.** Three instructed invocations, each gated:
  - `/instruction-placement:delta` (when the `instruction-placement` plugin is installed;
    absent: record the lane as not run in the report). Owns what moved in the
    instruction-placement findings since its last run.
  - `/overengineering:delta` with `unattended` (when the `overengineering` plugin is
    installed; absent: record the lane as not run). Owns what moved in the enforcement
    surface since its last run.
  - `/codebase-health:audit` without `--fix` (when the `codebase-health` plugin is
    installed; absent: record the lane as not run). Owns the full drift pass over docs,
    config, code, and architecture claims. It is a full pass, not a delta.
  - Run prerequisites, stated in the leaf: the run checks out a branch, never a detached
    HEAD (the delta lanes refuse to write a baseline without a branch identity); the runner
    persists the memory-tier home (`.work/<plugin>/<branch-slug>/`) across runs, else every
    run is a bootstrap that reports no delta. Unattended limitation: `/codebase-health:audit`
    asks for targets when its config cannot resolve them and confirms before dispatching past
    roughly twenty files; the leaf instructs the run to invoke it only where its config
    resolves targets and to record the lane as not run otherwise.
- **Derived guardrail row.** `AGT` judgment; `R + WI` output → `C1`; no structural or
  configuration change (no `C4`); repo access, no external content (no `C5`); `L2` floor.
- **Prerequisites.** The line "Single-posture identity:" followed by the backticked token
  `drift-delta-sweep`, plus the five-row axis table in the `tech-debt-sweep.md` shape. Repo needs (recognized phrases only): "repository
  source tree; documentation corpus; tracker binding when filing work items through the
  work-item tracker seam".
- **Admission and escalation.** Imported by citation, as every leaf does.
- **Precedent.** The proven manual pattern is the operator-run delta pass.

### Class parameter (in `routines.md`)

One bullet: `drift-delta-sweep` and `doc-freshness-sweep` are distinct classes.
`doc-freshness-sweep` judges whether prose still describes its subject; `drift-delta-sweep`
runs the repository's installed drift detectors and reports their movement. Its
`/codebase-health:audit` lane is a full pass whose documentation dimension overlaps
`doc-freshness-sweep`; an org enabling both accepts that one dimension is covered twice.
The two delta lanes require a persisted memory-tier home and a branch checkout, which is
why the class's conforming scheduler class is `ci-cron`.

### Sanity Checks

Each was run on the unmodified tree on 2026-09-06 and **failed** there (the generator
`--check` alone passes on the unmodified tree, which is why it is paired with a presence
grep). Run from the repository root. All must pass after the phase.

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
grep -q '^## Fan-out' "$LEAF"
grep -q '/instruction-placement:delta' "$LEAF"
grep -q '/overengineering:delta' "$LEAF"
grep -q '/codebase-health:audit' "$LEAF"
grep -q 'without `--fix`' "$LEAF"
grep -q 'ci-cron' "$LEAF"
grep -qi 'is installed' "$LEAF"
grep -qi 'detached' "$LEAF"
grep -q '\.work/' "$LEAF"
! grep -qi 'melodic' "$LEAF"
grep -q '"version": "0.23.0"' plugins/autonomy/.claude-plugin/plugin.json
grep -q '^## \[0.23.0\]' plugins/autonomy/CHANGELOG.md
bash plugins/autonomy/skills/setup/scripts/generate-identity-prerequisites.test.sh
npx markdownlint-cli2 "$LEAF" "$CAT" plugins/autonomy/CHANGELOG.md
```

Absence checks use `! grep -q`, never `grep -c` (which prints `0` and exits 1 on no
match, failing under `set -e` exactly when the asserted absence holds). No brace
expansion inside a quoted path.

## Test strategy

- The generator's own test (`generate-identity-prerequisites.test.sh` with its manifest)
  covers clean `--check`, drift, and leaf-to-emission parity; it runs unchanged and must
  stay green with eleven leaves.
- `scripts/validate-plugins.sh` runs the generator `--check` in CI; a stale emission fails
  the PR.
- `npx markdownlint-cli2` on every changed markdown file.
- The CI spell gate (`typos`) splits coined hyphenated compounds; the plugin's `AGENTS.md`
  says to keep multi-word identifiers backticked. `drift-delta-sweep` is always backticked
  or in a table cell in prose.
- No SKILL.md changes, so `/skill-quality:check` has nothing to check; #3819's criterion is
  amended to say so.

## Blast radius

- `autonomy` plugin only. One new leaf, one catalog hub edit, one generated file, one
  comment, changelog, version.
- No skill body changes in any plugin. No change to what the three fanned-out skills detect.
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
| Extend `doc-freshness-sweep` (advisory posture) | Changes a ratified identity's substance; class purpose mismatch. | A rule forbidding a new v1 row without a prior join trigger. |
| Add a third posture `doc-freshness-sweep/drift-delta` | Cleaner than extending advisory, but still misfiles two non-doc lanes under a doc-freshness class. | Same as above; this is the fallback shape. |
| Add a row to this repository's `.github/recurring-schedule.json` | That is the work-items recurring-schedule seam, a consumer-side binding for this repository, not the shipped catalog. Out of the container's scope (the catalog is what ships). | A follow-up item to bind the new class for this repository. |
| Extend the generator's `NEED_PATTERNS` with a `persisted_baseline_home` need | Widens blast radius into the resolver and its probes; #3819 is a catalog change. | Deferred question below. |

## Risks

- **A worker writes the `## Prerequisites` section in a shape the generator does not parse.**
  Mitigated by the Sanity Checks (`--check` plus presence grep) and by the issue body naming
  `tech-debt-sweep.md` as the shape to copy.
- **A worker registers a surface or writes a workflow.** The issue body says no surface,
  binding, or workflow is created.
- **Spell gate on the new token.** Backticked everywhere in prose.
- **#3831 changes the delta skill's argument surface.** The leaf names the skill by slash
  name and passes no arguments to it, so no contradiction is possible.

## Deferred questions

1. Should `generate-identity-prerequisites.mjs` gain a `persisted_baseline_home`
   (`harness-context`) need so the resolver can probe the prerequisite the two delta lanes
   have, instead of the leaf stating it in prose only?
2. Should `/codebase-health:audit` gain an `unattended` token (the collapse
   `/overengineering:delta` already has) so a scheduled run never hits its two interactive
   stops? That is a codebase-health change, outside this container's "discoverability and
   persistence only" scope.
3. Should this repository bind the new class for itself (a `.github/recurring-schedule.json`
   row, or an autonomy binding once the runner ships)?
