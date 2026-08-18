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

### Standards grounding

No `docs/standards/` index exists in this repository (absent-index case; the contract forbids
unprompted writes, so none was created — an index can be offered separately). Grounded instead in
the repo's own convention docs, matched to the surfaces this plan touches:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| Plugin design boundary | `docs/PLUGIN-PHILOSOPHY.md:8-16` (no undocumented consumer layout), `:709-711` (dispatch ladder), `:718-721` (named-agent bar) | team |
| Seam phrasing | `docs/conventions/seam-phrasing/README.md` — "'Skip silently' is not a fallback" | team |
| Topic docs | `docs/conventions/topic-docs/README.md` — memory vs contract tier, pointer discipline | team |
| Commits | `docs/conventions/commit-convention/README.md` | team |
| Scope budget (this plugin) | `plugins/code-tidying/skills/tidy/reference/scope-budget.md:9-22`, `:121-123` | team |
| Skill lint | `plugins/skill-quality/scripts/check-skill.sh` — check 3 (trigger preservation), check 4 (500-line cap), check 10 (200-line soft target) | team |

### Phase 1: Fix the argument parser [TODO]

Independently shippable. These are **pre-existing defects**, not repo-mode work: the grammar must be
coherent before a third scope value can be added to it. Ships as its own `fix:` commit and can be
merged alone.

**Pre-flight consumer check (FIRST work item).** The argument grammar is a contract. Before editing:
`Grep` for other surfaces that describe or parse batch-simplify's arguments — at minimum
`plugins/code-tidying/README.md`, the plugin manifest description, `docs/CATALOG.md`,
`docs/SKILL-CHEAT-SHEET.md`, and the four existing evals. Document which of them state the grammar,
so Phase 5 updates exactly that set rather than guessing.

| File | Action | What changes |
|---|---|---|
| `plugins/code-tidying/skills/batch-simplify/SKILL.md` | MODIFY | `:41` detection heuristic and `:55` docs-flag detection |
| `plugins/code-tidying/skills/batch-simplify/evals/evals.json` | MODIFY | Add one eval pinning the corrected grammar |
| `plugins/code-tidying/CHANGELOG.md` | MODIFY | Patch-bump entry |
| `plugins/code-tidying/.claude-plugin/plugin.json` | MODIFY | Patch bump |

1. **Fix substring matching.** `:41` routes any argument *containing* "branch" to branch mode. Change
   to exact-token matching against the branch trigger set (`branch`, `feature branch`,
   `all commits`), so a value that merely mentions the word does not misroute.
2. **Fix stripping precedence.** `:55` strips `docs` from `$ARGUMENTS` before mode parsing. Change to
   token-wise stripping: split the argument into whitespace-separated tokens, remove a token that
   *equals* `docs` (case-insensitive), and parse the remainder — so `docs` as a standalone flag still
   works while a token merely containing the substring survives.
3. **Keep the unknown-argument behavior.** `:41`'s "anything else → ask the user rather than guessing"
   is retained verbatim; the fix narrows what matches, it does not widen what is accepted.

**Sanity Check:**

- `grep -n 'contains "branch"' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns **no
  match** (the substring rule is gone).
- `grep -n 'equals\|exact token\|token-wise' plugins/code-tidying/skills/batch-simplify/SKILL.md`
  returns at least 2 matches (both fixes state their matching discipline).
- `python3 -c "import json;d=json.load(open('plugins/code-tidying/skills/batch-simplify/evals/evals.json'));print(len(d['evals']))"` prints `5`.
- `bash plugins/skill-quality/scripts/check-skill.sh plugins/code-tidying/skills/batch-simplify/SKILL.md` exits 0.
- `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.

### Phase 2: Repo mode exists end-to-end [TODO]

The walking skeleton: the mode parses, discovers, filters, and reports. Everything a run needs to
complete once, correctly, at any scale.

| File | Action | What changes |
|---|---|---|
| `plugins/code-tidying/skills/batch-simplify/SKILL.md` | MODIFY | `repo` row in the detection heuristic; Mode 3 section; Phase 1 discovery; Phase 2 exclusion; dirty-tree refusal; `:2` description opener; `:4` argument-hint; `:110` exit string |
| `plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` | CREATE | Progressive-disclosure spoke (stub in this phase, filled in Phase 3) |
| `plugins/code-tidying/skills/batch-simplify/context/reference.md` | MODIFY | `:34` `Scope: {scope}` line covers the repo case |

