# fleet-sync

## Brief

### Scope change 2026-09-08 (pending approval at the plan gate)

Q4 is reversed. Parking does not extend `source-control`'s `worktree-create.sh`; sync owns its
parking primitive. Verification found the cross-plugin call unreachable: installed plugins live in
separate versioned cache directories, `docs/PLUGIN-PHILOSOPHY.md` forbids reaching into a sibling
plugin's files, and rungs 3 and 4 of that helper's root ladder are caller-supplied from
`source-control`'s own plugin option and data directory, which `repo-fleet-hygiene` cannot read.
Invoking `/source-control:worktree create` per park is also out, because that path terminates in
`EnterWorktree`. Sync therefore reimplements the root ladder against the documented
`melodic.worktreeroot` convention, which becomes the artifact contract between the two plugins. The
struck items below are superseded; the replacement text follows each.

Q6 is revised, also pending approval: a dirty checkout already on the default branch attempts
`pull --ff-only` first and parks only when git refuses because a dirty path would be overwritten.

### TLDR

- New `repo-fleet-hygiene:sync` skill: for every canonical repo checkout in scope, switch to the default branch and fast-forward pull; park divergent work in a linked worktree instead of losing it.
- Zero-argument invocation infers scope from a six-rung ladder (explicit args, fleet conf, conversation-named paths, ghq if present, cwd context, else a transparent "nothing resolved" exit). The resolver is a shared plugin script that `audit` adopts as its no-scope fallback.
- ~~Parking reuses `source-control`'s `worktree-create.sh` via a new existing-branch mode, so naming, root resolution, containment guard, `.worktreeinclude` copy, and lock claim are all inherited.~~ Superseded: parking is sync-owned. Sync reimplements the root ladder (`--worktree-root`, then `melodic.worktreeroot`, then a `${CLAUDE_PLUGIN_DATA}/worktrees` path passed through a file the SKILL.md writes, else refuse), the `<root>/<owner>-<repo>-<slug>` naming, the containment guard, the Windows same-drive check, and a park-specific lock claim, all as a pre-flight that runs before any mutation.
- Verb contract: bare invocation is a dry-run plan; mutation only with `--apply` after one confirmation gate. Non-fast-forward, dubious ownership, and partial stash apply are skip-and-report, never merge, rebase, reset, or config writes.
- Follow-up issue for `repo-hygiene:clean tree-batch` to gain the same zero-argument scope inference; not in this change.

### Goal

An operator on any machine can run one command from anywhere and have every canonical repository they own moved to its current default branch and fast-forwarded, with a report naming what moved, what was parked where, and what was skipped and why. Nothing uncommitted or unpushed is ever lost: work that would block the switch is moved into a linked worktree under the repository's configured worktree root and left exactly as it was.

### Constraints

