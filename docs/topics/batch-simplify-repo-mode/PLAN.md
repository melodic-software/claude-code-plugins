# batch-simplify repo-wide mode

## Brief

### TLDR

Add a third scope mode, `repo`, to `/code-tidying:batch-simplify`. The existing skill sweeps
*recently changed* files in two scope modes (a time window, default `48h`, and `branch`); `repo`
sweeps every code file in the repository instead. Phases 2–8 of the existing workflow are
scope-agnostic and are inherited unchanged; the delta is one row in the detection heuristic
(`SKILL.md:41`), a whole-tree Phase 1 discovery command, and repo-scale machinery in a new
progressive-disclosure spoke `context/repo-mode.md`.

The capability is not speculative: a repository-wide pass was executed by hand and merged as
PR #2842 (`aab29b06`). This work productizes it while correcting the three things that run did
badly — a single unreviewable pull request, an inventory stored where it could not survive, and a
version bump phase that only works in this repository.

### Goal

`/code-tidying:batch-simplify repo` runs a behavior-preserving simplification sweep over every code
file in the repository, delivered as a series of independently mergeable pull requests, with each
group's changes checked by a fresh-context verifier that tries to refute "behavior preserved", and
with every deferred item persisted rather than lost.

### Constraints

**Doctrine this repository already publishes**

1. **Never fan out the whole repo unprompted** (`plugins/codebase-health/skills/audit/SKILL.md:143-146`).
   Repo mode is explicit-entry only, with a mandatory confirmation gate.
2. **No upper bound on deferred issues per run** (`plugins/code-tidying/skills/tidy/reference/scope-budget.md:121-123`);
   high volume is a diagnostic about scope — "split the lane, don't raise the cap" (`:22`). A numeric
   filing cap would ship two contradictory volume rules inside one plugin.
3. **A dispatch site degrades to the generic fresh-context subagent, never to a command that may not
   resolve** (`docs/PLUGIN-PHILOSOPHY.md:709-711`); the named-agent bar at `:718-721` blocks minting
   an in-marketplace simplifier agent from a single dispatch site.
4. **"Skip silently" is not a fallback** (`docs/conventions/seam-phrasing/README.md`). Every
   presence gate states what it skipped and why.
5. **Runtime behavior must not depend on an undocumented consumer layout**
   (`docs/PLUGIN-PHILOSOPHY.md:8-16`). `code-tidying` carries **zero** `.work/` references — unlike
   122 files in other plugins — and phrases its notes location as consumer-resolved with an inline
   fallback (`batch-simplify/SKILL.md:21`). Repo mode preserves that.
6. **Review-size budget**: the plugin's own headline is ≤200 LOC / ≤8 files target, ≤400 / ≤15 hard
   cap, on the SmartBear/Cisco finding that reviews above 400 LOC are "largely ineffective".

**Mechanical constraints, verified this session**

1. **`scripts/check-stale-base-overlap.sh` is a required CI check** (`.github/workflows/ci.yml:1363`)
   that fails a PR whose merge base is behind the target tip on overlapping paths. A repo-wide PR
   overlaps everything; #2842 paid this as 48 merge conflicts.
2. **Harness limits** (`https://code.claude.com/docs/en/sub-agents.md`, fetched 2026-08-18): 20
   concurrently-running subagents, after which the Agent tool fails with `Concurrent subagent limit
   reached` and the error says not to retry; spawn depth defaults to three layers, and at the depth
   limit the Agent tool is withheld from every non-fork subagent. Resuming an already-finished
   subagent takes a fresh slot **without** checking the limit.