1. **Detection heuristic** gains one row: argument is the exact token `repo` → repo mode. Placed so
   it cannot be shadowed by the time-window regex or the branch trigger set.
2. **Mode 3 section** documents the scope and states that `repo <path>` is deliberately not accepted
   in v1 (Brief, Deferred Q26) — an unknown trailing token falls through to the existing
   ask-the-user rule.
3. **Phase 1 discovery**: `git ls-files --cached --others --exclude-standard`. No GNU-only
   constructs (Brief constraint 12 — `code-tidying` is not in the shell-portability baseline).
4. **Dirty-tree refusal**: repo mode refuses to start when the working tree is dirty, naming the
   reason (per-group commits would capture uncommitted work).
5. **Phase 2 exclusion**: add `.github/standards/**` as a read-only deferred class, with the reason
   (standards-`managed`; local edits are silently lost on sync).
6. **Empty-scan offer**: the existing no-files exit gains a named offer of repo mode. It offers;
   it never escalates.
7. **`context/repo-mode.md` created as a stub** with its section headings, so the spoke link in
   SKILL.md resolves (skill-quality check 5 requires backtick-cited internal files to resolve).

**Sanity Check:**

- `grep -c 'repo' plugins/code-tidying/skills/batch-simplify/SKILL.md` ≥ 8.
- `grep -n 'ls-files --cached --others --exclude-standard' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns exactly 1 match.
- `grep -n '\.github/standards' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns ≥ 1 match.
- `grep -niE 'dirty|uncommitted' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns ≥ 1 match.
- `test -f plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` exits 0.
- `grep -n 'recently changed' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns **no match** on line 2 (the description opener no longer claims changed-files-only).
- `bash scripts/check-shell-portability.sh origin/main` exits 0.
- `bash plugins/skill-quality/scripts/check-skill.sh plugins/code-tidying/skills/batch-simplify/SKILL.md` exits 0 (checks 4 and 10: SKILL.md stays under the 500-line cap; note if it crosses the 200-line soft target).

### Phase 3: Repo-scale run machinery [TODO]

Fills the spoke. All content here is loaded only when repo mode fires, keeping SKILL.md near its
current length.

| File | Action | What changes |
|---|---|---|
| `plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` | MODIFY | Full spoke content (7 sections below) |

1. **Grouping and canonical clusters** — deterministic base pass, then agent refinement (merge
   undersized, split over the existing 25-file threshold). A synced copy is **removed from its
   plugin's group** and edited only via its source plus `scripts/sync-*.sh` regeneration; state that
   #2842 lost its `_lib` bucket to exactly this hazard.
2. **Ordering** — dependency constraint only (shared/canonical libraries first). State explicitly
   that churn ranking is **not** used and why (change-frequency alone is a documented
   false-positive generator), so a later reader does not "helpfully" add it back.
3. **Concurrency** — soft cap 4–6 concurrent simplifiers, stated as a cost/quality choice, **not**
   the harness ceiling (20). Note that verifiers and refinement agents consume slots too, and that
   resuming a finished subagent takes a slot without checking the limit. Degrade to sequential;
   never retry into the cap.
4. **Run state and resume** — consumer-resolved working-notes location with the existing inline
   fallback; never a hardcoded `.work/`. Resume is idempotent: a group with uncommitted edits is
   reverted before resume, not re-simplified on top.
5. **Confirmation gate** — inventory summary (file count, group count, wave plan, scale estimate) on
   both entry paths; explicit-prose unattended escape, recorded in the Phase 8 report.
6. **Deferred items** — persist everything; file High only, **no numeric cap**, at the existing
   "one per deferred concern, not per site" unit; report high volume as a scope diagnostic; no
   rollup issue. State that High-only is a deliberate repo-mode narrowing from the current
   High+Medium default.
7. **Delivery** — per-wave PRs, each independently mergeable, opened and merged sequentially so the
   ≥3-open-PR backlog throttle is respected. State why not one PR (`check-stale-base-overlap.sh` is
   a required check and a repo-wide PR overlaps everything) and why not per-group (~61 PRs jams the
   same throttle).

**Sanity Check:**

- `grep -c '^## ' plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` ≥ 7.
- `grep -n 'sync-' plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` returns ≥ 1 match.
- `grep -niE 'churn' plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` returns ≥ 1 match (the not-used rationale is present).
- `grep -n '\.work/' plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` returns **no match**.
- `grep -niE 'no numeric cap|without a cap' plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` returns ≥ 1 match.
- `grep -n '20' plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` returns ≥ 1 match (the real ceiling is named).