- Lives in `plugins/repo-fleet-hygiene/skills/sync/`, sibling to `audit` and `apply`; `audit` stays read-only and its plan JSON schema is untouched (`apply-plan.sh` exits 2 on unknown operations, so sync never rides the plan).
- No hardcoded tool or layout: ghq, fleet conf, and cwd context are all presence-gated per `docs/PLUGIN-PHILOSOPHY.md` "Two-lane convention posture"; the skill works with none of them configured.
- Plugins stay horizontally decoupled: `repo-hygiene` does not call `repo-fleet-hygiene`'s resolver, and ~~the `source-control` change is confined to a new flag on `worktree-create.sh`~~ superseded: `source-control` takes no code change at all. The only cross-plugin coupling left is a documented one, the `melodic.worktreeroot` key described in `plugins/source-control/reference/worktree-root-convention.md`.
- Every git invocation the script emits must stay outside the guardrails block list (`reset --hard`, `clean -f*`, `checkout .`, `restore .`, `checkout -f`, `switch -f`, `--discard-changes`, force push). Allowed and used: `switch`, `pull --ff-only`, `fetch`, `ls-remote --symref`, `worktree add`, `stash push -u`/`apply`/`drop`, `status --porcelain`, `rev-list --count`.
- Stash handling: `stash push -u -m <unique marker>`, resolve the entry by marker to its SHA, `stash apply <sha>` in the park, then explicit `drop` by re-found ref; never bare `stash`/`pop` (the stack is repository-wide and shared with other sessions).
- Skill body follows `.claude/rules/skill-bodies-state-current-rules.md` (state rule and reason, no incident or PR citations, `## Next` section); frontmatter carries a paired `${CLAUDE_SKILL_DIR}` `allowed-tools` grant; `allowed-tools-pairing.test.sh` `SKILLS=` array gains `sync`.
- Tests are co-located plain-bash `<stem>.test.sh` selected by `scripts/affected-tests.sh`; every changed file must map to a suite. PR opens as a draft. Conventional Commits.
- Cross-platform: Bash script must run under Git Bash on Windows (paths via the repo's windows-path-emit convention) and on Linux CI; the Windows CI lane is informational.

### Acceptance criteria

- Bare `/repo-fleet-hygiene:sync` from inside a repo under a multi-repo parent, with no fleet conf and no ghq, resolves that parent as a root, prints a dry-run plan listing every repo with its source rung and intended action, and mutates nothing.
- With ghq on PATH and no other scope, every `ghq root --all` entry is used as a root; with explicit args or a fleet conf present, rungs 4 and 5 are not consulted.
- With no scope resolvable at any rung, the run prints what each rung probed and the remedies (pass a directory, run `repo-fleet-hygiene:setup`, install ghq) and exits 3 without touching any repository.
- `audit-fleet.sh` invoked with no scope and no config falls back to the shared resolver instead of failing with "no scope resolved"; its existing tests still pass and its `allowed-tools` grant is unchanged.
- `--apply` on a repo that is on the default branch, clean, and behind origin results in a fast-forward; `git rev-parse HEAD` equals `origin/<default>` afterwards.
- `--apply` on a repo whose canonical checkout is on a non-default branch with uncommitted changes leaves the canonical on the default branch, fast-forwarded, and a linked worktree at `<worktree-root>/<owner>-<repo>-<slug>` checked out on that branch with the uncommitted changes (tracked and untracked) present and no stash entry left behind.
- ~~`--apply` on a repo on the default branch with a dirty tree parks the changes on a new `park/<date>-<short-sha>` branch in a linked worktree, then fast-forwards the canonical.~~ Revised: `--apply` on a repo on the default branch with a dirty tree attempts `pull --ff-only` first; when the dirty paths are untouched by the incoming commits the fast-forward succeeds and no worktree is created, and only when git refuses because a dirty path would be overwritten are the changes parked on a new `park/<UTC yyyymmdd-HHMM>-<7-char sha>` branch before the canonical is fast-forwarded.
- A non-default branch that is clean and fully pushed is switched to default with no worktree created; the local branch ref survives.
- `pull --ff-only` failing (exit 1 or 128), a dubious-ownership refusal, and a stash apply that returns non-zero each produce a skipped/failed line naming the repo, the git exit code, and the remedy; the stash entry is retained on apply failure; the run continues with the next repo and exits non-zero at the end.
- The default branch is taken from `git ls-remote --symref <remote> HEAD`, where `<remote>` is the current branch's configured remote, else `origin`, else the sole remote; a repo whose local `<remote>/HEAD` points at a renamed-away branch still syncs to the remote's current default.
- `--repo`, `--root`, `--repos-from FILE|-`, `--skip`, `--skip-from`, `--dry-run` (default), `--apply` are accepted; duplicates across rungs are deduplicated by git common dir; linked worktrees given as targets are retargeted to their main worktree.
- ~~`worktree-create.sh` gains an existing-branch mode that refuses when the branch is checked out elsewhere (git's own exit 128 surfaced, never `--force`) and otherwise behaves identically to the new-branch mode for root resolution, containment, `.worktreeinclude`, and lock; its existing tests pass and a new test covers the mode.~~ Replaced by: sync's own parking primitive resolves a root through its three-rung ladder or refuses with the remedy; it refuses when the branch is checked out elsewhere (git's exit 128 surfaced, never `--force`); it never leaves the canonical checkout detached; a park is locked with a park-specific reason and the record prints the unlock remedy; `plugins/source-control/` is unchanged by this work.
- A repository whose worktree root resolves to a different Windows drive than the repository is `skipped` with the config remedy, before any mutation.
- With no configured remote for the current branch, no `origin`, and no sole remote, the repository is `skipped` naming the missing remote.
- `sync` honours the `cwd-repo` rung; `audit` deliberately does not, because a single incidental checkout is not fleet scope while a directory directly holding two or more repositories is fleet scope by construction.
- `scripts/affected-tests.sh --run` passes for the change set on Linux; the skill passes `skill-quality:check`.

### Captured assumptions

- No minimum git version gate; `ls-remote --symref` predates every git in the fleet. Revisit if a fleet host reports a `ls-remote` that lacks `--symref`.
- Stash breadth is `-u` (untracked, not ignored); ignored files are rebuildable. Revisit if an operator reports losing gitignored local state they needed.
- Rung 5's ancestor probe uses "≤4 levels up, directory directly holding ≥2 repos". Revisit if a fleet layout nests roots deeper or keeps single-repo folders that should count.
- `safe.directory` is never written by sync; the remedy is printed. Revisit if the fleet standardises on a per-root `'<root>/*'` entry via setup.
- Acceptance-criteria coverage prompt was asked; unwanted-behaviour cases are covered above (ff-only failure, partial apply, dubious ownership); no additional state-driven case was requested.
- Research verification: git semantics were verified against git's own docs, source, and binary, then corroborated from a second pool for 16 of 18 load-bearing claims; the two uncorroborated (double-`--force` worktree nuance, Windows ownership carve-outs) are not used by the design.

### Out-of-scope

- Adding `canonical-not-on-default`, `dirty-canonical`, `ahead-or-diverged` findings to `audit-fleet.sh` (Q3); sync computes them itself.
- A `--reset-diverged` escape hatch that shells to `git-tree-reset.sh` (Q8 alternative).
- Zero-argument scope inference for `repo-hygiene:clean tree-batch` (Q13); filed as a follow-up issue.
- Riding the audit's plan JSON or extending `apply-plan.sh` (Q2).
- Any merge, rebase, or reset fallback when a fast-forward is not possible.

### Deferred questions

- Q6 — exact `park/<date>-<short-sha>` naming and whether the date is UTC; defer until implementation; **arbiter: /planning:plan**. Resolved: `park/<UTC yyyymmdd-HHMM>-<7-char sha>`. The disposition itself is revised (try the fast-forward first) and is pending approval, see the scope-change note.
- Q14 — the exact flag name and output line format for reporting each target's source rung; defer until implementation; **arbiter: /planning:plan**. Resolved: no flag; the `detail` column carries `rung=<name>` as its first field.

## Plan

### Goal

Ship `repo-fleet-hygiene:sync`: a third sibling skill whose bundled `sync-fleet.sh` resolves a
repository scope through a shared six-rung resolver, then, per canonical checkout, moves the working
tree to the remote's current default branch and fast-forwards it, relocating any work that would
block the move into a linked worktree under the repository's configured worktree root. Bare
invocation is a dry-run plan; `--apply` mutates behind one confirmation gate. The resolver ships as a
plugin-level script so `audit` adopts it as its no-scope fallback. Parking is sync-owned: the skill
carries its own root ladder, containment guard, same-drive check, naming, and lock claim, coupled to
`source-control` only through the documented `melodic.worktreeroot` convention.

**Superseded findings.** The scope change at the top of the Brief moots the earlier review findings
about `worktree-create.sh`'s new mode (its consumer pre-flight, its exit-code surface, and the two
findings about inheriting that helper's `.worktreeinclude` copy and lock reason). `plugins/source-control/`
is untouched by this work.

### Standards grounding

No `docs/standards/` index exists in this repository, so grounding is inferred from the path-scoped
rule files under `.claude/rules/` and the owner docs under `docs/conventions/`, plus
`docs/PLUGIN-PHILOSOPHY.md` as the durable design policy.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `.claude/rules/skill-bodies-state-current-rules.md` | Keep-out list (issue and pull-request numbers, past-tense narration, date-conditional guidance, hardcoded bare-fact specifics); keep-in list; `## Next` successor sections | repo, path-scoped to `plugins/*/skills/**` |
| `.claude/rules/catalog-taxonomy.md` | Read `docs/CATALOG-TAXONOMY.md` Form rule, Assignment principle, Singleton governance before assigning or changing a category | repo, path-scoped to `.claude-plugin/marketplace.json` |
| `.claude/rules/pr-body-contract.md` | Closing-keyword line, the four required sections, draft the body before creating the pull request | repo |
| `docs/conventions/windows-path-emit/README.md` | Rule 1 (prefer a path the native side computes), rule 2 (convert at the boundary), rule 3 (`cygpath -m` via `scripts/emit-windows-path.sh`), rule 4 (fail loud), rule 5 (never `export` a conversion suppressor) | repo |
| `docs/conventions/permission-rule-hygiene/README.md` | The correct pattern (bare name on PATH, narrow allow rule, operator-setup boundary); the known gap that plugin `bin/` delivery is per-session unreliable | repo |
| `docs/PLUGIN-PHILOSOPHY.md` | Two-lane convention posture (presence-gate anything a consuming repo may not have); cross-platform contract | repo |
| `plugins/repo-fleet-hygiene/skills/apply/SKILL.md` | Frontmatter shape, `disable-model-invocation: true`, non-negotiable boundary, confirmation-gate table, "What this skill does NOT do" | plugin sibling, the shape to match |

Three specifics this plan is reviewed against and does not restate per phase: every git form the
scripts emit stays outside the guardrails block list; stash use is `push -u -m <marker>` then
`apply <sha>` then `drop` by re-found ref; and every path named here is repo-relative.

### Approach

1. **Land the thinnest end-to-end slice first.** Phase 1 creates
   `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh` supporting only the `explicit` rung
   and `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh` supporting only dry-run
   classification, wired together. Every later phase widens one of the two along a seam the tracer
   already proved.
2. **Take `batch-common.sh` through the repo's sync-cluster idiom, not by hand.** A hand-copied
   library drifts silently. Add `scripts/sync-batch-common.sh` in the shape of
   `scripts/sync-hook-utils.sh` (which parameterizes the shared engine at `scripts/lib/sync-cluster.sh`):
   source `plugins/repo-hygiene/skills/clean/scripts/lib/batch-common.sh`, copy target
   `plugins/repo-fleet-hygiene/skills/sync/scripts/lib/batch-common.sh`. That gives the cluster a
   `--check` gate in CI and a `--print-manifest` mode `scripts/affected-tests.sh` reads, so a source
   change re-runs the copy's dependents. The two plugins stay horizontally decoupled at runtime; the
   coupling is a checked build-time copy. `clean-common.sh` (`clean_path_key`, `clean_skip_matches`)
   comes across the same way as a second copy in the same cluster. Only `batch_emit` is adapted
   locally, its four-line `Repo:`/`Outcome:`/`Reason:`/`---` block becoming the single tab-delimited
   `<repo-path>  <outcome>  <action>  <detail>` record the design fixes; the resolve-dedup loop stays
   inline for the same reason `git-tree-reset-batch.sh` keeps it inline (a repo directory whose name
   contains a literal backslash must not be folded away). The orchestration skeleton of
   `git-tree-reset-batch.sh` is still read as a shape, not copied: dry-run default, one batch-wide
   gate, a per-repo outcome vocabulary, unmatched-skip reporting.
3. **Copy the walk from inside this plugin.** `resolve-fleet-scope.sh` emits only `root` and `repo`
   targets; the bounded discovery walk belongs to `sync-fleet.sh`, adapted from
   `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh` (`discover_repositories`: the
   nested-repository early return, symlink and junction non-descent, unreadable-directory tolerance,
   depth bound) plus its `main_worktree` retargeting.
4. **Two distinct `--skip` grammars, never conflated.** The resolver's `--skip NAME` mirrors the
   audit's: a bare directory basename consulted during the walk, replacing the default list rather
   than appending to it. `sync-fleet.sh`'s `--skip ENTRY` mirrors the batch tier's: a
   segment-anchored repo entry (absolute path, `owner/repo`, or bare repo name) consulted after
   enumeration.
5. **Own the parking primitive.** Parking lives in the sync skill, in `sync-fleet.sh` or a sibling
   file under its `lib/`. `plugins/source-control/` takes no code change. The root ladder is
   `--worktree-root <dir>`, then `melodic.worktreeroot` read from the target repository with includes
   on and after a `rev-parse --git-dir` gate (a scoped read skips every `includeIf`, and under
   dubious ownership a bare `config --get` returns the global value with rc 0), then
   `${CLAUDE_PLUGIN_DATA}/worktrees` supplied through a `--data-root-file` the SKILL.md writes, else
   refuse with the remedy. Naming is `<root>/<owner>-<repo>-<slug>`. The containment guard, the
   Windows same-drive check, the park-path-free check, the in-progress-operation check, and the
   submodule-superproject check all run as one pre-flight before any mutation.
6. **Adopt the resolver in `audit`, minus one rung.** `audit-fleet.sh` calls the resolver only when
   its own rungs yield nothing, and takes `config`, `ghq`, `cwd-root`, and `cwd-ancestor` but not
   `cwd-repo`. A single incidental checkout is not fleet scope, which is the rule the audit already
   enforces at its unresolved-scope branch; a directory that directly holds two or more repositories
   is fleet scope by construction. Sync keeps `cwd-repo`, so the two verbs diverge on exactly one
   rung and the Brief says so.

#### Dependencies

- Depends on: `plugins/source-control/reference/worktree-root-convention.md` as a documented artifact
  contract (the `melodic.worktreeroot` key, its multi-valued last-wins read, the two silent hazards,
  and the outside-every-repository and same-drive requirements), not on any `source-control` code;
  `plugins/repo-hygiene/skills/clean/scripts/lib/batch-common.sh` as a synced copy source;
  `scripts/lib/sync-cluster.sh` as the wrapper engine; the git semantics settled in
  `.work/fleet-sync/git-semantics/RESEARCH.md` (query `ls-remote --symref` rather than read the
  `origin/HEAD` cache; the stash stack is repository-wide; `--ff-only` is safe to attempt blind;
  `worktree add <path> <branch>` exits 128 when the branch is checked out elsewhere).
- Depended on by: `scripts/affected-tests.sh` selection (every new script needs a co-located suite,
  the new sync-cluster manifest feeds its R5/R6 rules, and an explicit mapping makes a change to
  `resolve-fleet-scope.sh` re-run `audit-fleet.test.sh` since the audit now consumes it);
  `plugins/repo-fleet-hygiene/scripts/allowed-tools-pairing.test.sh` (its `SKILLS` array);
  `scripts/check-changelog-parity.sh --check-bump` (each bumped plugin needs a new changelog entry);
  `scripts/check-fleet-audit-doc-grammar.sh` and
  `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh` (both parse the audit's
  no-scope failure text).

### Test strategy

Test-first throughout. Each phase writes its failing assertions into the co-located suite before the
production edit, then makes them pass. Suites are plain bash `<stem>.test.sh` in the shape of
`plugins/repo-fleet-hygiene/skills/apply/scripts/apply-plan.test.sh`: `unset GIT_DIR GIT_WORK_TREE
GIT_CONFIG` before `set -euo pipefail`, a `mktemp -d` fixture with `trap 'rm -rf "$TMP"' EXIT`,
hand-rolled `pass` / `fail` / `assert_contains` helpers, a `fails` accumulator, and an exit on
`$fails`. Every fixture repository is a throwaway `git init -q -b main` under that `mktemp -d`,
paired with a throwaway `git init -q -b main --bare` serving as its `origin`, so `fetch`,
`ls-remote --symref`, and `pull --ff-only` run against a real remote with no network. The explicit
`-b main` matters: a host without `init.defaultBranch` set yields `master`, and an assertion naming
`origin/main` would fail for a reason unrelated to the change. Every fixture is given at least one
commit and pushed (`git -C <fixture> commit -q --allow-empty -m init` then
`git -C <fixture> push -q -u origin main`) before any run, because an unborn HEAD makes
`rev-parse HEAD` fail and makes `ls-remote --symref` on an empty remote host-version-dependent.
"Behind origin" is produced by pushing a further commit from a second clone of the same bare remote.

Test boundaries, each named with whether it exists today:

| Boundary the tests drive | Status | Suite |
|---|---|---|
| `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh` CLI (argv, stdout `target` records, stderr `probe` trace, exits 0 / 2 / 3) | INTRODUCED in Phase 1 | `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.test.sh` (new) |
| `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh` CLI (argv, per-repo records, `Summary:` line, `UnmatchedSkip:` lines, exits 0 / 1 / 2 / 3) | INTRODUCED in Phase 1 | `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.test.sh` (new) |
| `scripts/sync-batch-common.sh` CLI (`sync`, `--check`, `--check-bump <ref>`, `--print-manifest`) | INTRODUCED in Phase 3 | `scripts/sync-batch-common.test.sh` (new, in the shape of the sibling sync-cluster suites) |
| `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh` CLI (no-scope behavior after resolver adoption) | EXISTS | `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh` (existing, extended) |
| `scripts/check-fleet-audit-doc-grammar.sh` no-scope probe (a consumer of the audit CLI, not a new boundary) | EXISTS | `scripts/check-fleet-audit-doc-grammar.test.sh` (existing, extended only if the probe changes) |
| `plugins/repo-fleet-hygiene/scripts/allowed-tools-pairing.test.sh` (a file-reading contract gate; drives no CLI) | EXISTS | itself, with `sync` added to its `SKILLS` array |

Presence-gated external tools are stubbed, never assumed. Every "nothing resolves" assertion prepends
a fixture `bin` directory to `PATH` holding an executable `ghq` that exits non-zero, because the
resolver presence-gates on `command -v ghq` and an absent binary is a different code path from a
present binary yielding no roots. The ghq-rung assertion uses a second stub that prints a fixture
root.

What the assertions prove, in the order they are written:

- **Resolver.** An explicit `--repo` yields exactly one `target repo <abs-path> explicit` record and
  nothing else on stdout; a config supplying `fleet.root` is additive to an explicit target; a
  present `ghq` fires only when explicit and config are both empty; the cwd ancestor probe resolves a
  directory that directly holds two fixture repos and does not resolve one holding a single repo; a
  run with no rung satisfied exits 3, names every probed rung on stderr, and prints the three
  remedies.
- **Sync classification.** A fixture on the default branch, clean, behind its origin classifies
  `would-sync` / `ff-pull`; a non-default clean fully-pushed fixture classifies `would-sync` /
  `switch+ff-pull`; a non-default fixture with unpushed commits classifies `would-park` /
  `park-branch`; a dirty default-branch fixture classifies `would-park` / `park-dirty-default`; a
  detached HEAD classifies `skipped`. Every dry-run assertion also proves nothing moved: `git -C
  <fixture> rev-parse HEAD` and `git -C <fixture> status --porcelain` match their pre-run capture,
  `git -C <fixture> stash list` is empty, and `git -C <fixture> worktree list` has one entry.
- **Apply, one case per acceptance criterion.** `HEAD` equals `origin/<default>` after a
  fast-forward; after `park-branch` on a dirty non-default fixture the canonical is on the default
  branch and fast-forwarded, a linked worktree exists on the parked branch holding both a tracked
  edit and an untracked file, and `git stash list` in the canonical is empty; after
  `park-dirty-default` the park branch matches `^park/[0-9]{8}-[0-9]{4}-[0-9a-f]{7}$`; a clean
  fully-pushed non-default fixture switches with no worktree created and its local branch ref still
  resolves.
- **Failure paths, each asserted to skip and continue rather than fall back.** A diverged fixture
  produces a `failed` record naming the git exit code and a remedy, the run exits 4, and a later
  clean fixture in the same run still syncs; a park whose target branch is checked out in another
  worktree produces a `failed` record; a stash apply returning non-zero leaves the stash entry
  present (`git stash list` non-empty) and the park directory in place; a `stash push` that produces
  no entry matching the marker is `failed` with the canonical untouched; an `ls-remote` failure and a
  network timeout each produce `failed` with a remedy; a park path that already exists, including the
  same-minute name collision, is `failed` with a remedy.
- **New skipped rows.** A repository with an in-progress merge, rebase, or cherry-pick; a repository
  whose `.gitmodules` makes it a submodule superproject; a repository whose resolved worktree root is
  on a different Windows drive; a repository with no configured remote for the current branch, no
  `origin`, and no sole remote; a linked worktree given directly as a target, unless its main
  worktree is itself in scope in the same run, in which case only the main worktree is processed.
- **Remote and upstream selection.** A fixture whose current branch has a configured remote other
  than `origin` uses that remote; a fixture with a sole non-`origin` remote uses it; a fixture whose
  upstream ref no longer exists (an upstream default renamed away) is compared against
  `<remote>/<branch>` when that exists and is otherwise treated as unpushed and parked.
- **Post-conditions.** After every mutating step, the symbolic ref of HEAD equals the intended target
  and `status --porcelain` matches the expected shape; a mismatch is `failed`, asserted by a fixture
  that is mutated out from under the run between steps.
- **Offline and network hardening.** A run with `--no-fetch` against a bare remote whose directory
  has been made unreachable classifies without error and marks the affected records `provisional`; a
  network verb wrapped by the timeout helper is asserted to return `failed` rather than hang, using
  the fast-timeout test switch the audit already carries.
- **Guardrail conformance, asserted statically as well as behaviorally.** A grep over both new
  scripts for the blocked forms (`reset --hard`, `clean -f`, `checkout .`, `restore .`,
  `checkout -f`, `switch -f`, `--discard-changes`, `push --force`) and for bare `git stash` or
  `git stash pop` returns no matches. A second assertion covers what a literal grep cannot: no git
  invocation composes its subcommand or flags from a variable, so a blocked form can never be built
  at runtime out of parts that each look benign.
- **Portability.** Every assertion naming `origin/main` carries co-located resolution evidence or an
  explicit portability-ok marker, so a host default-branch difference is a declared choice rather
  than an accident.
- **Edge cases.** A linked worktree passed as a target retargets to its main worktree and is not
  processed twice; two paths sharing one object store dedup by `git rev-parse --git-common-dir`; a
  `--skip` entry matching nothing emits `UnmatchedSkip:`; a repo directory name containing a literal
  backslash is not folded away; `--repos-from -` reads stdin.
- **Existing tests updated.** The three no-scope assertions in `audit-fleet.test.sh` and the
  `run_sealed` probe in `scripts/check-fleet-audit-doc-grammar.sh`, both read in Phase 4's pre-flight
  before any edit to `audit-fleet.sh`.

Validation command for every phase: `scripts/affected-tests.sh --run --explain`. That is a Linux
gate; on a Windows host run the individual suites by hand and let the Linux CI lanes decide.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| Add a `sync-canonical` operation to the audit plan JSON and ride `apply-plan.sh` | That consumer exits 2 on the whole plan for any unknown operation, so this forces a change to a verb whose contract is deliberately narrow | Switch if `apply-plan.sh` ever dispatches unknown operations per action instead of aborting the plan |
| Park with `git worktree add -b <branch>-parked <path> <branch>`, one command and no stash | Leaves the uncommitted work in the canonical checkout, which is what the goal forbids | Switch if the verb's scope narrows to clean checkouts only |
| Import `batch-common.sh` from `repo-hygiene` at runtime | Creates a horizontal dependency between two plugins that ship and version independently, and installed plugins live in separate versioned cache directories, so the path is not reachable | Switch if the marketplace grows a shared library plugin both may depend on |
| Hand-copy `batch-common.sh` into the sync skill with a comment naming the source | The copy drifts silently the first time the source is fixed | Switch never while `scripts/lib/sync-cluster.sh` exists |
| Call `worktree-create.sh` or `/source-control:worktree create` for each park | Not reachable: separate versioned cache directories, sibling-plugin reach is forbidden by the plugin philosophy, that helper's root-ladder rungs 3 and 4 are caller-supplied from `source-control`'s own option and data directory, and the skill path terminates in `EnterWorktree` | Switch if the marketplace grows a supported cross-plugin script invocation seam |
| Leave the canonical checkout detached while the park is created | A run interrupted mid-park leaves the operator on a detached HEAD with their work in a stash, which is the state hardest to recover from | Switch never |
| Fall back to `merge`, `rebase`, or a reset when `--ff-only` refuses | Silently rewrites or discards operator work, which is the loss the verb exists to prevent | Switch never; the `--reset-diverged` escape hatch is already out of scope |
| Add `--existing-branch` to `worktree-create.sh` and call it (the original Q4 answer) | Superseded: the call is not reachable, so the flag would be dead weight in another plugin | Switch if a cross-plugin invocation seam ever exists |
| Read `origin/HEAD` for the default branch instead of `ls-remote --symref` | That cache is written at fetch time and never updated, so it outlives an upstream default-branch rename | Switch if a fleet host is found whose git lacks `ls-remote --symref` |
| Give `audit` all six rungs including `cwd-*` | Turns the repository-local no-scope probe in `scripts/check-fleet-audit-doc-grammar.sh` into a report and breaks three assertions in `audit-fleet.test.sh` | Switch if those two consumers are deliberately rewritten to probe from an isolated cwd |
| Bare `git stash` and `git stash pop` | The stack is repository-wide and shared with other sessions, so index 0 is not reliably this operation's entry | Switch never |

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Adopting the resolver in `audit` changes its no-scope behavior and breaks the two consumers that parse the failure text | High | High | Phase 5 opens with a pre-flight that reads every consumer; the adoption keeps the existing message and exit code on the nothing-resolved path and suppresses the `cwd-*` rungs |
| A stash apply lands partially (a pre-existing untracked path in the park makes apply return 1 after writing content) | Medium | High | Any non-zero apply is `failed`: retain the stash entry, leave the park in place, emit the git exit code and the remedy, continue with the next repo |
| The park worktree is not at the stash's base commit, so apply conflicts | Medium | Medium | The park is created with `git worktree add --detach <path> <branch>`, so it starts at that branch's tip, which is the commit the stash was taken from since the canonical was on that branch when the stash was pushed. The canonical itself is never detached |
| A run parks work into a worktree root the operator did not intend | Low | High | The sync-owned ladder refuses rather than guessing when no usable external root resolves, and a containment or same-drive violation is caught in the pre-flight before any mutation; both surface as `skipped` or `failed` with the config remedy |
| Another live session is using the canonical checkout as its working directory while sync switches its branch | Medium | High | No claim mechanism exists for main worktrees (`git worktree lock` covers linked worktrees only), so this cannot be prevented, only disclosed. The skill body's "What this skill does NOT do" section states it, and the operator is expected to run sync when they are not mid-task in a target repository |
| A blocked git form is assembled at runtime from variables that each look benign | Low | High | A test assertion forbids composing a git subcommand or flag from a variable in either new script |
| A skip entry typo silently fails to protect a repo | Medium | High | Segment-anchored matching plus `UnmatchedSkip:` reporting, copied from the batch tier where that defect is already closed |
| A Windows path spelling reaches a native consumer unconverted | Medium | Medium | Keep POSIX form inside bash, convert only at the boundary via `scripts/emit-windows-path.sh`, never `export MSYS_NO_PATHCONV` or `MSYS2_ARG_CONV_EXCL`, and keep MSYS spellings out of suite assertions since the Windows lane is informational |
| The `sync` `allowed-tools` grant ships dead through a quoting or interpreter mismatch | Medium | Medium | `sync` joins the `SKILLS` array in `plugins/repo-fleet-hygiene/scripts/allowed-tools-pairing.test.sh` in the same phase the skill body lands |
| The resolver introduces `ghq` as a new external process the audit may spawn | Medium | Medium | Presence-gate on `command -v ghq`, invoke it with a fixed argv, and record it in the audit's `reference/security-review.md` egress surface in Phase 5 |
| Two workers edit `sync-fleet.sh` concurrently | Low | High | Phases 2 and 4 both edit that file and sit in different waves; the scope-fencing tables make it exclusive to one worker at a time |

### Phase 1: Tracer bullet, explicit-scope resolver plus dry-run sync [TODO]

The integration slice. It proves the resolver-to-sync seam, the record grammars, and the test harness
end to end before any rung or state-machine work widens either side.

- [ ] Write `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.test.sh` first, asserting: a
      single `--repo <dir>` emits exactly one stdout line `target<TAB>repo<TAB><abs-forward-slash-path><TAB>explicit`;
      a repeated `--repo` of the same directory emits one line, not two; an unknown flag exits 2; no
      argument at all exits 3 with the three remedies on stderr and nothing on stdout.
- [ ] Create `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh` with the argv surface the
      design fixes, implementing only the `explicit` rung (`<dir>...`, `--root D`, `--repo D`,
      `--repos-from FILE|-`) plus `--help`. Config, ghq, and the cwd rungs land in Phase 2; each is a
      stub that emits its `probe<TAB><rung><TAB><what was checked><TAB>not-implemented` stderr line
      so the trace shape is exercised from the start.
- [ ] Write `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.test.sh` first, asserting the
      dry-run classification of a clean, behind, default-branch fixture and the untouched-fixture
      invariants (`rev-parse HEAD`, `status --porcelain`, `stash list`, `worktree list` all
      unchanged).
- [ ] Create `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh`: argv passthrough to the
      resolver, `--dry-run` as the default and the only accepted mode in this phase, one `ff-pull`
      classification path, the `<repo-path>  <outcome>  <action>  <detail>` record, the `Summary:`
      line, and exits 0 / 2 / 3. The `detail` column carries `rung=<name>` as its first field.
- [ ] Copy in only what this phase uses from `batch-common.sh` and `clean-common.sh`
      (`batch_normalize_input`, `clean_path_key`, the git-common-dir dedup); leave a comment naming
      the source file and the reason the copy exists rather than an import.

**Sanity Check:**

- `bash plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh --repo "$(mktemp -d)"` exits 2. An
  explicit target that is not a git working tree is a caller typo, and the audit's precedent is that
  a CLI typo stops the run rather than degrading to nothing-resolved. `[EXEC-SHAPE]`
- The same command against a `git init -q -b main` directory exits 0 and its stdout matches
  `^target<TAB>repo<TAB>.*<TAB>explicit$` exactly once.
- End to end against a throwaway repo:

  ```bash
  TMP=$(mktemp -d)
  git init -q -b main --bare "$TMP/origin.git"
  git clone -q "$TMP/origin.git" "$TMP/canon"
  git -C "$TMP/canon" commit -q --allow-empty -m init
  git -C "$TMP/canon" push -q -u origin main
  bash plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh --repo "$TMP/canon"
  ```

  exits 0, prints one record whose `detail` contains `rung=explicit`, prints a `Summary:` line, and
  leaves `git -C "$TMP/canon" status --porcelain` empty.
- `bash plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.test.sh` and
  `bash plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.test.sh` each exit 0.
- `scripts/affected-tests.sh --run --explain` exits 0 and its explain output names both new suites.

### Phase 2: The full six-rung ladder [TODO]

- [ ] Extend `resolve-fleet-scope.test.sh` first, one case per rung plus the interaction rules:
      config `fleet.root` and `fleet.repo` are additive to explicit targets; `ghq` fires only when
      explicit and config are both empty; the cwd rungs fire only when explicit, config, and ghq are
      all empty; `--cwd D` overrides `$PWD`. One case encodes the acceptance criterion directly: with
      `--cwd` set to a repository that sits under a parent directly holding two repositories, the
      only record emitted is the parent as a `root` with rung `cwd-ancestor`, and no `cwd-repo`
      record appears.
- [ ] Every negative case (nothing resolves, a restricted rung set) runs with `--cwd` pointed at a
      second `mktemp -d` that holds no repositories, so a fixture repository sitting beside it in the
      first temp directory cannot satisfy the ancestor probe by accident.
- [ ] Implement the `config` rung: `--config F` wins, else `<project-dir>/.claude/repo-fleet-hygiene.conf`
      when `--project-dir D` is given, else `~/.claude/repo-fleet-hygiene.conf`. Read with
      `git config --file` and never source the file.
- [ ] Implement the `ghq` rung, presence-gated on `command -v ghq`, consuming `ghq root --all`; every
      entry becomes a `root` target. An absent binary and a binary yielding no roots emit different
      `probe` lines.
- [ ] Implement the three cwd rungs in this precedence, which the acceptance criteria fix: the
      ancestor probe runs first, so a bare run from inside a repository under a multi-repo parent
      resolves the parent as a `root`, not the one repository. `cwd-root` is the probe matching at
      level 0 (the cwd itself directly holds at least two repositories). `cwd-ancestor` is the same
      probe matching at levels 1 through 4, starting from the repository toplevel's parent when the
      cwd is inside a working tree. `cwd-repo` is the last resort: the cwd is inside a git working
      tree and no directory within four levels directly holds two or more repositories, so that
      repository's main worktree becomes a `repo` target.
- [ ] Add `--rungs <comma-list>`, which restricts the ladder to the named rungs and still emits a
      `probe` line per suppressed rung marked as such. `sync` passes nothing and gets all six;
      `audit` passes `config,ghq,cwd-root,cwd-ancestor` in Phase 4.
- [ ] Nothing resolved: exit 5, stderr carries one `probe` line per rung and the three remedies (pass
      a directory, run `repo-fleet-hygiene:setup`, install ghq).

**Sanity Check:**

- With a fixture directory holding two `git init -q -b main` repositories and `PATH` shadowing `ghq`
  with a stub that exits 1:
  `bash plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh --cwd "$FIXTURE/repo-a"` exits 0,
  stdout is exactly one line, that line ends `cwd-ancestor`, and its path field is `$FIXTURE`. The
  same command with `--cwd "$FIXTURE/solo/repo"` (a parent holding one repository) ends `cwd-repo`
  and names the repository.
- The same command with `--rungs config,ghq` exits 5, and its stderr matches
  `probe.*cwd-ancestor.*suppressed`. With `--rungs config,ghq,cwd-root,cwd-ancestor` (the audit's
  set) it exits 0 and resolves the parent, while `--cwd "$FIXTURE/solo/repo"` under that same set
  exits 5 because `cwd-repo` is suppressed.
- With a `ghq` stub printing one fixture root:
  `bash plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh --cwd "$EMPTY"` exits 0 and stdout
  ends `\tghq`; adding `--repo <fixture-repo>` to the same command yields only `explicit` records
  (`grep -c 'ghq$'` returns 0).
- `bash plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.test.sh` exits 0.

### Phase 3: The state machine, the sync-owned parking primitive, and `--apply` [TODO]

Review: code-design

- [ ] Add `scripts/sync-batch-common.sh` in the shape of `scripts/sync-hook-utils.sh`, parameterizing
      `scripts/lib/sync-cluster.sh` with source `plugins/repo-hygiene/skills/clean/scripts/lib/batch-common.sh`
      and copy target `plugins/repo-fleet-hygiene/skills/sync/scripts/lib/batch-common.sh`, plus
      `clean-common.sh` as a second copy in the same cluster. Add `scripts/sync-batch-common.test.sh`
      beside it, and wire the `--check` mode into the CI gate list where its sibling clusters sit.
      Add the explicit `scripts/affected-tests.sh` mapping that makes a change to
      `resolve-fleet-scope.sh` re-run `audit-fleet.test.sh`, since the audit now consumes it.
- [ ] Copy the audit's probe discipline into `sync-fleet.sh` and `resolve-fleet-scope.sh`: the
      fixed-argv allowlist, the subshell that unsets the inherited git selectors and exports
      `GIT_CONFIG_COUNT=0 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_NO_LAZY_FETCH=1
      GIT_OPTIONAL_LOCKS=0 GIT_PAGER=cat GIT_TERMINAL_PROMPT=0`, and the timeout wrapper with its
      GNU-timeout-or-bash-watchdog selection and its fast-timeout test switch. Every network verb
      (`ls-remote`, `fetch`, `pull`) runs under it; a timeout is `failed` with the remedy.
- [ ] Implement the sync-owned parking primitive under
      `plugins/repo-fleet-hygiene/skills/sync/scripts/lib/`: the three-rung root ladder
      (`--worktree-root`, then `melodic.worktreeroot` read after a `rev-parse --git-dir` gate with
      includes on and last-value-wins, then a `--data-root-file` the SKILL.md writes), the
      `<root>/<owner>-<repo>-<slug>` naming with the same slug sanitization the convention documents,
      and the park lock with reason
      `parked by repo-fleet-hygiene:sync on <host> at <utc>; git worktree unlock <path> to remove`,
      whose unlock remedy is printed in the record.
- [ ] Implement the pre-flight, which runs before any mutation for a repository that would park: the
      root resolves; the root is not inside any repository; on Windows the root is on the
      repository's drive (cross-drive is `skipped` with the config remedy); the park path is free;
      there is no in-progress merge, rebase, or cherry-pick; the repository is not a submodule
      superproject.
- [ ] Extend `sync-fleet.test.sh` first with one dry-run case per row of the design's state table,
      then one `--apply` case per acceptance criterion, then the failure cases. Assertions are the
      ones listed in the test strategy.
- [ ] Add the bounded discovery walk under a `root` target, adapted from `audit-fleet.sh`:
      configurable depth (default 5, bounded 1 to 12), the nested-repository early return, no descent
      into symlinks or junctions, tolerance of unreadable directories, and dedup by
      `git rev-parse --path-format=absolute --git-common-dir` with linked worktrees retargeted to
      their main worktree through the `worktree list --porcelain -z` first record.
- [ ] Add the segment-anchored `--skip ENTRY` / `--skip-from FILE` ledger and `UnmatchedSkip:`
      reporting.
- [ ] Implement remote selection and classification. The remote is the current branch's configured
      remote, else `origin`, else the sole remote; none of those and the repository is `skipped`. The
      default branch comes from `git ls-remote --symref <remote> HEAD`, never from the local
      `<remote>/HEAD` cache. "Unpushed" is `rev-list --count @{u}..HEAD` when an upstream resolves;
      when the upstream ref is gone (an upstream default renamed away) compare against
      `<remote>/<branch>` if that exists, else treat the branch as unpushed and park it. Dry-run
      fetches by default, which writes only refs and objects under `.git`; `--no-fetch` is the
      offline form, and any classification resting on a stale or missing tracking ref carries
      `provisional` in its record.
- [ ] Implement the actions:
  - `ff-pull`: `git pull --ff-only`.
  - `switch+ff-pull`: `git switch <default>` then `git pull --ff-only`; no worktree created and the
    local branch ref survives.
  - Dirty on the default branch: attempt `ff-pull` first. A dirty file the incoming commits do not
    touch is carried across untouched, so this succeeds without a park most of the time. Only when
    git refuses because a dirty path would be overwritten does it become `park-dirty-default`, whose
    park branch is a new `park/<UTC yyyymmdd-HHMM>-<7-char sha>`.
  - `park-branch` and `park-dirty-default` share one round-trip, and the canonical is never detached:
    pre-flight, then `git stash push -u -m sync-park-<uuid>` (skipped when the tree is clean), then
    capture the entry's SHA by marker (`git stash list --format='%gd %gs'`, take the first field of
    the matching row and resolve it), then `git worktree add --detach <park-path> <branch>` with no
    `--force`, then `git stash apply --index <sha>` in the park, then `git switch <default>` in the
    canonical (or `git switch -c <default> --track <remote>/<default>` when no local default branch
    exists), then `git switch <branch>` in the park, then re-find the stash by marker, assert the SHA
    at that index still equals the captured SHA, and `git stash drop stash@{n}` (drop refuses a raw
    SHA, so the index form is required), then `ff-pull`.
- [ ] Implement the failure posture. A failure before the canonical switch restores with
      `git stash apply --index <sha>` in the canonical, drops the entry by the same re-find-and-assert
      discipline, reports `failed`, and removes the park only when this run created it and it is
      clean. A failure after the canonical switch reports `failed` and names the park path where the
      work now lives. `pull --ff-only` exit 1 or 128, an `ls-remote` or `fetch` failure or timeout, a
      dubious-ownership refusal, a `worktree add` exit 128, a `stash push` that leaves no entry
      matching the marker, a park path that already exists, and a non-zero stash apply each emit a
      `failed` record naming the repository, the git exit code, and the remedy, then continue with
      the next repository. `safe.directory` is never written; the remedy is printed.
- [ ] Assert post-conditions after every mutating step: the symbolic ref of HEAD equals the intended
      target and `status --porcelain` matches the expected shape. A mismatch is `failed`.
- [ ] Implement the mode gate in the shape of the batch tier and aligned with the `apply` sibling:
      `--dry-run` is the default, `--apply` opts into mutation behind one batch-wide confirmation,
      and `--yes` supplies non-interactive consent. Exit codes: 0 success, 2 usage, 3 gate abort or
      non-interactive `--apply` without `--yes`, 4 one or more repositories failed, 5 nothing
      resolved. Note that `--repos-from -` consumes stdin and so makes the session non-interactive,
      which means `--apply` with it always needs `--yes`.

**Sanity Check:**

- `grep -nE 'reset --hard|clean -f|checkout \.|restore \.|checkout -f|switch -f|--discard-changes|push --force|git stash pop|git stash$' plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh`
  returns no matches (exit 1).
- `grep -c 'ls-remote --symref' plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh` returns
  at least 1, and `grep -c 'symbolic-ref refs/remotes' plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh`
  returns 0.
- Against a throwaway clone that is clean and behind its bare origin,
  `bash plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh --repo "$TMP/canon" --apply --yes`
  exits 0 and `git -C "$TMP/canon" rev-parse HEAD` equals `git -C "$TMP/canon" rev-parse origin/main`.
- Against a throwaway clone on a non-default branch with one tracked edit and one untracked file,
  the same command exits 0, `git -C "$TMP/canon" branch --show-current` prints the default branch,
  `git -C "$TMP/canon" stash list` is empty, and the park directory named in the record contains both
  the edit and the untracked file.
- Against a diverged clone the same command exits 4, its record line contains `failed`, and
  `git -C "$TMP/canon" rev-parse HEAD` is unchanged from the pre-run capture. At no point during any
  of these runs does `git -C "$TMP/canon" symbolic-ref -q HEAD` fail, which is the assertion that the
  canonical is never detached.
- `grep -nE 'switch --detach|checkout --detach' plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh`
  returns no matches (exit 1); the only detach is `worktree add --detach`.
- `bash scripts/sync-batch-common.sh --check` exits 0, and
  `bash scripts/sync-batch-common.sh --print-manifest` lists the source and both copies.
- `bash plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.test.sh` and
  `bash scripts/sync-batch-common.test.sh` each exit 0.
- `scripts/affected-tests.sh --explain` on a change to
  `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh` names `audit-fleet.test.sh` in its
  selection.

### Phase 4: `audit` adopts the resolver as its no-scope fallback [TODO]

- [ ] **Pre-flight consumer check (first work item).** List and read every consumer that parses the
      audit's no-scope failure text or exit code:
      `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh` (the zero-config
      no-scope case, the remedy-naming case, the project-directory case, and the scopeless-config
      case), `scripts/check-fleet-audit-doc-grammar.sh` (its `run_sealed` probe requires a non-zero
      stop containing `no scope resolved`, requires one of the two remedy-block headings, requires
      that no report is produced, and harvests the indented `--<flag>` forms from the remedy block
      into the documented argument grammar), and `scripts/check-fleet-audit-doc-grammar.test.sh`
      (which fixtures that text). Record, per consumer, exactly which string and which exit code it
      depends on. Both probes run from the caller's working directory, which is this repository, a
      git working tree, so a `cwd-*` rung reached from the audit would turn the probe into a
      successful report.
- [ ] Wire the fallback in `audit-fleet.sh` so the resolver's targets are appended to `ROOT_ARGS` and
      `REPO_ARGS` **before** `CLI_ROOT_COUNT` and `CLI_REPO_COUNT` are snapshotted, so both the
      discovery walk and the scope-provenance accounting see them. Call
      `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh` with the audit's own `--config` and
      `--project-dir` values and with the rung set `config`, `ghq`, `cwd-root`, `cwd-ancestor`, and
      not `cwd-repo`: the audit's unresolved-scope branch exists precisely to refuse a single
      incidental checkout as fleet scope, while a directory that directly holds two or more
      repositories is fleet scope by construction. A resolver root that does not exist on disk is
      dropped, so a stale ghq root never becomes scope. The
      audit captures both the resolver's stdout and its stderr and forwards neither on the
      nothing-resolved path: the doc-grammar checker harvests the indented `--<flag>` forms out of
      the audit's own remedy block into the documented argument grammar, so a probe line or a
      resolver-only flag reaching that output would silently widen the grammar the audit is held to.
      When the resolver returns nothing, fall through to the existing rejection unchanged, so the
      message text, the remedy block, and the exit code all stay exactly as they are.
- [ ] Add a `resolver (<rungs>)` segment to `SCOPE_PROVENANCE`, beside the existing command-line and
      config segments, so a report never attributes resolver-supplied scope to the command line.
- [ ] Keep the audit's `allowed-tools` grant unchanged. The resolver is invoked by the script, not by
      Claude, so no new grant is introduced.
- [ ] Record `ghq` in `plugins/repo-fleet-hygiene/skills/audit/reference/security-review.md` as a
      newly reachable external process, with the presence gate, the fixed-argv allowlist, and the env
      pinning that bound it, alongside the resolver itself as a new callee.
- [ ] Extend `audit-fleet.test.sh` with the adoption cases: with a `ghq` stub printing a fixture root
      and no other scope, a bare run discovers the fixture repositories; with a `ghq` stub that exits
      non-zero and no other scope, the run still fails with the existing message and exit code.
- [ ] Update the two no-scope probes so they still mean what they say. Both run from the caller's
      working directory, which is this repository, so with `cwd-root` and `cwd-ancestor` live they
      would resolve scope and stop failing. Each probe moves to a directory nested at least five
      levels inside a fresh `mktemp -d` (deeper than the four-level ancestor bound, and with no
      sibling repositories to find), and each stubs `ghq` absent by prepending a fixture `bin` to
      `PATH`. That covers `audit-fleet.test.sh`'s zero-config, project-directory, and
      scopeless-config cases and `run_sealed` in `scripts/check-fleet-audit-doc-grammar.sh`, whose
      sealed environment currently preserves `PATH="$PATH"` and stubs nothing, so the checker would
      otherwise pass on CI (no ghq installed) and fail on any fleet host that has ghq. These edits go
      through the user-approval gate.

**Sanity Check:**

- `bash plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh` exits 0.
- `bash scripts/check-fleet-audit-doc-grammar.sh` exits 0 and
  `bash scripts/check-fleet-audit-doc-grammar.test.sh` exits 0, both on a host with `ghq` installed
  and on one without. `git diff scripts/check-fleet-audit-doc-grammar.sh` touches only `run_sealed`
  and its cwd, and `git diff scripts/check-fleet-audit-doc-grammar.sh | grep -c '^+.*ghq'` returns at
  least 1.
- From a directory nested five levels inside a fresh `mktemp -d`, with `HOME` and
  `CLAUDE_PROJECT_DIR` pointed at empty fixture directories and a `ghq` stub on `PATH` that exits 1,
  `bash plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh` exits 2 and its output
  contains `no scope resolved`.
- `grep -c 'cwd-repo' plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh` returns at
  least 1 (the exclusion is stated in the call, not implied), and a run whose only possible scope is
  a single incidental checkout still exits 2.
- A run with a `ghq` stub printing a fixture root produces a report whose scope-provenance line names
  `resolver`.
- `grep -Fq ghq plugins/repo-fleet-hygiene/skills/audit/reference/security-review.md` succeeds.

### Phase 5: Skill surface, registration, and release notes [TODO]

- [ ] Write `plugins/repo-fleet-hygiene/skills/sync/SKILL.md` in the shape of the `apply` sibling:
      a trigger-phrase-bearing `description`, `user-invocable: true`, the confirmation-gate table
      restated with sync's own exit codes (0 success, 2 usage, 3 gate abort or non-interactive
      `--apply` without `--yes`, 4 one or more repositories failed, 5 nothing resolved),
      `disable-model-invocation: true`, an `argument-hint` covering
      `[<dir>]... [--root <dir>]... [--repo <dir>]... [--repos-from <file>|-] [--config <file>] [--project-dir <dir>] [--max-depth <1..12>] [--skip <entry>]... [--skip-from <file>] [--worktree-root <dir>] [--no-fetch] [--dry-run|--apply] [--yes]`,
      a single `allowed-tools` grant `Bash(${CLAUDE_SKILL_DIR}/scripts/sync-fleet.sh:*)` paired with
      the literal invocation in the body, a non-negotiable boundary section, the confirmation-gate
      table, and a "What this skill does NOT do" section that includes the disclosure that sync
      cannot detect another live session using a canonical checkout as its working directory, because
      git offers no claim mechanism for main worktrees. Present tense, the rule with its reason, no
      issue or pull-request numbers, no incident narration.
- [ ] The skill body writes the `--data-root-file` the parking ladder's third rung reads, carrying
      `${CLAUDE_PLUGIN_DATA}/worktrees`, and passes it on every invocation. State the operator-setup
      boundary for `melodic.worktreeroot` in the body, citing
      `plugins/source-control/reference/worktree-root-convention.md` rather than copying a path.
- [ ] Add a `## Next` section to the new skill body naming its successor, and add a `## Next` to
      `plugins/repo-fleet-hygiene/skills/audit/SKILL.md` in the bullet form, naming both
      `/repo-fleet-hygiene:apply` (a plan was written) and `/repo-fleet-hygiene:sync` (canonical
      checkouts are off their default branch). Neither audit nor apply carries a `## Next` today, so
      the predecessor edit is authoring work rather than a substitution.
- [ ] Create `plugins/repo-fleet-hygiene/skills/sync/evals/evals.json` alongside the sibling skills'
      eval files, so `skill-quality:check` finds the surface it expects.
- [ ] Add `sync` to the `SKILLS` array in
      `plugins/repo-fleet-hygiene/scripts/allowed-tools-pairing.test.sh`.
- [ ] Bump `plugins/repo-fleet-hygiene/.claude-plugin/plugin.json` to the next minor version, extend
      its `description` and `keywords` to name the sync verb, and add the matching `## [<version>]`
      entry to `plugins/repo-fleet-hygiene/CHANGELOG.md`.
- [ ] Update the `repo-fleet-hygiene` entry in `.claude-plugin/marketplace.json`: `tags` only. Adding
      a skill to an existing plugin needs no new marketplace entry (skills are discovered under
      `plugins/<plugin>/skills/<name>/SKILL.md`) and the category is unchanged, so the
      catalog-taxonomy rule's read requirement is not triggered.
- [ ] Update `plugins/repo-fleet-hygiene/README.md` to describe the third verb and the resolver, and
      state the operator-setup boundary for the permission grant per the permission-rule-hygiene
      convention.

#### File Inventory

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/repo-fleet-hygiene/skills/sync/SKILL.md` | CREATE | The skill surface itself |
| [ ] `plugins/repo-fleet-hygiene/skills/sync/evals/evals.json` | CREATE | Eval surface the sibling skills carry |
| [ ] `plugins/repo-fleet-hygiene/skills/audit/SKILL.md` | MODIFY | Gains a `## Next` naming the sync verb |
| [ ] `plugins/repo-fleet-hygiene/scripts/allowed-tools-pairing.test.sh` | MODIFY | `SKILLS` array gains `sync` |
| [ ] `plugins/repo-fleet-hygiene/.claude-plugin/plugin.json` | MODIFY | Minor version bump, description and keywords |
| [ ] `plugins/repo-fleet-hygiene/CHANGELOG.md` | MODIFY | New version entry required by the parity gate |
| [ ] `plugins/repo-fleet-hygiene/README.md` | MODIFY | Third verb, the resolver, operator-setup boundary |
| [ ] `.claude-plugin/marketplace.json` | MODIFY | `tags` only; category and entry shape unchanged |
| [ ] `plugins/repo-fleet-hygiene/skills/apply/SKILL.md` | KEEP | Audited; it carries no `## Next` today and sync is not its successor, so adding one is separate authoring work outside this change |
| [ ] `plugins/repo-fleet-hygiene/skills/setup/SKILL.md` | KEEP | Audited; the config grammar it documents is unchanged by this work |
| [ ] `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh` | KEEP | Landed in Phases 1 to 3; this phase only pairs the grant to it |
| [ ] `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh` | KEEP | Plugin-level, not skill-bundled, so it carries no grant of its own |
| [ ] `plugins/repo-fleet-hygiene/skills/sync/scripts/lib/batch-common.sh` | KEEP | A synced copy owned by `scripts/sync-batch-common.sh`; edited only at its source |
| [ ] `plugins/source-control/**` | KEEP | Audited; the scope change removed every edit to this plugin, and `reference/worktree-root-convention.md` is consumed as documentation only |

**Sanity Check:**

- `bash plugins/repo-fleet-hygiene/scripts/allowed-tools-pairing.test.sh` exits 0 and its output
  contains a `PASS` line naming `sync`.
- `grep -c 'CLAUDE_SKILL_DIR}/scripts/sync-fleet.sh' plugins/repo-fleet-hygiene/skills/sync/SKILL.md`
  returns at least 2 (the frontmatter grant and the body invocation, quoted identically).
- `grep -nE '#[0-9]{3,}' plugins/repo-fleet-hygiene/skills/sync/SKILL.md` returns no matches
  (exit 1).
- `grep -c '^## Next$' plugins/repo-fleet-hygiene/skills/sync/SKILL.md` returns 1 and the same
  command against `plugins/repo-fleet-hygiene/skills/audit/SKILL.md` returns 1.
- `bash scripts/check-changelog-parity.sh --check` exits 0.
- `python -c "import json,sys; json.load(open('.claude-plugin/marketplace.json'))"` exits 0.
- `bash scripts/check-skill-portability.sh` exits 0.
- `/skill-quality:check sync` reports PASS with no blocking finding.
- `git status --porcelain plugins/source-control/` is empty across the whole change set.
- `scripts/affected-tests.sh --run --explain` exits 0.

### Phase 6: File the tree-batch scope-inference follow-up [TODO]

Zero-argument scope inference for `repo-hygiene:clean tree-batch` is out of scope here and is
recorded as a tracker item so it is not lost.

- [ ] **Phase-entry check** (first work item, verifies no duplicate exists):

  ```bash
  gh issue list --state all --search 'tree-batch scope inference in:title' --json number,title,state
  ```

- [ ] **If the search returns a match** pivot to a comment on the existing item naming the resolver's
      path and the two grammars it would have to bridge, instead of creating a duplicate. Skip the
      remaining create steps and close the phase with the comment URL as evidence.
- [ ] **If the search returns empty** create the item:

  ```bash
  gh issue create --title 'repo-hygiene: tree-batch zero-argument scope inference' --body '<body>' --label 'enhancement'
  ```

  The body names: the shared resolver at `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh`
  as the reference implementation; the reason `repo-hygiene` cannot import it (plugins stay
  horizontally decoupled, so this is a copy or a promotion to a shared surface, not a dependency);
  and the two skip grammars that would have to be reconciled.

- [ ] **Sanity Check:** the item number (created or pivoted-to) and its URL recorded in the phase
      notes; `gh issue view <N> --json title,state` exits 0.

### Execution-Shape Analysis

#### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh`, `.../resolve-fleet-scope.test.sh`, `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh`, `.../sync-fleet.test.sh` | 2 (resolver), 3 (sync) |
| 2 | `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh`, `.../resolve-fleet-scope.test.sh` | 1, 3 (Phase 3 adds the env pinning and allowlist to the same file) |
| 3 | `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh`, `.../sync-fleet.test.sh`, `plugins/repo-fleet-hygiene/skills/sync/scripts/lib/*`, `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh`, `scripts/sync-batch-common.sh`, `scripts/sync-batch-common.test.sh`, `scripts/affected-tests.sh` | 1, 2 |
| 4 | `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh`, `.../audit-fleet.test.sh`, `plugins/repo-fleet-hygiene/skills/audit/reference/security-review.md`, `scripts/check-fleet-audit-doc-grammar.sh` | 5 (audit `SKILL.md` is a different file in the same skill directory) |
| 5 | `plugins/repo-fleet-hygiene/skills/sync/SKILL.md`, `.../sync/evals/evals.json`, `plugins/repo-fleet-hygiene/skills/audit/SKILL.md`, `plugins/repo-fleet-hygiene/scripts/allowed-tools-pairing.test.sh`, `plugins/repo-fleet-hygiene/.claude-plugin/plugin.json`, `plugins/repo-fleet-hygiene/CHANGELOG.md`, `plugins/repo-fleet-hygiene/README.md`, `.claude-plugin/marketplace.json` | 4 (same skill directory, disjoint files) |
| 6 | none (tracker only) | none |

#### Dependency graph

- Phase 1 gates everything: it creates both scripts and both suites.
- Phase 2 widens the resolver only.
- Phase 3 needs Phase 2 (it adds the probe hardening to the resolver too, and it consumes the full
  ladder) and touches the resolver file, so it cannot run beside Phase 2.
- Phase 4 needs Phase 2, because the rung set it adopts is what Phase 2 implements. It is
  file-disjoint from Phase 3.
- Phase 5 needs Phase 3, because the grant it pairs must match the invocation the finished script
  takes, and it edits a file in the same skill directory Phase 4 touches.
- Phase 6 is independent of everything and is last only so the follow-up body can cite the resolver's
  final path.
- Integration-first ordering: Phase 1 is the integration slice and precedes every widening.
- The scope change removed the only phase that was file-disjoint from the resolver work, so the plan
  is now nearly sequential: exactly one pair, Phases 3 and 4, can run together.

#### Recommended shape

> Phase 1 (main session) then Phase 2 (worker) then
> Wave A (parallel workers, single message): Phase 3, Phase 4 then
> Phase 5 (main session, after Wave A returns) then Phase 6 (main session).
>
> Cost note: two worker dispatches in Wave A plus one for Phase 2, three in total. Only Wave A
> multiplies token usage against a sequential run, and it does so for one pair; the user picks
> consciously.

#### Scope-fencing tables

Phase 2 runs alone, so it needs no fence beyond its ALLOWED list:
`plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh` and its suite, roughly 250 lines.

Wave A:

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| A1 | 3 | `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.sh`, `plugins/repo-fleet-hygiene/skills/sync/scripts/sync-fleet.test.sh`, `plugins/repo-fleet-hygiene/skills/sync/scripts/lib/**`, `plugins/repo-fleet-hygiene/scripts/resolve-fleet-scope.sh`, `scripts/sync-batch-common.sh`, `scripts/sync-batch-common.test.sh`, `scripts/affected-tests.sh` | ~650 |
| A2 | 4 | `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.sh`, `plugins/repo-fleet-hygiene/skills/audit/scripts/audit-fleet.test.sh`, `plugins/repo-fleet-hygiene/skills/audit/reference/security-review.md`, `scripts/check-fleet-audit-doc-grammar.sh` | ~150 |

A1 and A2 both touch the resolver's behavior but only A1 may edit its file; A2 consumes it as a CLI.
Neither may touch `plugins/source-control/`, which this change set leaves untouched.

**Each agent FORBIDDEN:** any file outside its ALLOWED list; `docs/topics/fleet-sync/PLAN.md` (the
main session edits phase status only); the other agent's territory; and staging, committing, or
pushing outside its own worktree branch.

**Each agent reports at end:** work items completed, a per-criterion Sanity Check verdict with the
command output that produced it, and the actual line-count delta.

**Divergence escalation (copy into every worker brief verbatim):**

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief —
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task — STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

#### Sequential fallback

> If a scope-fence violation, a concurrent-edit race, or a cannot-complete report arrives, abort that
> agent and fall back to sequential 1 to 2 to 3 to 4 to 5 to 6 for the affected phase only; the
> other agent in Wave A continues.

#### Per-phase routing table

Execution runs through `/implementation:implement-dispatch` with Opus worker subagents, each in its
own worktree; the main session verifies every return against direct evidence rather than the worker's
summary.

| Phase | Surface | Basis |
|---|---|---|
| 1 | main session | The integration slice fixes two record grammars and the harness shape that every later phase copies; getting it wrong is expensive and it is judgment-heavy |
| 2 | sub-agent worker | Mechanical rung-by-rung widening of one file behind a suite written first |
| 3 | sub-agent worker | The largest mechanical volume in the plan, with the state table, the park round-trip, the parking ladder, and the failure posture all fully specified here |
| 4 | sub-agent worker | Bounded edit at one branch point in an existing script, with the consumer pre-flight list already enumerated |
| 5 | main session | Skill body wording, the grant pairing, the version and changelog decisions, and the marketplace touch all need judgment against the repo's rules |
| 6 | main session | A tracker write with a search-before-create gate and a human-readable body |

#### Token-cost note

Three worker dispatches, two of them concurrent. Each worker reads only this PLAN.md plus the memory
slice under `.work/fleet-sync/`, so the per-worker read cost is bounded and the file dumps never
reach the main conversation. A fully sequential run costs modestly fewer tokens and takes longer in
wall-clock; only Wave A's pair is genuinely disjoint, and the user picks consciously.

### Decisions made (gate-passed)

Three rows are marked USER-RESERVED: they reverse or revise a briefed answer and are the operator's
call at the plan gate, not this plan's.

| Decision | What it changes in the plan | Basis (evidence) |
|---|---|---|
| `[FALLBACK — confirm or override]` **USER-RESERVED (A).** Parking is sync-owned; `plugins/source-control/` takes no code change | The whole `--existing-branch` phase is deleted, Phase 3 grows the root ladder, pre-flight, naming, and lock claim, and the phase count drops from seven to six | The cross-plugin call is unreachable: installed plugins live in separate versioned cache directories, `docs/PLUGIN-PHILOSOPHY.md` forbids reaching into a sibling plugin's files, `worktree-create.sh`'s root-ladder rungs 3 and 4 are caller-supplied from `source-control`'s own plugin option and data directory, and `/source-control:worktree create` terminates in `EnterWorktree`. The remaining coupling is the documented `melodic.worktreeroot` convention |
| `[FALLBACK — confirm or override]` **USER-RESERVED (E).** `audit` adopts `config`, `ghq`, `cwd-root`, and `cwd-ancestor`, but not `cwd-repo`; `sync` keeps all six | Phase 2 drops the `--no-cwd` flag in favor of a rung set; Phase 4 states the exclusion; the Brief gains an acceptance criterion naming the divergence | The audit's unresolved-scope branch exists to refuse a single incidental checkout as fleet scope, and that reason does not extend to a directory that directly holds two or more repositories. Suppressing all three cwd rungs would have been stricter than the rule requires |
| `[FALLBACK — confirm or override]` **USER-RESERVED (H).** A dirty checkout already on the default branch tries `pull --ff-only` first and parks only when git refuses | Phase 3's action list leads with the attempt; the Brief's dirty-default acceptance criterion is struck and replaced; the interview ledger's Q6 row is annotated | The research handoff records that `--ff-only` is safe to attempt blind and that a dirty file the incoming commits do not touch is carried across untouched. Parking unconditionally creates worktree sprawl for the common case |
| `[EXEC-SHAPE]` The park round-trip never detaches the canonical; the only detach is `git worktree add --detach` | Phase 3 restates the ordering with the canonical switch and the park switch as distinct steps, adds the restore-on-failure path, and the risk row's mechanism text is corrected | A run interrupted mid-park would otherwise leave the operator on a detached HEAD with their work in a stash. `worktree add --detach <path> <branch>` puts the park at that branch's tip, which is the stash's base commit, without touching the canonical's HEAD |
| `[EXEC-SHAPE]` The stash is dropped by re-found index after asserting the SHA at that index still matches the captured SHA | Phase 3 spells out the drop discipline in both the success and the restore paths | `git stash drop` refuses a raw SHA, so an index form is required; the stack is repository-wide, so the index may have shifted between the push and the drop |
| `[EXEC-SHAPE]` Remote selection is the branch's configured remote, then `origin`, then the sole remote, else `skipped` | Phase 3 implements it; the Brief gains the no-remote acceptance criterion; the design's state table drops its hardcoded `origin` | A fleet contains clones whose remote is not named `origin`, and the design fixed `origin` only as shorthand |
| `[EXEC-SHAPE]` Both new scripts take the audit's env pinning, fixed-argv allowlist, and timeout wrapper; every network verb runs under them | Phase 3 gains those three work items and an offline plus timeout test pair | The audit already solved this for the same class of process on the same fleet; a fleet verb that can hang on one unreachable remote is unusable |
| `[EXEC-SHAPE]` `batch-common.sh` and `clean-common.sh` arrive through a new `scripts/sync-batch-common.sh` cluster wrapper rather than a hand copy | Approach item 2 and Phase 3 replace the copy list with the wrapper; a new suite and a CI `--check` gate come with it | `scripts/sync-hook-utils.sh` parameterizes `scripts/lib/sync-cluster.sh` for exactly this problem, and its `--print-manifest` mode is what `scripts/affected-tests.sh` reads to keep a copy's dependents selected |
| `[EXEC-SHAPE]` Dry-run fetches by default, with `--no-fetch` for offline and a `provisional` marker on any classification resting on a stale or missing tracking ref | Phase 3's classification item; the design's input line; a new offline test | A fetch writes only refs and objects under `.git`, so every mutates-nothing invariant the dry-run tests assert (HEAD, `status --porcelain`, the stash stack, the worktree list) still holds, and a plan computed against a stale tracking ref is worse than one that fetched |
| `[EXEC-SHAPE]` Resolver targets are appended before `CLI_ROOT_COUNT` is snapshotted, and a `resolver (<rungs>)` segment joins `SCOPE_PROVENANCE` | Phase 4 names the insertion point and the provenance segment | The counts snapshotted at that point are what decide per-entry failure semantics and what the report attributes scope to; appending after them would make resolver scope look command-line-supplied and change its failure unit |
| `[EXEC-SHAPE]` Deferred Q6's naming resolves to `park/<UTC yyyymmdd-HHMM>-<7-char sha>`, the sha being the canonical checkout's HEAD at park time | Phase 3 passes exactly this string as the new park branch; its sanity check asserts `^park/[0-9]{8}-[0-9]{4}-[0-9a-f]{7}$` | The design resolution fixes `park/<utc-date>-<short-sha>`. The chosen form is 26 characters over two segments, each restricted to letters, digits, dots, underscores, and dashes, so it passes `git check-ref-format --branch`. UTC removes the ambiguity a local-time stamp carries across a multi-machine fleet, and minute precision distinguishes two parks of the same commit in one session. The disposition around it is the separately gated Q6 revision |
| `[EXEC-SHAPE]` Deferred Q14 resolves to no new flag: the `detail` column carries `rung=<name>` as its first field | Phase 1 emits `rung=` in `detail`; the Phase 1 sanity check greps for it; no reporting flag appears in any argv list | The design resolution already states that `detail` carries the source rung and fixes the six rung values. A flag would add an argv surface the acceptance criteria do not list |
| `[EXEC-SHAPE]` One exit-code table across the plugin's three verbs: for `sync`, 0 success, 2 usage, 3 gate abort or non-interactive `--apply` without `--yes`, 4 one or more repositories failed, 5 nothing resolved; for the resolver, 0 / 2 / 5 | Phase 3's mode gate, Phase 5's gate table, the resolver's exit 5 in Phases 1 and 2, and the design's new exit-code section | The `apply` sibling already fixes 3 for the gate abort and 4 for failed mutations, so sync matching it keeps one mental model across the plugin, and 5 is free for the nothing-resolved case the design introduced. `sync` also adopts `--yes` for non-interactive consent from that same sibling. The audit's use of 2 for nothing-resolved is pre-existing and left alone |
| `[EXEC-SHAPE]` `sync` frontmatter carries `disable-model-invocation: true` | Phase 5's skill body matches the `apply` sibling rather than the read-only `audit` | `apply` states the reason a mutating verb is a separate, model-uninvocable skill: a grant that matches any argv on a script must not silently widen mutation authority |
| `[EXEC-SHAPE]` `sync` writes its own `## Next`, and `audit` gains one naming `/repo-fleet-hygiene:sync` | Phase 5 adds a section to a file that has none today | The skill-bodies rule requires a new skill to write its own `## Next` and to edit the predecessor whose `## Next` should now name it; neither `audit` nor `apply` carries one |
| `[EXEC-SHAPE]` `.claude-plugin/marketplace.json` changes `tags` only; no new entry, no category change | Phase 5 states the marketplace touch precisely and does not open `docs/CATALOG-TAXONOMY.md` | Skills are discovered under `plugins/<plugin>/skills/<name>/SKILL.md`, so adding one needs no manifest entry; the catalog-taxonomy rule's read requirement fires on assigning, renaming, or merging a category, none of which happens |
| `[EXEC-SHAPE]` Only `repo-fleet-hygiene` takes a version bump, with its matching changelog entry, in Phase 5 | The `source-control` bump and changelog entry are gone with Phase 3's deletion | `scripts/check-changelog-parity.sh --check-bump` fails a manifest version change with no new `## [<version>]` entry, and `source-control` no longer changes at all |
| `[EXEC-SHAPE]` The three cwd rungs are ordered ancestor-probe-first, with `cwd-repo` as the last resort | Phase 2 defines `cwd-root` as the probe matching at level 0 and `cwd-ancestor` as levels 1 to 4, and adds a test case plus a sanity check for the parent-resolves case | The acceptance criteria require a bare run from inside a repository under a multi-repo parent to resolve the parent as a root; a `cwd-repo`-first order would emit the single repository and never reach the parent |
| `[EXEC-SHAPE]` An explicit `--repo` or `--root` naming a path that is not a git working tree exits 2, not 3 | Phase 1's first sanity check asserts exit 2 | The audit treats a CLI path typo as a hard stop and degrades only config-supplied entries; matching that keeps one behavior across the two scripts in one plugin |
| `[FALLBACK — confirm or override]` Every existing no-scope assertion gains a `PATH`-shadowing `ghq` stub that exits non-zero, including the sealed environment in `scripts/check-fleet-audit-doc-grammar.sh` | Phase 4 lists this as a work item over tests the phase did not otherwise need to touch, and its sanity check predicts a single hunk in the checker rather than an unmodified file | Once the audit consults a presence-gated tool, an assertion that means "no rung resolved" is otherwise satisfied only by the accident of `ghq` being absent on the running host. The checker's sealed environment preserves the caller's `PATH` and stubs nothing, so it would pass on CI and fail on any fleet host that has ghq installed |
| `[FALLBACK — confirm or override]` The audit captures and discards the resolver's stdout and stderr on the nothing-resolved path | Phase 4 states the capture explicitly rather than letting the resolver's probe trace reach the audit's output | The doc-grammar checker harvests indented `--<flag>` lines out of the audit's failure output into the argument grammar it enforces, so a forwarded resolver-only flag or probe line would silently widen that grammar |
| `[FALLBACK — confirm or override]` Phase 6's tracker write is gated by a search-before-create step with an explicit pivot-to-comment path | Phase 6 is shaped as a phase-entry check rather than a bare create call | The plan template requires that shape for any phase ending in a tracker write; the brief records the follow-up but not how to avoid duplicating it |

### Blast radius

Blast radius: HIGH. This change adds a mutating verb that runs across every canonical repository an
operator owns and changes the scope resolution of the existing `audit` verb, so a defect in either
surface reaches many working trees at once rather than one.

Stress-test triggers matched from
`skills/plan/context/stress-test-triggers.md`: an architecture decision affecting multiple projects
(a shared resolver adopted by an existing skill, and a parking primitive built against another
plugin's documented convention); a multi-step implementation with more than three steps touching
behavior that needed dedicated research (cross-worktree stash apply, `--ff-only` exit-code semantics,
`worktree add` refusal); and a change to a contract other code parses (the audit's no-scope failure
text and its scope-provenance line, with two consumers).

Not CRITICAL, and the reason is narrower than it first appears. The code is revertable by a normal
revert, but the *state* a run leaves on an operator's disk is not, so the claim rests on the run's
own guarantees rather than on git history: no force, reset, or discard form is ever emitted; every
failure is skip-and-report with the stash entry retained and the park left in place; and, since the
park order was corrected, the canonical checkout is never detached, so an interrupted run leaves the
operator on a real branch with their work either in place or in a named park, never on a detached
HEAD with the only copy in a stash. `/planning:devils-advocate` is warranted before implementation
begins.

### Stress-test summary

Pending. Blast radius is HIGH and three triggers match, so `/planning:devils-advocate` runs against
this plan before Phase 1 starts, focused on the three surfaces the research and the pre-flights
flagged: the stash round-trip across worktrees, the audit's adopted fallback and its two text-parsing
consumers, and the failure posture's promise that a partial apply always leaves the stash entry and
the park behind.

### Open questions

- Whether `repo-fleet-hygiene:setup` should learn to write a `melodic.worktreeroot` entry so parking
  has a root on a fresh machine, or whether refusing with the remedy is the right operator signal.
  Left as is for now: the refusal is surfaced with the remedy.
- Whether the resolver eventually moves to a shared surface several plugins may depend on, which is
  what Phase 6's follow-up would want. Out of scope here.
- Whether `plugins/source-control` should eventually publish the worktree-root ladder as a callable
  seam, which would let a future sync drop its own copy. Not proposed here; the copy is small and the
  convention document is the contract.

### Handoff to implementation

#### User-approval gates

- **Before Phase 1 starts**, the three USER-RESERVED rows in the decisions table, because each
  reverses or revises an answer the interview locked: A (parking is sync-owned, `source-control`
  untouched), E (the audit's rung set excludes only `cwd-repo`), and H (a dirty default-branch
  checkout tries the fast-forward before it parks).
- Before Phase 4 starts, the remaining `[FALLBACK — confirm or override]` rows, and specifically the
  edits to `scripts/check-fleet-audit-doc-grammar.sh` and the three no-scope cases in
  `audit-fleet.test.sh`, since those files are otherwise outside this change's blast radius.
- Any mid-flight discovery that the parking primitive needs something from `plugins/source-control/`
  beyond the documented `melodic.worktreeroot` convention, since the criterion is that
  `git status --porcelain plugins/source-control/` stays empty.

#### Worker brief essentials, per phase

Every worker reads only `docs/topics/fleet-sync/PLAN.md` and the memory slice under
`.work/fleet-sync/`, and needs, in addition to its ALLOWED and FORBIDDEN lists and the divergence
clause:

- **Phase 2** — the six rung names and their precedence (explicit and config additive; ghq and the
  three cwd rungs only when both are empty; within the cwd family, ancestor-probe first and
  `cwd-repo` last); the record and probe grammars from Phase 1; the config discovery ladder
  (`--config`, then `<project-dir>/.claude/repo-fleet-hygiene.conf`, then
  `~/.claude/repo-fleet-hygiene.conf`), read with `git config --file` and never sourced; the ancestor
  probe bound (at most four levels up, a directory directly holding at least two repositories); that
  `--rungs` exists so the audit can take a subset; exit 5 for nothing resolved; and that every
  negative test stubs `ghq` on `PATH` and runs from a repo-free temp directory.
- **Phase 3** — the design's per-repo state table verbatim, including that a dirty default-branch
  checkout attempts the fast-forward first; the park round-trip in order, with the canonical never
  detached and `worktree add --detach` as the only detach; the stash discipline (`push -u -m
  <marker>`, capture the SHA by marker, `apply --index <sha>`, re-find and assert before
  `drop stash@{n}`, never bare stash or pop, never a raw SHA to drop); the restore-on-failure path
  and where it stops applying; the three-rung parking ladder and the full pre-flight list; the audit's
  env pinning, fixed-argv allowlist, and timeout wrapper as the model to copy; the sync-cluster
  wrapper shape from `scripts/sync-hook-utils.sh`; the two `--skip` grammars; the exit-code table; and
  the guardrails block list as a hard budget.
- **Phase 4** — the enumerated consumer list and exactly which string and exit code each depends on;
  the insertion point before `CLI_ROOT_COUNT` is snapshotted; the rung set (`config`, `ghq`,
  `cwd-root`, `cwd-ancestor`, never `cwd-repo`) and why the last one is excluded; that resolver stdout
  and stderr are captured and not forwarded; that a resolver root must exist on disk; that the
  nothing-resolved path keeps its current message and exit code byte for byte; that the audit's
  `allowed-tools` grant is unchanged; and that `ghq` and the resolver are both recorded in the
  security-review reference.

#### Mechanical work

- Commit boundaries: one commit per phase, Conventional Commits, scoped to `repo-fleet-hygiene` or to
  the repo-level `scripts/` surface. No commit touches `plugins/source-control/`.
- Verification checkpoint after every phase: `scripts/affected-tests.sh --run --explain`, plus the
  phase's own Sanity Check commands, run by the main session against the worker's branch rather than
  taken from the worker's report.
- The pull request opens as a draft and flips to ready when the phases are done, so the test and
  review lanes are asked for once. Its body is drafted to the PR body contract before creation.
- Sequential fallback path as documented above.