3. **`/simplify` accepts a target** (`https://code.claude.com/docs/en/commands.md:134` — "Pass a path
   or PR reference to review a specific target") and fans out four review agents of its own; at the
   spawn-depth limit it **silently** degrades to a single-pass inline variant.
4. **`scripts/affected-tests.sh` is shell-only.** Sampled Python files under `plugins/knowledge`
    (225 source files) return `UNMAPPED`. There is no per-wave test selector for Python, JS, or
    PowerShell.
5. **`scripts/check-changelog-parity.sh` is referenced from zero plugin files** and exits 2 when
    `plugins/*/.claude-plugin/` is absent. A consumer installing `code-tidying` never receives it.
6. **Portability CI lanes fire on this edit**: `check-skill-portability.sh`
    (`ci.yml:1286-1289`) and `check-shell-portability.sh` (`ci.yml:1313-1317`), the latter scanning
    skill markdown for GNU-only constructs. `code-tidying` is not in
    `scripts/shell-portability-skill-md-baseline.txt`, so any new shell snippet is gated fresh.
7. **Repo scale**: 2914 tracked files; 1023 tracked source files (546 `.sh`, 238 `.js`, 107 `.ps1`,
    84 `.py`, 25 `.mjs`, 20 `.ts`, 2 `.cs`, 1 `.psm1`) plus 645 `.json`/`.toml`; 1154 tracked `.md`
    of which 750 survive the exclusions; 245 `*.test.sh` suites; 38 CI jobs.

### Acceptance criteria

**Entry and scope**

- [ ] `repo` is a third value on the existing scope-shaped argument surface; the detection heuristic
      (`SKILL.md:41`) gains one row. It is NOT a new skill and NOT an action verb.
- [ ] Repo mode is entered only by an explicit `repo` argument, or by the user accepting an offer
      made when a normal scan finds zero files. It never auto-escalates.
- [ ] The existing trigger phrase "simplify everything" remains mapped to the `48h` default.
- [ ] **Two parser defects are fixed**: `docs` is currently stripped before mode parsing
      (`SKILL.md:55`), so a path argument can never mean the `docs/` directory; and any argument
      containing the substring "branch" misroutes to branch mode (`SKILL.md:41`).
- [ ] `repo <path>` is **not** implemented in v1.
- [ ] File universe is `git ls-files --cached --others --exclude-standard`, then the existing Phase 2
      filters. The command uses no GNU-only constructs (constraint 12).
- [ ] The run **refuses to start on a dirty working tree**, so per-group commits cannot capture the
      user's uncommitted work.
- [ ] `.github/standards/**` is added to the exclusion list as a read-only deferred class (those
      files are standards-`managed`; local edits are silently lost on sync, per `AGENTS.md:3-10`).

**Grouping and ordering**

- [ ] Deterministic base pass (enumerate, filter, group by directory/ecosystem), then an agent
      refinement pass that merges undersized groups, splits groups over the existing 25-file
      threshold (`SKILL.md:191`), and identifies canonical/synced clusters.
- [ ] A synced copy is **removed from its plugin's group** and edited only via its source plus
      `scripts/sync-*.sh` regeneration. #2842 lost its `_lib` bucket to exactly this hazard.
- [ ] Ordering is by dependency constraint only — shared/canonical libraries first. **No churn
      ranking**: the primary evidence records that change-frequency applied alone "produced excessive
      false positives", and size-weighting amplifies rather than corrects that.

**Execution**

- [ ] Groups are simplified by an agent spawned with an inline prompt and an explicit absolute-path
      file list (`pr-review-toolkit:code-simplifier` when installed, else `general-purpose`). Repo
      mode does **not** invoke the bundled `/simplify`. The stated reason is the silent depth-limit
      degradation and slot arithmetic (constraints 8–9) — **not** any claim that `/simplify` lacks a
      target.
- [ ] The simplifier prompt states the Write/Edit-tool path explicitly, so agents do not each
      rediscover a consumer hook that blocks shell writes.
- [ ] Soft cap of 4–6 concurrent simplifiers, degrading to sequential under rate-limit pressure
      rather than retrying. The skill states that this is a cost/quality choice, not the harness
      ceiling (which is 20), and that verifiers and refinement agents consume slots too.
- [ ] A fresh-context refutation verifier runs per group, mandatory in repo mode only.
- [ ] **`SKILL.md:174` is amended** so its "objective verification is enough" exemption is scoped to
      the diff-scoped modes, naming the distinguishing principle: at repo scale there is no
      human-reviewable diff. Left unamended, the file carries two contradictory doctrines.

**Delivery**

- [ ] Per-wave pull requests (~6–11), each independently mergeable, opened and merged sequentially so
      the plugin's ≥3-open-PR backlog throttle is respected. **Not** one repo-wide PR; **not** ~61
      per-group PRs.
- [ ] Run state (groups, per-group status, deferred items) persists to the consumer-resolved
      working-notes location with the existing inline fallback — **never** a hardcoded `.work/`.
- [ ] Resume semantics are idempotent: a group with uncommitted edits is reverted before resume, not
      re-simplified on top.
- [ ] The confirmation gate presents the inventory summary (file count, group count, wave plan, scale
      estimate) on both entry paths. An explicit-prose unattended escape exists and is **recorded in
      the Phase 8 report**.

**Deferred items**

- [ ] All deferred items persist to the run-state inventory.
- [ ] Work items are filed for High only, with **no numeric cap**, at the existing unit ("one per
      deferred concern, not per site"). High-only is a deliberate repo-mode narrowing from the
      current High+Medium default (`SKILL.md:164`) and is stated as such.
- [ ] High deferral volume is reported as a scope diagnostic, per constraint 2. No rollup issue —
      the run-state inventory is the durable artifact, which is the established local pattern.

**Verification and version discipline**

- [ ] Each wave verifies the ecosystems that wave touched; one union pass runs at end of run.
- [ ] The skill states explicitly that files with no mapped suite fall through to the refutation
      verifier and the end-of-run union pass. `scripts/affected-tests.sh` is **not** named in the
      skill body — it does not ship with the plugin.
- [ ] The version-bump phase is presence-gated on a versioned-plugin layout
      (`plugins/*/.claude-plugin/plugin.json`), with a stated non-silent fallback: "no version
      discipline detected; skipping bump phase". It names the base ref that `--check-bump` requires.

**Documentation and packaging**

- [ ] Repo-scale machinery lives in `context/repo-mode.md`, loaded only when the mode fires
      (`SKILL.md` is 194 lines against a 200-line soft target and a 500-line hard cap).
- [ ] `docs` composes with `repo` as a separate confirmation tier; the inventory summary reports the
      markdown count separately.
- [ ] A reciprocal one-line boundary statement is added to **both** `batch-simplify` and
      `tidy` — batch-simplify owns factual staleness across the whole doc set in one pass;
      tidy's `docs-prose` lane owns incremental structural prose work under a scope budget — and
      `tidy/SKILL.md:37`'s differentiation prose is updated, since repo mode removes the mechanism it
      currently names.
- [ ] Mode-worded surfaces are updated: the `description` opener ("across all recently changed
      files"), the no-files exit string (`SKILL.md:110`), and `context/reference.md:34`'s
      `Scope: {scope}` line.
- [ ] Sibling doc surfaces stating the mode set are updated: `plugins/code-tidying/README.md:15,27-28`,
      the plugin manifest description, and the generated `docs/CATALOG.md` / `docs/SKILL-CHEAT-SHEET.md`.
- [ ] At least one eval covers repo mode; the existing four evals still pass. Trigger keywords in the
      description are preserved (skill-quality check 3).
- [ ] `code-tidying` receives a minor version bump and a changelog entry.

### Captured assumptions

1. Wave count lands near #2842's 11 waves at this repo's scale, so "~6–11 PRs" is an estimate, not a
   contract. The binding rule is one PR per wave, each independently mergeable.
2. The ≥3-open-PR backlog throttle applies to repo mode's PRs as it does to tidy's. If it does not,
   the sequential open-and-merge discipline can relax.
3. Deferring `repo <path>` to a later version is reversible; the parser fixes it depends on are
   being made now regardless.

### Out of scope

- `repo <path>` subtree narrowing, and any lane-based `repo <lane>` surface.
- Recovering #2842's ~330 still-open deferred items — verified unrecoverable (never tracked; no
  inventory issue was ever filed).
- Minting an in-marketplace simplifier agent (blocked by the named-agent bar, constraint 3).
- Adding per-ecosystem test selectors for Python/JS/PowerShell. Repo mode documents the gap and
  routes unmapped files to the verifier; building selectors is separate work.
- Changing the existing time-window and branch modes' verification doctrine.

### Deferred questions

- **Q26 — should `repo <path>` (or `repo <lane>`) ship in a later version?** Arbiter: USER-RESERVED.
  Deferred out of v1 by the user. The lane-based form is the only narrowing surface with local
  precedent, and the choice interacts with whether tidy's lane config becomes a shared seam.
- **Q25 — should per-ecosystem test selectors be built?** Arbiter: `/planning:plan`. Repo mode ships
  with the gap documented; whether to close it is separate, larger work, and 225 source files in
  `plugins/knowledge` alone currently have no mapped suite.
- **Q21 — should hotspot ranking (change frequency × complexity/health, lifetime-normalized) return
  once the sweep is truncatable?** Arbiter: `/planning:plan`. Ranking only changes outcomes under
  truncation or resume; with no `--max-groups` in v1 its only consumer is resume order.

## Plan

*(Empty — `/planning:plan` fills this section.)*