### Phase 4: Doctrine reconciliation [TODO]

Three places where shipping repo mode without an edit would leave the marketplace self-contradictory.

| File | Action | What changes |
|---|---|---|
| `plugins/code-tidying/skills/batch-simplify/SKILL.md` | MODIFY | `:174` exemption scoping; verification fall-through; version-bump presence gate |
| `plugins/code-tidying/skills/tidy/SKILL.md` | MODIFY | `:37` differentiation prose; reciprocal boundary line |

1. **Amend `SKILL.md:174`.** Today it reads that objective cross-ecosystem verification "is
   verification enough" because simplification is behavior-preserving — a scale-invariant claim.
   Scope it to the diff-scoped modes and name the distinguishing principle: at repo scale there is no
   human-reviewable diff, so the per-group refutation verifier is mandatory. Without this the file
   carries two contradictory doctrines.
2. **Verification fall-through.** State that files with no mapped test suite fall through to the
   refutation verifier plus the end-of-run union pass. Do **not** name `scripts/affected-tests.sh` —
   it does not ship with the plugin.
3. **Version-bump phase presence gate.** Gate on a versioned-plugin layout
   (`plugins/*/.claude-plugin/plugin.json`) with a stated non-silent fallback — "no version
   discipline detected; skipping bump phase" — and name the base ref `--check-bump` requires. Do not
   name the repo-root script as an unconditional dependency.
4. **tidy reciprocity.** `tidy/SKILL.md:37` currently differentiates the two skills by "a time-window
   or branch diff in waves" — the exact mechanism repo mode removes. Rewrite it, and add a one-line
   boundary to **both** skills: batch-simplify owns factual staleness across the whole doc set in one
   pass; tidy's `docs-prose` lane owns incremental structural prose work under a scope budget.

**Sanity Check:**

- `grep -n 'verification enough' plugins/code-tidying/skills/batch-simplify/SKILL.md` — the surviving
  match sits within a sentence that also matches `grep -niE 'time-window|branch mode|diff-scoped'` on
  the same or adjacent line.
- `grep -n 'affected-tests' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns **no match**.
- `grep -n 'time-window or branch diff in waves' plugins/code-tidying/skills/tidy/SKILL.md` returns
  **no match** (the stale differentiator is gone).
- `grep -niE 'batch-simplify' plugins/code-tidying/skills/tidy/SKILL.md` returns ≥ 1 match (the
  boundary line is present).
- `grep -niE 'no version discipline detected' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns 1 match.
- `bash plugins/skill-quality/scripts/check-skill.sh plugins/code-tidying/skills/tidy/SKILL.md` exits 0.

### Phase 5: Packaging, sibling docs, and evals [TODO]

Everything that states the mode set, plus the release artifacts.

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-tidying/README.md` | MODIFY | `:15`, `:27-28` describe the mode set |
| [ ] `plugins/code-tidying/.claude-plugin/plugin.json` | MODIFY | Minor bump; description states "recently changed files" |
| [ ] `plugins/code-tidying/CHANGELOG.md` | MODIFY | `## [<minor>]` Added entry |
| [ ] `plugins/code-tidying/skills/batch-simplify/evals/evals.json` | MODIFY | Add repo-mode evals |
| [ ] `docs/CATALOG.md` | MODIFY | Regenerate via `scripts/generate-catalog.mjs` |
| [ ] `docs/SKILL-CHEAT-SHEET.md` | MODIFY | Regenerate via `scripts/generate-cheatsheet.mjs` |
| [ ] `plugins/code-tidying/skills/batch-simplify/templates/checklist.md` | KEEP | Phase list is unchanged by repo mode — audited, no edit |
| [ ] `plugins/code-tidying/skills/batch-simplify/SKILL.md` | KEEP | Final read-through only; edits landed in Phases 1–4 |

1. Update the README and manifest description to state three modes.
2. Regenerate both derived docs with their own scripts rather than hand-editing.
3. Add at least one repo-mode eval covering: explicit `repo` entry, the confirmation gate, and the
   deferred-item policy. Verify the four existing evals still describe current behavior.
4. Minor version bump plus changelog entry (a new mode is a feature, not a fix).
5. Confirm every description trigger keyword from the pre-edit description survives
   (skill-quality check 3).

**Sanity Check:**

