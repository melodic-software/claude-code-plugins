# Plugin conformance audit: plan

Status: APPROVED by the user 2026-09-27. Phases 0 and 1 shipped in #4538: the dependency rule in
`docs/plugin-philosophy.md`, the registry `docs/conformance-dimensions.md`, and its integrity gate.
Phases 2 to 5 have not started; this document is their approved plan, and its user gates still
hold. It graduated here from the task branch's `docs/topics/plugin-alignment-audit/PLAN.md` (in
history at `38774fdfc4a70bed30ff79f5a158dcb129daf858`), so "this branch" and "this PR" below mean
the branch that picks up Phase 2.

## Brief

Build `/audit-plugin-conformance`, a repo-local skill in `.claude/skills/` that audits one plugin, or
all of them, against `docs/plugin-philosophy.md`. It composes the checks and judgment skills that
already exist, and adds three deterministic scripts plus one registry. It becomes the "fleet
conformance audit" the philosophy doc cites. All design decisions are in
`docs/specs/plugin-conformance-design-threads.md` (T1-T17, all RESOLVED; the several-positions tier in T15 is
TAGGED-DEFERRED). The capability map is `docs/specs/plugin-conformance-capability-matrix.md`; the file layout and
registry row shape are in `docs/specs/plugin-conformance-topology.md`.

Scope items (each maps to a phase):

1. Dependency inventory classes as a philosophy rule (T12) → Phase 1
2. Concern registry `docs/conformance-dimensions.md` and its integrity check (T9, T13) → Phase 1
3. Leaf-name verb grammar gate with a baseline (T10, T13), then follow-up issue 5 (T11) → Phase 2
4. Dependency and repeated-literal candidate-list scripts (T3, T13) → Phase 3
5. The orchestrator skill (T1, T14, T15) → Phase 4
6. Rewrite every live "fleet audit" citation (T7, widened below) → Phase 5

Out of scope: a `realign` sibling, a `--fix` mode, the several-positions tier, model-graded evals,
fixing issues #4582-#4586.

Constraint (user, 2026-09-27): no new model-driven CI. Every CI step this plan adds runs a
deterministic script (bash, no `claude`, no API key, no Claude GitHub Action). The skill runs only
when a person invokes it; the existing review and security-review lanes stay the only Claude-driven
CI jobs.

Success: every phase's Sanity Check passes; `/audit-plugin-conformance animation` writes a findings
report in which every finding carries a registry id and every registry row has a lane that ran; no
live doc outside frozen records cites a conformance audit that does not exist.

## Plan

Standards grounding: `AGENTS.md` (draft PRs, when to stop), `.claude/rules/skill-bodies-state-current-rules.md`
(read before writing the skill body; four-part record and `## Next` section),
`.claude/rules/ruff-pin.md` (only if a phase adds Python), `docs/plugin-philosophy.md` Naming,
Skills are processes, One owner per value, Fresh-eyes checkpoints; `docs/conventions/finding-suppression/`,
`docs/conventions/topic-docs/` (memory tier), `docs/conventions/shell-test-helpers/`.

Test strategy: TDD per script. Each new or extended script gets a sibling `scripts/<name>.test.sh`
fixture test (the pattern of `scripts/check-skill-leaf-names.test.sh`), written red first. Test
boundaries: each script's command line (arguments, stdout/stderr, exit code); all exist or are
introduced here, none added for testability alone. Every `scripts/check-*.sh` follows the family
contract (exit 0 pass, 1 findings, 2 usage/prerequisite; findings on stderr) and gets a row in
`scripts/check-script-contract.test.sh`. The skill body is gated by
`plugins/skill-quality/scripts/check-skill.sh` (root form) in CI, and checked end to end by one real
run.

### Phase 0: Precondition [DONE]

Notes: #4534 merged as `cd0300607`; main merged in at `5048c1769`. Every `docs/plugin-philosophy.md`
line cited by this plan and the design (`:90-92`, `:110-112`, `:118-176`, `:136-145`, `:220-235`,
`:254`, `:301-303`, `:431-434`, `:440-456`, `:464`, `:513`, `:638`, `:660`, `:684-688`, `:867`) is
unchanged on main; no refresh needed. Sanity: ancestor check exit 0, heading count `2`, pixel-art
`scene` present.

- Confirm #4534 is merged: `gh pr view 4534 --json state --jq .state` prints `MERGED`.
- `git merge origin/main` into this branch; resolve conflicts.
- Re-read the "Skills are processes", "One owner per value", "Prerequisites and failure behavior"
  and "Convention registry" sections on the merged `docs/plugin-philosophy.md` and refresh every
  line number this plan and the design cite (they were read from the `feat/animation-plugin` copy).

