# CI runner routing

This repository is public, so every lane runs on GitHub-hosted runners, free for
public repositories: `ubuntu-24.04` for all of them except the informational
Windows lane `test-windows`, which runs `windows-2025` in its own workflow,
`.github/workflows/pr-test-platforms.yml`, and that workflow's informational
`test-macos-planning-shared` job, which runs `macos-26`. The organization's
runner-policy engine refuses a governed fleet label here outright, reporting
`public-self-hosted-routing`. There is no observer credential and no
self-hosted exception inventory in this repository.

No selector preflight runs anywhere in the organization: private repositories
name the governed fleet label as a literal and nothing routes at run time. This
repository is not eligible for the fleet. The decision is recorded in
melodic-software/github-iac
`docs/adr/0014-fleet-first-ci-for-private-repositories.md`.

## Configuration contract

`.github/runner-policy.json` declares `visibility: "public"` and
`selfHostedCi: false`; the policy engine cross-checks that declaration against
the live repository-visibility evidence on every CI run and fails closed on a
mismatch, so a visibility change must land together with the matching posture
change in this repository's workflows.

Workflow source contains no organization runner label, host name, or GitHub
App identifier. Each reusable workflow from `melodic-software/ci-workflows` is
called at `@main` and has an approved contract in
[`components/runner-policy/policy.json`](https://github.com/melodic-software/standards/blob/main/components/runner-policy/policy.json)
of `melodic-software/standards`, which the `lint-repo` job's runner-policy step
reads at the run's standards commit. Each call passes its `runner` input
explicitly (`ubuntu-24.04`).

## Routing and failure behavior

The `ci-status` required check depends on every **required** workload lane
(`mark-lanes`, `select-tests`, `lint-repo`, `lint-shell`, `check-plugins`, `check-catalog`,
`check-skills`, `test-bash`, `test-python`, `test-node`, `test-selection`,
`check-managed-files`, `check-tests`) and requires
each result to be `success`, failing closed through execution
(`!cancelled()`, never a success-guard, so a skipped lane cannot report
success to branch protection). The one exception is an ordered skip: a test
lane, `test-selection`, `lint-shell` or `check-tests` the change gives no work
skips as a job, and `ci-status` counts that skip as `success` only when
`select-tests` succeeded and its row for that lane (`run_bash`, `run_python`,
`run_node`, `run_selection`, `run_shell`, `run_check_tests`) is `false`; any
other skip stays red.
On a draft pull request every lane but
`select-tests` carries a draft gate, so a draft run lints and tests nothing, and its
`ci-status` passes those skips with the notice `draft: lanes not run; the
ready_for_review run lints and tests this SHA` (`scripts/check-docs-only-gate.sh`
pins both forms). The `ready_for_review` run lints and tests the same SHA, and a
green draft cannot admit a merge: the merge-queue ruleset has no bypass actor, so
every merge waits for the merge-group run, which runs every lane. `test-windows` is deliberately outside that
aggregate, as an informational platform lane; `pr-test-platforms.yml` says so at the
top of the file and warns against wiring it into any required check. It runs in
its own workflow because nothing gates on it and, inside `pr-require-checks.yml`, it was the
longest job in the run: time-to-green is measured to the run's completion, so an
advisory lane was setting the number. Its `on.paths` filters repeat the `shell`,
`python` and `powershell` groups of `pr-require-checks.yml`'s detect-changes table, so a diff
that touches none of them starts no Windows run; the two are kept in step by
hand. Inside a run, its `select-tests-windows` job runs the same planner over the same
diff, and a Windows step runs only when the change selects its suite
(`scripts/test-windows-plan.txt`), counting no changed path that
`scripts/test-windows-inert-paths.txt` lists; a schedule run (09:17 and 16:17 UTC), a
dispatch, and a change to that workflow run every step. The
metadata checks (Conventional Commits title,
`do-not-merge` label, issue linkage) run as the `check-contract` composite step
inside the same `ci-status` job on the same hosted runner and carry no status
contexts of their own. Fork pull requests receive no secrets and
no automated review, by design.

On a ready pull request `ci-status` also requires both AI review lanes
(`pr-review-hosted.yml` and `pr-review-security-hosted.yml`) to have reviewed
the head, in its `Require both review lanes on this head` step, with one
exception: the formatter-only proof (owner decision, row L438 of
docs/owner-decisions.md in the org's architecture repository,
[the row](https://github.com/melodic-software/architecture/blob/main/docs/owner-decisions.md?plain=1#L438)).
The `prove-formatting` job checks out the pull request's test merge commit,
moves to its base, and runs
`.github/scripts/pr-require-checks/formatter-proof.sh` from there: the base's
pinned shfmt (through bash-format's `shfmt_rewrite`) and Ruff (the
python-format hook's two commands, through `scripts/run-ruff.sh`) over the
base's copy of each changed shell and Python file, then the base's
`scripts/sync-shared-copies.sh` and `scripts/sync-hold-floor.py`. When that
reproduces every changed file of the head byte for byte, with only added
`.changes/<plugin>/*.md` fragments beside them, the step accepts the head
without the lanes. A trust-gate path among the changed files (the step's
`hold_patterns`, whoever the author) still needs a person on the trusted-actor
list to approve the head. Any other file, an added, deleted or renamed file, a
mode change, a byte the formatters do not write, a tool off its pin or a run
that fails is no proof, and the lanes decide as before. The proof waives
nothing else: the lane jobs, the holds, pr-verify and the merge-risk rating
still apply. A fork's head and a head an agent App wrote on a trust-gate path
fail as before.

No pull request code runs in `prove-formatting`: after its checkout it moves
the working tree to the merge commit's first parent, the base branch commit
GitHub merged into, so the local shfmt action, the Ruff pin and the script are
the base's, and the head is read only as blob ids. The job holds a read-only
token and keeps no credential. It is not a lane: `ci-status` leaves its result
out of the aggregate, so its failure only means no proof. It runs on every
non-draft `pull_request` event, contract-only ones included, so a label change
on a formatter pull request still finds its proof; a change with any path no
formatter or regenerator covers stops after the classifying step, before the
tools install. Its budget is unmeasured as a job: the script took 173 s on one
lane (36 s on eight) for the 1,403-file shfmt cleanup of
[#17778](https://github.com/melodic-software/claude-code-plugins/issues/17778)
and 5 s for its 439-file Ruff cleanup, so with about 60 s of checkout and setup,
ceil(1.5 x 233 / 60) = 6 minutes, and a 12-minute timeout.

Workflow, job and step names follow the org naming lint
([github-actions-conventions](https://github.com/melodic-software/standards/blob/main/components/github-actions-conventions/README.md)),
which `lint-repo` runs. The gate job `ci-status` shows as
`CI Status`, the check the ci-gate ruleset requires. `lint-repo` lints the repository as a whole (text
hygiene, the CI configuration, the docs conventions); `lint-shell` runs
ShellCheck and the gates that read shell source; `check-plugins` holds the
plugin manifests, changelogs, hook declarations, the counter ceilings and the
shared-library bump checks; `check-catalog` holds the plugin checks that read
the root npm install (`claude plugin validate` and the rendered-view HTML
assets) with the shared-library copy and declared-prerequisite gates beside
them, split from `check-plugins` to keep each under its 3-minute work budget;
`check-skills` holds the skill
and eval contracts, check 25 included; `test-bash`, `test-python` and
`test-node` run the shell suites, the Python suites and the Node packages the
change selects, and each skips when it has none. A domain is its own job only
when that shortens the critical path by more than a job's fixed cost (about
15 s bare, about 40 s with a toolchain), when a job that outgrows its timeout
is split, or, for the test lanes, when it lets a
change that touches none of its ecosystem start no runner for it. Every gate
keeps its step name and its `id`, which is its aggregator key, and each job
with gate steps carries its own `aggregate-hygiene-results.sh` feed over
exactly those steps.

## What each event tests

The `select-tests` job resolves one diff base, published as `lane_base`, and every
diff-scoped step diffs against it:

- **Pull request:** the base branch. The contract suites are the affected
  selection (`scripts/affected-tests.sh`), and ShellCheck lints the changed
  shell files.
- **Merge group:** the queue's base commit
  (`github.event.merge_group.base_sha`), so the lanes run what the group's own
  diff selects, as on its pull request. A release group is scoped the same way;
  the `--check-release` gate step still runs on every merge-group commit. The queue merges a commit only after
  this run passed on it, so main's commits carry its checks. The
  detect-changes groups read only a pull request's files and report true here;
  the check-25 scan diffs its own inputs instead.
- **Push to `main`:** no run, in `pr-require-checks.yml` or
  `pr-test-platforms.yml`. Every commit reaches `main` through the merge queue,
  whose merge-group run already tested that SHA.
- **Schedule (09:17 and 16:17 UTC, two of the workflow's quietest hours) and
  dispatch:** the whole tree. That means
  the full contract corpus, the whole-repository ShellCheck, and the check-25
  scan over every skill. This run catches what a diff cannot show: a suite that
  asserts against the live tree, or a dependency the selector does not see.

Whole-tree gates whose verdict depends only on their own inputs are scoped the
same way on a diff: markdownlint lints the changed markdown (its download is
cached), the eval-quality lint reads the eval set of every skill directory the
diff touched (a set's `files` entries resolve anywhere in it), `claude plugin
validate` runs for the touched plugins, the manifest and workflow schemas run
when their filter group matched, and the skill-count, eval-coverage and
fixture-isolation scans skip when none of their inputs changed. Each falls back
to the whole tree when there is no diff base or `pr-require-checks.yml` changed, and the
scheduled run scans everything. Replayed on 20 recent pull requests, every
skipped or narrowed scan landed on a whole-tree success.

`select-tests` also plans the test lanes, once, with `scripts/plan-test-lanes.sh`:
each selected suite goes to the lane of its ecosystem (a Node suite with a
sibling `.test.sh` runs through it in `test-bash`), `test-bash` gets one to six
legs of about 120 suite-seconds each and `test-python` one to four of about
180, packed longest first from the measured seconds in
`scripts/suite-seconds.txt`, and each leg installs only the optional toolchains
(the animation wheels, the inventory's parser packages, the DuckDB CLI) its
suites need. `test-node` runs the Node packages the change reaches on one to
eight legs of about 140 package-seconds each, packed the same way. An
UNMAPPED code file adds the whole corpus of its language; unmapped data adds
nothing, since no suite reads it, and is still counted. A Python pin runs every
Python suite, a Node pin every Node package, and a change to
`pr-require-checks.yml` or `.github/actions/download-full-history/` every suite
of every lane. `lint-shell` skips when the change touches none of its inputs
(the `lint_shell` filter group: shell and Python source, hook and bin
directories, skill and agent markdown, its gates and their baselines).

A suite that scans a directory never names the file that changed, so it
declares what it reads in a `test-scope:` header comment, and the selector's rule
[R8](#selection-rules) selects it for any changed file matching the glob.
`scripts/affected-tests.sh --help` lists the flags, including `--replay`, which
shows a selector change's effect on recent main commits.

### Selection rules

`scripts/affected-tests.sh` selects a suite when the changed file is code the
suite runs or loads, or data the suite (or code it runs) reads. Each rule finds
that relation from text and paths, and says no when the text does not show it.
"Names" is defined under [Matching](#matching), [Ambiguous names](#ambiguous-names)
and [Comments](#comments) below.

- **R1 self.** A changed suite selects itself, in any ecosystem.
- **R2 co-located.** `<dir>/<stem>.<ext>` selects the sibling suites covering
  it under each ecosystem's naming: `<stem>.test.sh`, `<stem>.test.js`,
  `<stem>.test.mjs`, `<stem>.Tests.ps1`, `<dir>/test_<stem>.py` and
  `<dir>/tests/test_<stem>.py`, the Python forms also with `-` folded to `_`.
  Every match is taken. pytest loads a `conftest.py`, and Python an
  `__init__.py`, with no mention, so either selects every `test_*.py` at or
  below its directory.
- **R3 same language.** A file in the changed file's language that names it is
  a dependent, and R1, R2 and R3 apply to it in turn, with no depth cap; this
  carries a library change out to what sources it. A Python `import`/`from`
  line names `<stem>.py` for each dotted component equal to the stem, and a
  name after `from m import` names `name.py` only when `m`'s package directory
  holds it. The module must sit under the importer's plugin or lib root
  (`plugins/<p>/`, `lib/<l>/`, `.github/scripts/<x>/`); an importer outside
  every root reaches the whole tree. An ambiguous stem resolves only to the
  module of its name in the nearest directory, from the importer up to that
  root, that holds one.
- **R4 other language.** A file in another language counts only where the
  naming line runs or loads the file: an interpreter or process API on the line
  (`bash`, `sh`, `python3`, `node`, `pwsh`, `source`, `subprocess`, `spawn*`,
  `exec*`, ...), or a path to the file rather than its bare name. A chain takes
  at most one such transition. A data file (any extension that is not code)
  reaches code of every language that names it, and that first step spends no
  transition.
- **R5 shared lib.** The `src` of a `scripts/sync-*.sh` selects every path in
  that script's published `copy` list, then R2, R3 and R4 on each copy. The
  copy set is derived from `--print-manifest` on every run, since the manifests
  are what CI's sync lanes enforce.
- **R6 sync script.** A changed `scripts/sync-*.sh` selects its own co-located
  test plus everything its published `src` selects.
- **R7 path class.** A path under `plugins/autonomy/reference/` selects the
  plugin-contract validator's suite, which bans vendor names across that
  directory without naming any file in it.
- **R8 declared scope.** A suite that enumerates a directory of the live tree
  (a `grep -r`, a `find`, a glob) or builds a path from parts declares what it
  reads in its leading comment block, before any code or docstring, in lines of
  `# test-scope: plugins/github/* scripts/x.sh` (`// test-scope:` in `.test.js`
  and `.test.mjs` suites). A changed file matching a glob selects the suite and
  counts as mapped. The globs use the dialect of
  `scripts/affected-tests-no-suite.txt`: matched against the repo-relative
  path, `*` crosses `/`, and a `#` after them starts a comment. A glob matching
  no file fails the run that changes its suite.
- **R9 wrapper.** A selected `<stem>.test.js` or `<stem>.test.mjs` whose
  directory holds `<stem>.test.sh` selects that wrapper too, since CI runs such
  a suite only through its wrapper. Applied after every other rule, before
  `--shard`.
- **R10 package scope.** Node reads a `package.json` for every bare import in
  its package scope
  ([resolution algorithm](https://nodejs.org/api/esm.html#resolution-algorithm-specification)),
  so a changed `<dir>/package.json` seeds the walk with each non-test `.js`,
  `.mjs` or `.cjs` file under `<dir>`, short of `node_modules/` and any nested
  `package.json`, that imports or requires a dependency the manifest declares at
  the diff base or now; R2, R3 and R4 then apply to each. Needs `jq`.

#### Matching

One file names another when the other's basename stands in a line as a whole
path token: bounded on both sides by a character outside `[A-Za-z0-9_.-]`. `/`
is outside that class, so a path-qualified mention names the file. A trailing
run of `.` is sentence punctuation and is dropped, and so is a leading run of
`-`, `+`, `=`, `?` or `.`, so `${TARGET:-<name>}` and `...<name>` name
`<name>`. A basename buried inside a longer token (`handoff-paths.json` against
`paths.js`) is not a mention: a substring match there would be false coverage, a
file nothing covers coming back mapped. A basename with a character outside the
class keeps the substring test rather than losing its coverage.

`plugin.json`, `marketplace.json`, `hooks.json`, `settings.json`,
`package.json`, `package-lock.json`, `CHANGELOG.md` and `LICENSE` select no
suite through a mention: a suite that reads one reads its name or version, and
the manifest, changelog and catalog gates own those files. Only R1, R2, R8 and,
for `package.json`, R10 reach a suite from them; anything else is on the
no-suite list.

#### Ambiguous names

A basename two or more files carry, and the structural docs (`README.md`,
`SKILL.md`, `AGENTS.md`, `CLAUDE.md`, `index.md`), name a specific file only
when the mention resolves to it. Any mention from the file's own directory
resolves. A bare name resolves from a directory above the file when no other
file of that name sits below that directory (`FIXTURES / "questions.json"`),
and never otherwise. A path resolves when it ends in the shortest suffix of the
file's path, two components or more, that no other file of that name ends in,
or in the file's path relative to a directory below the repository root that
holds both files, when that relative path has a directory in it
(`$SCRIPT_DIR/lib/x.sh` from a script beside `lib/`,
`$PLUGIN_DIR/skills/interview/SKILL.md` from inside the plugin). A path that
spells only the name (`$SKILL_DIR/SKILL.md`) or is relative to the root alone
(`$ROOT/.github/workflows/pr-require-checks.yml`) does not resolve: tests build
the same path under a temporary directory as often as they read the real file,
so a suite that reads such a file declares it (R8). R5's shared-library copies
are the exception and keep the plain rule: they share a basename on purpose and
change together with their source.

#### Comments

A line that is only a comment (`#` in shell, Python and PowerShell; `//`, `/*`
or a `*` continuation in Node) names nothing, in suites and in code alike. A
`# shellcheck source=` directive and a JSDoc type import (`@import`,
`import('...')`) are read by tools and still count. A trailing comment on a
shell, Python or PowerShell code line (a `#` outside quotes after a blank)
names nothing either, but a trailing comment on a Node line, or on a Python
`import`/`from` line, still counts: `import transcript_reader  #
scripts/transcript_reader.py` is how a module import names its file. A shell
output redirect's target (`>file`, `>>"$dir/file"`) names nothing: a suite that
seeds a fixture writes that name and reads nothing.

## Contract-only `ci-status`

A same-repo `edited` (without `changes.base`), `labeled`, or `unlabeled` event
runs `ci` as contract-only: every lane job is gated off and `ci-status` reads
the `ci-lanes` commit status on the head SHA, with no carry-forward wait
(`yield-wait-seconds: '600'` on the `report-ci-status` composite, which fixes
`yield-to-full-run: 'true'` and `carry-forward-wait-seconds: '0'`). It
passes only when the newest status the Actions bot wrote is `success`.

A contract-only run waits only on a full run in flight on its SHA:

1. The composite lists this workflow's in-flight runs on the SHA first. A
   sibling whose only non-skipped job is `ci-status` (contract-only) does not
   count, and neither does the attempt of the full run that already wrote
   `ci-lanes=success`.
2. A full run in flight supersedes the contract-only run, which holds with its
   `ci-status` check run in progress: no conclusion, so no red. A job that runs
   always ends in a conclusion, and `neutral` and `skipped` pass a required
   check, so holding is the one way not to fail without passing. An older green
   `ci-status` on the SHA does not stand alone meanwhile, as it would if this
   run posted nothing: while the newer run is in progress the check is not
   satisfied. GitHub's docs do not state that rule;
   [the probe record](#contract-only-ci-status-probe-record) measured it.
3. When the full run completes or records a verdict, the contract-only run lists
   and reads again. It passes only on a `success` created at or after that
   run's start, and is red on anything else: a full run cancelled during the
   hold leaves an older `success` that must not pass. The full run does not wait
   for it: a holding run reads the `success` itself.
4. At the 600 s ceiling, reached only when a label flips early in a run that
   long, the run fails with `superseded by full run <url>`. The full run's
   own `ci-status` check run is newer and decides the gate, and after recording
   `success` it re-runs that red run (`rerun-contract-only-siblings`,
   `actions: write`). The re-run keeps its event, reads `success` and replaces
   the red check run within seconds.

An earlier failed step (an invalid title, a `do-not-merge` label) and a draft do
not hold, because such a run cannot pass: that red lands at once and is the
intended answer. `Require both review lanes on this head` runs after the
aggregate for this reason: before it, a review still running failed the job in
the window a yield happens, and the run never reached the hold. On `merge_group` nothing is contract-only, so the queue never
holds.

**Operator remedy.** When a contract-only `ci-status` is still red after the
full run finished:

- If `ci-lanes` on that SHA is `success` and the pull-request contract passes
  (valid title, no `do-not-merge` label), re-run the red contract-only `ci`
  run. This covers a contract-only run that was still in progress when the full
  run listed its siblings. The composite logs
  `Carried forward: ci-lanes is success`, passes, and the re-run replaces the
  red check run. Pushing a new commit is not needed.
- If the title is invalid or `do-not-merge` is applied, the contract check
  stays red on a re-run. Fix the title or remove the label first, then follow
  the other bullets for `ci-lanes`.
- If `ci-lanes` is `failure`, `pending` with no full run in flight, or missing,
  re-run the full workflow. On a draft, mark it ready instead.

### Contract-only ci-status probe record

Measured 2026-10-31 on
[pr-pipeline-sandbox#261](https://github.com/melodic-software/pr-pipeline-sandbox/pull/261),
whose ruleset requires `ci-status` from app 15368, as the `ci-gate` ruleset
does. One head, one reading per row, no merge queue entry:

| Newest `ci-status` | Older `ci-status` | `mergeStateStatus` |
|---|---|---|
| `success` | none | `CLEAN` |
| in progress | `success` | `BLOCKED` |
| `success` | in progress | `UNSTABLE` (the non-required `merge` check was also in progress) |
| `success` | `failure`, concluded after the newest | `CLEAN` |

The newest run decides, not the last to conclude. Newest is by id and start time; the probe does not separate the two.

## Toolchain integrity

The plugin-gate toolchain is identical everywhere it runs. Node executables
are integrity-locked in `package-lock.json`, Ruff is pinned to the Ubuntu x64
wheel and SHA-256 in `.github/requirements-ci.txt`, and Dependabot tracks both
dependency roots. CI consumes those manifests with `npm ci` and hash-required
`pip`, never mutable global installs.

Locally, lint Python through `scripts/run-ruff.sh`, never a bare `ruff` on `PATH`; its header
explains how it resolves the pinned version and how the pin moves.

## Time-to-green

The standing target is a p50 under 5 minutes and a p95 under 12 minutes per
pull-request head SHA, measured to the first successful full run of the
required workflow (`ci-status`); contract-only runs are excluded. This
repository owns the target, tracked on #3932.

## Authoritative references

- [Reuse workflows and pin a commit SHA](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows)
- [Reusable workflow runner and permission behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [`merge_group` and required checks](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#merge_group)
- [Dependabot configuration options](https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference)
