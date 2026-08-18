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

### Skill-lint invocation (used by every phase)

`check-skill.sh` takes a **skill name resolved under a skills root**, not a SKILL.md path — passing a
path fails with `Skill not found` regardless of the work. Every phase therefore uses the repo's own
wrapper, which maps changed paths to skill dirs, wires `CHECK_SKILL_BASE_REF`, and adds
`--require-evals` when a SKILL.md is modified:

```bash
bash scripts/check-changed-skills.sh origin/main
```

Direct form, only when a single skill must be checked in isolation:
`CHECK_SKILL_SKILLS_ROOT=plugins/code-tidying/skills bash plugins/skill-quality/scripts/check-skill.sh batch-simplify`.

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
| `plugins/code-tidying/skills/batch-simplify/SKILL.md` | MODIFY | `:39` (where the branch trigger rule is **authored**) and `:41` (where it is restated); `:55` docs-flag detection |
| `plugins/code-tidying/skills/batch-simplify/evals/evals.json` | MODIFY | Add one eval pinning the corrected grammar |
| `plugins/code-tidying/CHANGELOG.md` | MODIFY | Patch-bump entry |
| `plugins/code-tidying/.claude-plugin/plugin.json` | MODIFY | Patch bump |

1. **Fix substring matching.** The rule is authored at `:39` ("argument is `branch`, or contains
   "branch"…") and restated at `:41`. **Both** must change, or the defect stays live. Change to
   exact-token matching against the branch trigger set (`branch`, `feature branch`, `all commits`),
   so a value that merely mentions the word does not misroute.
2. **Fix stripping precedence.** `:55` strips `docs` from `$ARGUMENTS` before mode parsing. Change to
   token-wise stripping: split the argument into whitespace-separated tokens, remove a token that
   *equals* `docs` (case-insensitive), and parse the remainder — so `docs` as a standalone flag still
   works while a token merely containing the substring survives.
3. **Keep the unknown-argument behavior.** `:41`'s "anything else → ask the user rather than guessing"
   is retained verbatim; the fix narrows what matches, it does not widen what is accepted.

**Sanity Check:**

- `grep -n 'contains "branch"' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns **no
  match** (confirms `:39`, the authoring site, was fixed — not just the restatement).
- `grep -cnE 'exact token|token-wise|equals' plugins/code-tidying/skills/batch-simplify/SKILL.md`
  returns ≥ 2 (`-E`, not the basic-regex `\|` form — BSD grep on macOS treats `\|` literally and the
  check would always fail there).
- `node -e "console.log(require('./plugins/code-tidying/skills/batch-simplify/evals/evals.json').evals.length)"`
  prints `5` (node, not `python3` — `PLUGIN-PHILOSOPHY.md:178` flags `python3` as a WindowsApps alias
  stub on Windows).
- `bash scripts/check-changed-skills.sh origin/main` exits 0.
- `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0.

### Phase 2: Repo mode exists end-to-end [TODO]

The walking skeleton: the mode parses, discovers, filters, and reports. Everything a run needs to
complete once, correctly, at any scale.

| File | Action | What changes |
|---|---|---|
| `plugins/code-tidying/skills/batch-simplify/SKILL.md` | MODIFY | `repo` row in the detection heuristic; Mode 3 section; Phase 1 discovery; Phase 2 exclusion; precondition check; `:2` description, `:4` argument-hint, **`:8` `metadata.summary`**, **`:17` Purpose**, `:110` exit string |
| `plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` | CREATE | Spoke, with its full section skeleton (Phase 3 fills the bodies) |
| `plugins/code-tidying/skills/batch-simplify/context/reference.md` | MODIFY | `:34` `Scope: {scope}` line covers the repo case |

1. **Detection heuristic** gains one row: argument is the exact token `repo` → repo mode. Placed so
   it cannot be shadowed by the time-window regex or the branch trigger set.
2. **Mode 3 section** documents the scope and states that `repo <path>` is deliberately not accepted
   in v1 (Brief, Deferred Q26) — an unknown trailing token falls through to the existing
   ask-the-user rule.
3. **Phase 1 discovery**: `git ls-files --cached --others --exclude-standard`, anchored to the repo
   root (`git -C "$(git rev-parse --show-toplevel)" …`) — bare `git ls-files` returns only the
   current subtree when invoked from a subdirectory. No GNU-only constructs (Brief constraint 12).
4. **Precondition check, scoped — not a bare dirty-tree refusal.** Two corrections the naive form
   gets wrong:
   - It must cover **only files in the sweep universe**, explicitly excluding the working-notes
     location. The skill's own first step writes a checklist there (`SKILL.md:21`) and repo mode
     persists run state there; in a consumer repo that location may not be ignored, so a
     whole-tree refusal would block the run it just set up — and block every resume.
   - It must reconcile with `--others`. That flag exists to list **untracked** files, so a refusal
     that treats untracked files as dirty makes the flag dead. Decision: the precondition covers
     **tracked modifications** in the sweep universe; untracked non-ignored files are swept, and the
     Mode 3 section says so plainly so nobody is surprised that new files are simplified.
5. **Phase 2 exclusion, phrased as a discovered class.** Not a hardcoded `.github/standards/**`: the
   rule is "any directory the consuming repo documents as externally managed or sync-generated is a
   read-only deferred class". A concrete path may appear as an illustration only, annotated
   `portability-ok:`. Hardcoding this repo's layout into a general-purpose skill is the exact defect
   `PLUGIN-PHILOSOPHY.md:8-16` names, and the portability token list would not catch it.
6. **Empty-scan offer**: the existing no-files exit gains a named offer of repo mode. It offers;
   it never escalates.
7. **`context/repo-mode.md` created with its full section skeleton**, so the spoke link resolves
   (skill-quality check 5) and Phase 3 fills bodies rather than inventing structure.
8. **Line budget, pre-decided.** SKILL.md is 194 lines against a 200 soft target, so Phase 2 crosses
   it without relocation. Move the **Mode 3 body** and the **exclusion rationale** into the spoke,
   leaving only the heuristic row, a two-line Mode 3 pointer, and the discovery command in SKILL.md.
   Target: **≤ 205 lines** after Phase 2. The approval gate below then confirms a decided answer
   rather than opening a question mid-implementation.

**Sanity Check:**

- `grep -cE '^\| *`?repo`? ' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns ≥ 1 — the
  heuristic table has a `repo` row. (A bare `grep -c 'repo'` is vacuous: the unmodified file already
  returns 11, matching "report"/"reports".)
- `grep -n 'ls-files --cached --others --exclude-standard' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns exactly 1 match.
- `grep -n 'recently changed' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns **no match
  at all** — `:2`, `:8` and `:17` all carry that phrasing today, so any surviving match is an
  unfinished edit. (The earlier "no match on line 2" form was unrunnable — grep has no line
  predicate.)
- `node -e "const y=require('fs').readFileSync('plugins/code-tidying/skills/batch-simplify/SKILL.md','utf8').split('---')[1];const s=y.match(/summary: (.*)/)[1];console.log([...s].length)"`
  prints ≤ 100 (check 22's codepoint cap; the pre-edit summary is 71).
- `grep -qiE "simplify everything" plugins/code-tidying/skills/batch-simplify/SKILL.md` exits 0 — the
  trigger phrase survives and still means the 48h default.
- `bash scripts/check-changed-skills.sh origin/main` exits 0 — **run here, not deferred to Phase 5**:
  it carries check 3 (trigger preservation) against `origin/main`, and once Phase 2 is committed a
  dropped trigger becomes invisible to later phases whose base ref is HEAD.
- `bash scripts/check-shell-portability.sh origin/main` and
  `bash scripts/check-skill-portability.sh origin/main` both exit 0.
- `wc -l < plugins/code-tidying/skills/batch-simplify/SKILL.md` returns ≤ 205.

### Phase 3: Repo-scale run machinery [TODO]

Fills the spoke. All content here is loaded only when repo mode fires, keeping SKILL.md near its
current length.

| File | Action | What changes |
|---|---|---|
| `plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` | MODIFY | Full spoke content (9 sections below) |

**Shipped-content rule for this phase.** The spoke ships to consumer repos. It must not name this
repo's internal tracker items, its PR numbers, or repo-root scripts that do not ship with the plugin
— the same bar Phase 4 applies to `affected-tests.sh`. Describe the *mechanism*, not our instance
of it.

1. **Grouping and canonical clusters** — deterministic base pass, then agent refinement (merge
   undersized, split over the existing 25-file threshold). A synced or generated copy is **removed
   from its group** and edited only via its source plus the repo's own regeneration script. State the
   hazard generically ("a prior repository-wide run lost a whole bucket by editing copies directly"),
   without the PR number.
2. **Ordering** — dependency constraint only (shared/canonical libraries first). State explicitly
   that churn ranking is **not** used and why (change-frequency alone is a documented
   false-positive generator), so a later reader does not "helpfully" add it back.
3. **Concurrency** — soft cap 4–6 concurrent simplifiers, stated as a cost/quality choice, **not**
   the harness ceiling of 20 concurrent subagents. Note that verifiers and refinement agents consume
   slots too, and that resuming a finished subagent takes a slot without checking the limit. Degrade
   to sequential; never retry into the cap.
4. **Execution and spawn contract** *(Brief "Execution" block — was missing from the draft)* — one
   agent per group, spawned with an inline prompt and an explicit absolute-path file list;
   `pr-review-toolkit:code-simplifier` when installed, else `general-purpose`. State that repo mode
   does **not** invoke the bundled `/simplify`, and give the real reasons: at the spawn-depth limit
   it silently degrades to a single-pass variant, and each such worker occupies five concurrency
   slots rather than one. State the Write/Edit-tool path explicitly so agents do not each rediscover
   a consumer hook that blocks shell writes.
5. **Refutation verifier** *(Brief "Execution" block)* — a fresh-context verifier per group that
   tries to refute "behavior preserved", mandatory in repo mode. This is the load-bearing check for
   files no test suite maps to.
6. **Run state and resume** — consumer-resolved working-notes location with the existing inline
   fallback; never a hardcoded `.work/`. Resume is idempotent: revert is scoped to **that group's
   file list**, never the whole tree — a tree-wide revert would destroy the run-state notes that make
   resume possible.
7. **Confirmation gate** — inventory summary (file count, group count, wave plan, scale estimate) on
   both entry paths; explicit-prose unattended escape, recorded in the Phase 8 report. **`docs` tier**
   *(Brief scope item)*: when the `docs` flag composes with `repo`, the summary reports the markdown
   count separately and confirms it as its own tier.
8. **Wave and union verification** *(Brief scope item)* — each wave verifies the ecosystems that wave
   touched; one union pass runs at end of run. Files with no mapped suite fall through to §5's
   verifier plus the union pass.
9. **Deferred items** — persist everything; file High only, **no numeric cap**, at the existing
   "one per deferred concern, not per site" unit; report high volume as a scope diagnostic; no
   rollup issue. State that High-only is a deliberate repo-mode narrowing from the current
   High+Medium default.
10. **Delivery** — per-wave PRs, each independently mergeable, opened and merged sequentially so the
    open-PR backlog throttle is respected. State why not one PR (a repository-wide PR overlaps every
    path, which stale-base and merge-conflict gates punish, and it exceeds any workable review
    budget) and why not per-group (dozens of PRs jam the same throttle). Do not name this repo's
    gate script.

**Sanity Check:**

- `grep -c '^## ' plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` ≥ 10.
- `grep -qE 'code-simplifier' …/repo-mode.md` exits 0 and `grep -qiE 'does not invoke|never invokes' …/repo-mode.md` exits 0 — the spawn contract and the `/simplify` exclusion are both present.
- `grep -qiE 'refut' …/repo-mode.md` exits 0 — the verifier section exists.
- `grep -qiE 'union' …/repo-mode.md` exits 0 — wave/union verification exists.
- `grep -n '#2842' …/repo-mode.md` returns **no match**; `grep -nE 'affected-tests|check-stale-base-overlap|scripts/sync-' …/repo-mode.md` returns **no match** — no non-shipping repo-root script or internal tracker id leaked into shipped content.
- `grep -niE 'churn' …/repo-mode.md` returns ≥ 1 match (the not-used rationale is present).
- `grep -n '\.work/' …/repo-mode.md` returns **no match**.
- `grep -qiE 'no numeric cap|without a cap' …/repo-mode.md` exits 0.
- `grep -qE '20 concurrent' …/repo-mode.md` exits 0 — the real ceiling is named. (A bare `grep -n '20'` is vacuous: it matches any year or four-digit id.)
- `bash scripts/check-shell-portability.sh origin/main`, `bash scripts/check-skill-portability.sh origin/main`, and `bash scripts/check-changed-skills.sh origin/main` all exit 0 — this phase writes the bulk of the new markdown, including shell snippets and path globs.
- `npx markdownlint-cli2 plugins/code-tidying/skills/batch-simplify/context/repo-mode.md` reports 0 issues.

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
3. **Version-bump phase presence gate, phrased as a discovered class.** Gate on "a versioned-plugin
   or package-manifest layout, if the consuming repo has one" — **not** a hardcoded
   `plugins/*/.claude-plugin/plugin.json`, which is this marketplace's layout baked into a
   general-purpose skill (`PLUGIN-PHILOSOPHY.md:8-16`). State a non-silent fallback — "no version
   discipline detected; skipping bump phase" — and note that the parity check, where one exists,
   needs a base ref. Do not name any repo-root script as an unconditional dependency.
4. **tidy reciprocity.** `tidy/SKILL.md:37` currently differentiates the two skills by "a time-window
   or branch diff in waves" — the exact mechanism repo mode removes. Rewrite it, and add a one-line
   boundary to **both** skills: batch-simplify owns factual staleness across the whole doc set in one
   pass; tidy's `docs-prose` lane owns incremental structural prose work under a scope budget.

**Sanity Check:**

- `grep -A1 -B1 'verification enough' plugins/code-tidying/skills/batch-simplify/SKILL.md | grep -qiE 'time-window|branch mode|diff-scoped'`
  exits 0 — the exemption is now scoped to the diff-scoped modes. (The earlier "sits within a
  sentence" wording was a prose judgment, not a runnable check.)
- `grep -n 'affected-tests' plugins/code-tidying/skills/batch-simplify/SKILL.md` returns **no match**.
- `grep -n 'time-window or branch diff in waves' plugins/code-tidying/skills/tidy/SKILL.md` returns
  **no match** (the stale differentiator is gone).
- `grep -qiE 'batch-simplify' plugins/code-tidying/skills/tidy/SKILL.md` exits 0 (the boundary line
  is present).
- `grep -qiE 'no version discipline detected' plugins/code-tidying/skills/batch-simplify/SKILL.md` exits 0.
- `grep -nE '\.claude-plugin/plugin\.json' plugins/code-tidying/skills/batch-simplify/SKILL.md`
  returns **no match**, or every match carries a `portability-ok:` annotation — the layout is
  described as a discovered class, not hardcoded.
- `bash scripts/check-changed-skills.sh origin/main` exits 0 (covers both edited skills).

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
| [ ] `plugins/code-tidying/skills/batch-simplify/templates/checklist.md` | MODIFY | Repo mode adds a confirmation gate, a precondition check, a run-state inventory, a mandatory per-group verifier and per-wave delivery — none tickable in the current 8-phase list; its skip criteria also encode the High+Medium filing default that repo mode narrows to High-only |
| [ ] `plugins/code-tidying/skills/batch-simplify/SKILL.md` | KEEP | Final read-through only; edits landed in Phases 1–4 |

1. Update the README and manifest description to state three modes.
2. Regenerate both derived docs with their own scripts rather than hand-editing.
3. Add repo-mode-conditional rows to the run checklist, and reconcile its filing-tier skip criteria.
4. Add at least one repo-mode eval covering: explicit `repo` entry, the confirmation gate, and the
   deferred-item policy. Verify the four existing evals still describe current behavior.
5. Minor version bump plus changelog entry (a new mode is a feature, not a fix).

**Sanity Check:**

- `node -e "console.log(require('./plugins/code-tidying/skills/batch-simplify/evals/evals.json').evals.length)"` prints ≥ `6`.
- `node scripts/generate-catalog.mjs --check` and `node scripts/generate-cheatsheet.mjs --check` both exit 0.
- All **four** parity modes exit 0: `--check`, `--check-bump origin/main`, `--check-order`, and
  `--check-preserved origin/main`. The fourth is not optional here — two bumps land on one branch
  (patch in Phase 1, minor in Phase 5), and `--check-preserved` is the mode that catches a
  merge-forward resolution absorbing the Phase 1 heading into the Phase 5 entry.
- `bash scripts/validate-plugins.sh` exits 0.
- `bash scripts/check-changed-skills.sh origin/main` exits 0.
- `grep -qE 'time window.*branch.*repo' plugins/code-tidying/README.md` exits 0 — the README states
  all three modes. (The earlier `grep -c 'recently changed' … returns 0` was vacuous: that phrase was
  never in the README; its actual text is "sweeps files changed in a time window … or on the current
  branch" at `:15-16`.)
- `grep -qiE 'repo' plugins/code-tidying/skills/batch-simplify/templates/checklist.md` exits 0.

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

**Step 3 plan-reviewer (fresh context, did not author the plan): 20 findings — 1 BLOCKER, 7 HIGH,
10 MEDIUM, 2 LOW.** Every finding I spot-checked reproduced against the actual files. All confirmed
findings are fixed in the phases above. The load-bearing ones:

- **BLOCKER — three Sanity Checks were unrunnable.** `check-skill.sh` takes a skill *name* under a
  skills root, not a SKILL.md path; the planned command fails with `Skill not found` regardless of
  the work. Verified by running it. Replaced throughout with the repo's own wrapper,
  `scripts/check-changed-skills.sh origin/main`.
- **Three Sanity Checks passed before any work was done.** `grep -c 'repo' SKILL.md ≥ 8` — the
  unmodified file returns 11 ("report"/"reports"). `grep -c 'recently changed' README.md returns 0` —
  that phrase was never in the README. `grep -n '20' repo-mode.md` — matches any year. All replaced
  with discriminating forms.
- **A whole Brief scope block was dropped.** The Execution criteria — spawn contract, the
  `/simplify` exclusion, the Write/Edit-tool statement, and the mandatory refutation verifier — mapped
  to no phase item. Also dropped: the `docs` confirmation tier and wave/union verification. Added as
  spoke sections 4, 5, 7 and 8.
- **Dirty-tree refusal would have blocked its own run.** The skill writes a checklist to the
  working-notes location as its first step; a whole-tree refusal blocks the run that just set it up,
  and blocks every resume. Compounded by the planned resume revert, which would have destroyed the
  run-state notes. Both scoped down.
- **Consumer-layout hardcodes.** `.github/standards/**` and `plugins/*/.claude-plugin/plugin.json`
  were being baked into a general-purpose skill — the exact defect `PLUGIN-PHILOSOPHY.md:8-16` names,
  and one the portability token list would not catch. Both rephrased as discovered classes.
- **Internal provenance in shipped content.** The spoke was to cite `#2842` and two repo-root scripts
  that do not ship with the plugin — inconsistent with the plan's own bar for `affected-tests.sh`.
- **Cross-platform defects in the plan's own commands.** `grep 'a\|b'` fails on BSD grep (macOS);
  `python3` is a WindowsApps alias stub. Switched to `grep -E` and `node`.
- **Reviewer correction.** It reported `.work/` as tracked; it is in fact self-ignored via
  `.work/.gitignore` containing `*`. But that file was written by a tooling agent this session, not
  by the repo, so the portability concern behind the finding stands for consumer repos and the fix
  was applied.

Verified sound and left as-is: both generators do support `--check`; the two-bumps-on-one-branch
shape passes all four parity modes; every line-number citation in the plan checked out.

## Execution shape

**Sequential — by cost judgment, not by impossibility.** Being accurate about the basis: Phases 1, 2
and 4 all edit `batch-simplify/SKILL.md` and genuinely must serialize, and Phase 5 depends on the
final state. But a parallel slice **does** exist — Phase 3 touches only `context/repo-mode.md`, and
Phase 4's `tidy/SKILL.md` half touches neither that file nor `batch-simplify/SKILL.md`, so folding
the spoke's creation into Phase 3 would make `{Phase 3} ∥ {Phase 4 tidy-side}` schedulable.

It is not taken. The work is ~500 lines of prose that must hold one voice and one set of cross-
references across two skills; splitting it across agents buys little wall-clock and risks exactly the
inconsistency Phase 4 exists to remove. That is a cost/quality call, and it is recorded as one.

Per-phase routing:

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | Small, judgment-heavy contract fix on a published grammar |
| 2 | main session | Shares SKILL.md with Phases 1 and 4; ordering matters |
| 3 | main session | Long-form prose that must match the skill's established voice |
| 4 | main session | Doctrine wording across two skills; highest care, lowest volume |
| 5 | main session | Mechanical, but gated on generator scripts and parity checks |

Cost note: all-main-session, no sub-agent fan-out.

## Open questions

None blocking. Three questions carry forward from the Brief with arbiters assigned: `repo <path>` /
`repo <lane>` as a later surface (USER-RESERVED), per-ecosystem test selectors, and whether hotspot
ranking returns once runs are truncatable. None gates this plan.

## Handoff to implementation

### User-approval gates

- **Phase 1 shipping alone.** Phase 1 fixes pre-existing behavior and is independently mergeable. If
  it ships as its own PR, surface that before opening it — and note the **precondition**: Phase 1's
  PR and the Phases 2–5 branch both touch `batch-simplify/SKILL.md`, `CHANGELOG.md` and
  `.claude-plugin/plugin.json`, so once Phase 1 merges, the second branch is behind the target tip on
  overlapping paths — exactly what the required stale-base-overlap check fails. **Rebase Phases 2–5
  onto the merged Phase 1 tip before opening the second PR.** Phase 1 also carries its own patch
  bump, with the feature bump landing on top.
- **SKILL.md crossing the 200-line soft target.** Phase 2 pre-decides its relocations and targets
  ≤ 205 lines. If the actual edit still exceeds that, stop and surface it rather than silently
  accepting a warning or cutting existing prose to make room.

### Execution shape (`[EXEC-SHAPE]` tagged)

Sequential, all main-session, in phase order. Sanity checks run at each phase boundary; a failing
check blocks the next phase. No scope-fencing tables are needed — there are no parallel agents.

**Sequential fallback path:** not applicable (already sequential).

### Mechanical work

- One commit per phase. Conventional Commits per `docs/conventions/commit-convention/`: Phase 1 is
  `fix(code-tidying):`, Phases 2–4 are `feat(code-tidying):`, Phase 5 is `feat(code-tidying):` or
  `chore(code-tidying):` for the generated-doc regeneration.
- PLAN.md phase tags advance `[TODO]` → `[DOING]` → `[DONE]` in a separate `docs(topics):` commit,
  not folded into the `fix(code-tidying):` / `feat(code-tidying):` commit — a `docs/topics/**` edit
  does not belong under a `code-tidying` scope.
- Full verification before the PR: `scripts/validate-plugins.sh`, all four
  `check-changelog-parity.sh` modes, `check-changed-skills.sh`, `check-skill-portability.sh`,
  `check-shell-portability.sh`, and `markdownlint-cli2` on every touched markdown file.