- `python3 -c "import json;d=json.load(open('plugins/code-tidying/skills/batch-simplify/evals/evals.json'));print(len(d['evals']))"` prints ≥ `6`.
- `node scripts/generate-catalog.mjs --check` and `node scripts/generate-cheatsheet.mjs --check` both exit 0.
- `bash scripts/check-changelog-parity.sh --check && bash scripts/check-changelog-parity.sh --check-bump origin/main && bash scripts/check-changelog-parity.sh --check-order` all exit 0.
- `bash scripts/validate-plugins.sh` exits 0.
- `bash scripts/check-changed-skills.sh origin/main` exits 0.
- `grep -c 'recently changed' plugins/code-tidying/README.md` returns 0.

## Blast radius

**MEDIUM.** No executable code changes — the deliverable is skill prose, one JSON evals file, and
generated docs. But the blast radius is not trivial: the skill is published to a marketplace and
installed in consumer repos, the edit changes a documented argument grammar (Phase 1 alters existing
behavior), it amends a doctrine statement another skill's readers rely on, and it edits a sibling
skill. Triggers matched: published-contract change, cross-component edit.

**Stress-test needed:** the Step 3 fresh-context plan-reviewer runs regardless (mandatory). Formal
`/planning:devils-advocate` is **not** invoked — the design was already adversarially validated by
two independent fresh-context validators plus two artifact verifiers under `/planning:audit-answers`,
which is the same discipline applied to the decisions this plan implements.

## Stress-test summary

Upstream of this plan, `/planning:audit-answers` ran two independent validators over all 18 design
answers with the producing session's rationale withheld: 9 confirmed, 7 challenged, 2 reclassified to
the user. Three answers changed materially (delivery shape, prioritization, deferred-item policy) and
three stated rationales were refuted and recorded as such. Both discovery artifacts were graded by
fresh-context refutation verifiers, each returning FAIL-with-corrections, with verdicts written back
into the artifacts. Research coverage gate exits 1 on one declared, bounded row.

Step 3 plan-reviewer findings are recorded below at approval time.

## Execution shape

**Fully sequential — no parallel wave.** The file-overlap matrix collapses: Phases 1, 2 and 4 all
edit `batch-simplify/SKILL.md`; Phase 3 edits the spoke Phase 2 creates; Phase 5 depends on the final
state of everything. There is no subset with zero overlap and no dependency, so parallelism has
nothing to schedule.

Per-phase routing:

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | Small, judgment-heavy contract fix on a published grammar |
| 2 | main session | Shares SKILL.md with Phases 1 and 4; ordering matters |
| 3 | main session | Long-form prose that must match the skill's established voice |
| 4 | main session | Doctrine wording across two skills; highest care, lowest volume |
| 5 | main session | Mechanical, but gated on generator scripts and parity checks |

Cost note: all-main-session, no sub-agent fan-out. A parallel shape was considered and rejected as
unschedulable, not as too expensive.

## Open questions

None blocking. Three questions carry forward from the Brief with arbiters assigned: `repo <path>` /
`repo <lane>` as a later surface (USER-RESERVED), per-ecosystem test selectors, and whether hotspot
ranking returns once runs are truncatable. None gates this plan.

## Handoff to implementation

### User-approval gates

- **Phase 1 shipping alone.** Phase 1 fixes pre-existing behavior and is independently mergeable. If
  it ships as its own PR, surface that before opening it — it carries its own patch bump, and the
  later feature bump then lands on top.
- **SKILL.md crossing the 200-line soft target.** If Phase 2 or 4 pushes the file past check 10's
  soft target, stop and surface it rather than silently accepting a warning or aggressively cutting
  existing prose to make room.

### Execution shape (`[EXEC-SHAPE]` tagged)

Sequential, all main-session, in phase order. Sanity checks run at each phase boundary; a failing
check blocks the next phase. No scope-fencing tables are needed — there are no parallel agents.

**Sequential fallback path:** not applicable (already sequential).

### Mechanical work

- One commit per phase. Conventional Commits per `docs/conventions/commit-convention/`: Phase 1 is
  `fix(code-tidying):`, Phases 2–4 are `feat(code-tidying):`, Phase 5 is `feat(code-tidying):` or
  `chore(code-tidying):` for the generated-doc regeneration.
- PLAN.md phase tags advance `[TODO]` → `[DOING]` → `[DONE]` in the same commit as that phase's
  changes.
- Full verification before the PR: `scripts/validate-plugins.sh`, all four
  `check-changelog-parity.sh` modes, `check-changed-skills.sh`, `check-skill-portability.sh`,
  `check-shell-portability.sh`, and `markdownlint-cli2` on every touched markdown file.