**Sanity Check:** `git merge-base --is-ancestor origin/main HEAD` exits 0;
`grep -c '^## Skills are processes$\|^## One owner per value$' docs/plugin-philosophy.md` prints `2`;
`test -d plugins/pixel-art/skills/scene` exits 0 (#4407 is on main).

### Phase 1: Rule and registry [DONE]

Notes: registry has 16 rows (dim-8, dim-9, dim-11, dim-12 to dim-24). Sanity: registry tests
PASS=15 FAIL=0; `--check` exit 0; `check-lane-coverage.sh --check` exit 0;
`check-docs-only-gate.sh --check` exit 0; `no central registry` count 0; shellcheck and
shell-portability clean. `check-script-contract.test.sh` PASS=37 FAIL=2, both failures
`check-html-assets.sh` needing `htmlhint` (no `npm ci` in this worktree), unrelated to this phase.
Reviewed before merge against this phase's work items and Sanity Check (2026-09-27), with main
merged in: no finding; every Sanity Check command re-ran green.

Work items:

1. Add the dependency inventory classes and their verdict set to "Prerequisites and failure
   behavior" in `docs/plugin-philosophy.md` (T12): external binaries and versions, network ports,
   sizes and resolutions, other plugins' layouts, installed browsers, PATH lookups; verdicts port,
   `userConfig`, presence-gated, documented, fix needed. Reuse the section's absence classes.
2. Create `docs/conformance-dimensions.md`: one table. Row shape per `docs/specs/plugin-conformance-topology.md`
   (`id`, `concern`, `owner`, `checks`, `ci`, `scope`) plus one column, `lane`: either a script
   command line, or a judgment question the skill hands a fresh subagent. Every row has a
   non-empty `lane`; that is what makes each citation checkable. Ids `dim-8`, `dim-9`, `dim-11` keep
   their meaning (`docs/conventions/hook-observability/README.md`, the dim-N paragraph); the rest
   are numbered after. Rows: capability-matrix concerns 1-7, plus one row per promise the Phase 5
   sites make (native-stance re-verification, setup coverage gap, teardown second adopter,
   convention-registry conformance, seam phrasing, visible skip, and the four sites in the T7
   widening below). `owner` is `path#Section heading text` (heading text is matched as text, not
   used as a link anchor). `scope` is `plugin` or `fleet`; a `fleet` row runs once per run and
   is not narrowed; a `plugin` row whose script takes no plugin argument states its narrowing in
   `lane` (a path filter on the finding lines). The table cites the skill by slash invocation only.
3. `scripts/check-conformance-registry.sh` + `.test.sh`, red first. `--check` fails when: a row's
   `lane` is empty; a `scripts/...` path in `checks` or `lane` does not exist; a `/<plugin>:<leaf>`
   does not resolve to `plugins/<plugin>/skills/<leaf>/SKILL.md` or a `/<leaf>` to
   `.claude/skills/<leaf>/SKILL.md`; an `owner` file is missing or its heading text is not a level-2
   or level-3 heading line in it; a row with `ci: yes` names a script that `.github/workflows/ci.yml` does
   not run. Add its row to `scripts/check-script-contract.test.sh`.
4. Wire it as standalone steps in `.github/workflows/ci.yml` beside the skill-leaf-name steps
   (test step, then `--check` step with `id:` + `continue-on-error: true`, outcome added to the
   aggregator near `ci.yml:1436`). This departs from T13's "wire into `scripts/validate-plugins.sh`":
   that script needs `claude` and `node` on PATH, and the standalone steps are covered by
   `scripts/check-lane-coverage.sh`. [EXEC-SHAPE; listed under Displaced answers]
5. Update the dim-N paragraph in `docs/conventions/hook-observability/README.md` to point at the
   registry ("no central registry" becomes false).

**Sanity Check:** `bash scripts/check-conformance-registry.test.sh` exits 0;
`scripts/check-conformance-registry.sh --check` exits 0;
`bash scripts/check-script-contract.test.sh` exits 0;
`scripts/check-lane-coverage.sh --check` exits 0; `scripts/check-docs-only-gate.sh` exits 0;
`grep -c 'no central registry' docs/conventions/hook-observability/README.md` prints `0`.

### Phase 2: Verb grammar gate [TODO]

Work items:

1. Pre-flight consumers of `scripts/check-skill-leaf-names.sh`:
   `grep -rn check-skill-leaf-names .github scripts docs plugins`. Known: `ci.yml:777`, `ci.yml:781`,
   `scripts/check-skill-leaf-names.test.sh`, `scripts/check-script-contract.test.sh:99`,
   `docs/plugin-philosophy.md:188`. The existing default and `--check` modes keep their behavior.
2. Add a `--grammar` mode (and `--grammar --check`). A leaf passes when its first hyphen-segment is
   in the verb list, or `plugin/leaf` is in the exception list, or `plugin/leaf` is in the baseline.
   Data: `scripts/skill-leaf-verbs.txt` holds two sections. Verbs: English imperative verbs only
   (the Naming verb table plus verbs in use that pass that test); a first segment that is not an
   imperative verb (`video`, `song`, `known`, `morning` ...) never enters the verb list. Exceptions:
   `plugin/leaf` keyed, never a bare leaf ("a name class is never blanket-sanctioned"). The Naming
   section stays the owner of the exception rule; the test asserts every exception's leaf appears
   in the Naming section, so the two cannot drift. Baseline: `scripts/skill-leaf-verb-baseline.txt`
   (`plugin/leaf` per line). The ratchet (a baseline entry that no longer exists fails) reuses
   `read_list::mark_used` / `read_list::report_stale` from `scripts/lib/read-list.sh`, as the
   collision registry already does.
3. Tests red first in `scripts/check-skill-leaf-names.test.sh`: a verb leaf passes, an unlisted noun
   fails, an excepted `plugin/leaf` passes, the same leaf in another plugin fails, a baselined leaf
   passes, a stale baseline entry fails, every exception leaf appears in the Naming section, the old
   collision cases still pass.
4. Generate the draft baseline from the tree. Report its size and the rejected first segments to
   the user before committing it (the reviewer estimates 35-45 of 269 leaves). [user gate]
5. CI: a `--grammar --check` step with its own `id:` and aggregator entry.
6. Follow-up issue 5 (T11): first search `gh issue list --state all --search "noun skill leaf"` and
   `--search "skill-leaf-verb-baseline"`. On a match, comment the baseline list there instead of
   filing. Otherwise file one issue listing every baseline entry, linking PR #4538 and #4586.

**Sanity Check:** `bash scripts/check-skill-leaf-names.test.sh` exits 0;
`scripts/check-skill-leaf-names.sh --check` and `scripts/check-skill-leaf-names.sh --grammar --check`
both exit 0; `scripts/check-lane-coverage.sh --check` exits 0;
`grep -c 'pixel-art/scene' scripts/skill-leaf-verb-baseline.txt` prints `1`; the issue search result
and the issue or comment URL are recorded in this phase's notes.

### Phase 3: Candidate-list scripts [TODO]

Work items:

1. `scripts/list-plugin-dependencies.sh <plugin-dir>` + `.test.sh`: prints TSV
   `class<TAB>file:line<TAB>match` for the Phase 1 classes a pattern can find: invoked binaries,
   literal ports, absolute paths, bare `python`/`bash` launches, `command -v`/PATH lookups. The
   patterns are new; `org-agnosticism-tokens.txt` holds org-name tokens only and is not reused or
   duplicated. Exit 0 always except usage (2).
2. `scripts/list-plugin-literals.sh <plugin-dir>` + `.test.sh`: prints TSV
   `literal<TAB>count<TAB>file:line,...` for numeric and path literals in 2+ files of one plugin,
   excluding measurement records the "One owner per value" rule exempts (a documented path list in
   the script header). Exit 0 always except usage.
3. CI runs only the two test files (these scripts list; they do not gate, T13).
4. Measure recall against the hand inventory in `docs/topics/animation-ports/design/dependency-inventory.md`
   (48 dependencies, 26 values; pruned, read it in history at
   `fe29b787d4dc998861e9a0e5144334566f90cbe2`) and record both numbers in this phase's notes.

**Sanity Check:** both `.test.sh` files exit 0;
`scripts/list-plugin-dependencies.sh plugins/animation | grep -c $'\t'` prints a number greater than
0; `scripts/list-plugin-literals.sh plugins/animation | grep -c $'\t'` prints a number greater than
0; the two recall numbers are in the phase notes.

### Phase 4: The skill [TODO]

Work items:

1. Read `.claude/rules/skill-bodies-state-current-rules.md` and `/playbooks:skill-authoring` first.
2. `.claude/skills/audit-plugin-conformance/SKILL.md`: the process only. It reads the registry and
   runs every row's `lane`; it holds no concern list of its own.
   - Argument: a plugin name, `all`, or empty. Empty means plugins changed on the branch versus
     `origin/main`; if that set is empty, say "no plugins changed" and ask for a target.
   - Step 1, script lanes: `fleet` rows run once; `plugin` rows run per plugin, narrowed as the row
     states. Includes the two Phase 3 scripts.
   - Step 2, judgment lanes: each plugin's judgment rows run in one fresh subagent per plugin, which
     never sees the orchestrator's reasoning. The routing test runs in its own nested subagent given
     only descriptions and requests. Maximum nesting depth 2.
   - Composed skills run only in read-only modes, presence-gated with a stated fallback:
     `/coupling:reduce dry-run <plugin>`, `/docs-hygiene:extract-ssot identify`,
     `/code-metrics:audit-duplication`, `/plugin-quality:audit` on its unattended path (no issue
     filing). No dispatched step may edit, branch, push, or file.
   - `all`: pilot one plugin; then state the remaining plugin count and the expected subagent count
     and ask before continuing; then batches of 5 plugins. On a usage-limit error, stop and report
     which plugins finished.
   - Persistence: `<memory_dir>/audit-plugin-conformance/<UTC timestamp>-<short sha>/`
     (default `.work/`, per `docs/conventions/topic-docs/`), one `<plugin>.md` per plugin, written
     when that plugin finishes. `resume <run-dir>` skips plugins whose file exists. Each run gets its
     own directory, so concurrent runs and worktrees do not collide.
   - Finding identity: `<registry id>|<plugin>|<file>:<line>`. Suppressions live in
     `.claude/audit-plugin-conformance.md` in the shape `docs/conventions/finding-suppression/`
     defines, keyed by that identity.
   - Report: every finding line is `- [<registry id>] <plugin> <file>:<line> <finding>`; a closing
     table lists each registry row with `ran`, `skipped (reason)`, or `n/a`.
   - `## Next` section naming the successor (filing findings, or a future `realign`).
3. CI: add a step running `bash plugins/skill-quality/scripts/check-skill.sh .claude/skills` (root
   form; CI's `check-changed-skills.sh` does not scan `.claude/skills/`), with `id:` and aggregator
   entry.
4. One real run: `/audit-plugin-conformance animation` in a fresh session.

**Sanity Check:** `bash plugins/skill-quality/scripts/check-skill.sh audit-plugin-conformance; echo $?`
ends in `0`; in the real run's `animation.md`,
`grep '^- \[' animation.md | grep -vc '^- \[dim-'` prints `0`, and the closing table has one line
per registry row (`grep -c '^| dim-' animation.md` equals `grep -c '^| dim-' docs/conformance-dimensions.md`);
`scripts/check-lane-coverage.sh --check` exits 0.

### Phase 5: Citation rewrites [TODO]

Rewrite every live site to name `/audit-plugin-conformance` and its registry id. T7's list:
`docs/plugin-philosophy.md` (the native-first adoption gate, the formatter/linter setup sentence, the
pre-contract setup sentence, the teardown second-adopter sentence, the Convention registry lead, and
the Monitors, Themes and Channels rows' "before each audit"), and
`docs/conventions/seam-phrasing/README.md` (Conformance). Widened by the reviewer's grep to four more
live sites of the same kind: `docs/finding-your-unknowns.md:142`,
`docs/conventions/hook-precision/README.md:66`, `docs/conventions/pre-pr-ordering/README.md:69`,
`docs/conventions/hook-observability/README.md:281`. [EXEC-SHAPE] Frozen records stay as written:
CHANGELOGs, `docs/upstream/**/research-*`, and `docs/topics/**`. Must land in the same PR as Phase 4
(T7).

**Sanity Check:**
`grep -rn -i -e 'fleet audits\? check' -e 'fleet conformance audit' -e 'before each fleet audit' docs plugins | grep -v -e 'docs/topics/' -e 'CHANGELOG.md' -e 'docs/upstream/'`
prints nothing; `scripts/check-conformance-registry.sh --check` exits 0.

## Blast radius

MEDIUM. About 20 files across `docs/`, `scripts/`, `.github/workflows/ci.yml` and `.claude/skills/`.
Three new CI gates (registry integrity, verb grammar, repo-local skill check) feed the aggregator,
so a failure turns `ci-status` red; each is reversible with `git revert`. Once the verb gate merges,
any open PR adding a noun leaf goes red: before flipping this PR ready, list open PRs touching
`plugins/*/skills/*/` (`gh pr list --search "is:open" --json number,files`) and report which add a
new leaf. The philosophy and convention edits change doctrine text other components cite.

## Stress-test summary

Step 3 plan-reviewer (fresh context): 4 CRITICAL, 11 IMPORTANT, 6 SUGGESTION. Step 4
`/planning:devils-advocate` (fresh context): 0 CRITICAL, 3 HIGH, 4 MEDIUM, 2 LOW, overlapping the
reviewer's. The main thread checked the load-bearing claims against the files: `check-skill.sh` on
a skill directory exits 2; the Phase 5 grep hit four live sites T7 missed plus frozen records;
`coupling:reduce` bare mutates and `dry-run` does not; `check-script-contract.test.sh` requires a row
per `check-*.sh`; #4407 is merged. All confirmed findings are fixed above:

- Skill check used the wrong argument form and a vacuous pass test (Phase 4 Sanity, CI step).
- Phase 5 grep could not pass; four more live sites added; frozen records excluded.
- Promises without checks: every registry row now carries a `lane` the skill runs, and the
  integrity check fails an empty one; the report proves each row ran.
- Composed skills pinned to read-only modes.
- Script-contract row, lane-coverage and docs-only-gate checks added.
- Exceptions keyed `plugin/leaf`, admission rule for verbs, Naming stays owner via a test.
- Ratchet reuses `read-list.sh`.
- Registry check resolves skills, headings and the `ci` column.
- Persistence, run key, concurrency, finding identity and suppression file specified.
- `all` capped: pilot, confirm with counts, batches of 5, depth 2, stop on usage limit.
- Empty-target behavior, merge proof, recall measurement, non-vacuous Phase 3 checks,
  open-PR impact, shell portability.

## Execution shape

Fully sequential: Phase 0 gates everything; Phase 1 creates the registry Phases 2-5 cite; Phase 4
runs the Phase 2-3 scripts; Phase 5 names the Phase 4 skill. Phases 2 and 3 share `ci.yml` and are
each under the ~100 LOC-per-worker saving that would justify parallel workers. [EXEC-SHAPE]

| Phase | Surface | Basis |
|---|---|---|
| 0 | main session | merge conflicts need judgment |
| 1 | main session | doctrine text and registry ids are judgment |
| 2 | main session | edits a shared CI gate; user gate on the baseline |
| 3 | sub-agent worker | two self-contained scripts with tests |
| 4 | main session | skill body is the product |
| 5 | main session | doctrine wording |

## Displaced answers and new external effects

| Q | User said | Plan now proposes | New external effect | Source | Reply |
|---|---|---|---|---|---|
| T13 | Wire the registry check into `scripts/validate-plugins.sh` | Standalone `ci.yml` steps | none | reviewer fix | reconfirmed 2026-09-27 |
| T7 | Rewrite the listed citation sites | Also rewrite four more live sites of the same kind | none | reviewer fix | reconfirmed 2026-09-27 |

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis | Source |
|---|---|---|---|
| Registry rows carry a `lane` column | Every row is runnable; the skill loops over rows instead of hard-coding concerns | T7 A requires an implementing check per promise; reviewer finding | reviewer fix |
| Judgment rows share one fresh subagent per plugin; routing test nested | Caps spawns at about 2 per plugin | Fresh-eyes rule needs separation from the producer, not one context per question | reviewer fix |
| Persistence under the memory tier with a run directory and `resume` | Defines T14's resume without reusing audit-pass's private scripts | `docs/conventions/topic-docs/`; encapsulation rule | reviewer fix |
| Phase 3 runs on a sub-agent worker | Frees the main session | File-disjoint scripts with tests | execution shape |

## Open questions

None. Hard-to-reverse decisions: none; every change is a `git revert` away, and the new CI gates
are `continue-on-error` steps.

## Handoff to implementation

### User-approval gates

- Phase 0: do not start until #4534 is merged.
- Phase 2 item 4: show the baseline size and rejected first segments before committing the baseline.
- Phase 2 item 6: filing is authorized (2026-09-27); still search first.
- Phase 4 `all` runs: the skill itself asks after the pilot.
- Any change to an existing CI step's behavior (not just added steps) stops for the user.
- Flipping the PR to ready uses `/source-control:pull-request ready`, after the open-PR impact list.

### Execution shape ([EXEC-SHAPE] tagged)

Sequential, per the table above.

### Mechanical work

- One commit per phase, by exact path; plan tag updates ride the same commit.
- Before each commit: `markdownlint-cli2` on changed markdown; `shellcheck` and
  `scripts/check-shell-portability.sh` on changed scripts.
- Sequential fallback for Phase 3's worker: main session writes the scripts itself.
