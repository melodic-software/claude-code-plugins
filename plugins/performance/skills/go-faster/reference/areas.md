# go-faster areas

The sweeper walks this file top to bottom: one entry per area, current state first (setup, CI and
review history), then the session so far. Every area ends with at least one finding: measured,
candidate, flag-only, or `not-checked` with its reason code and reason (the reason rule is under
**Not checked** below). Finding fields are the record table in the `go-faster-sweeper` agent; this file says what to
run and what to record for each area.

Contents: [git](#git), [hooks](#hooks), [permissions](#permissions),
[instructions](#instructions), [plugins-startup](#plugins-startup),
[bash-windows](#bash-windows), [machine](#machine), [ci-cd](#ci-cd), [gates](#gates),
[pr-review](#pr-review), [tests](#tests), [session-work](#session-work),
[how-you-work](#how-you-work), [skills](#skills), [orchestration](#orchestration),
[model-cache](#model-cache).

Each entry gives:

- **Source**: where the data comes from.
- **Run**: the exact command or `/plugin:skill [args]` call, from the repository's working
  directory. No `git -C` to any other path.
- **Owner**: the skill whose output is reused, or none.
- **Record**: the finding to add, with its fixed `workload` text where it is measured. `compare`
  matches `workload` verbatim, so copy it exactly.
- **Not checked**: the condition, the reason code, and the `reason` text to use word for word.
  Fill each `<...>` slot with what it names and copy the rest unchanged. Every not-checked reason
  states why the area was not checked, then either (a) the step that would make the area
  checkable on a later go-faster run, named only when that run would in fact read it, or (b) the
  scope that makes the area inapplicable here ("applies only ..."). It never names a step
  go-faster would still not read, and never suggests creating or changing something (CI,
  instruction files, delegation, security or elevation settings) only so go-faster can measure it.
- **Guard**: the flag-only rule, where one applies.
- **Catalog**: the catalog files and area slugs whose rows back a candidate or a remedy.

**Rules for every area.** These apply to all sixteen entries.

- **Guards are flag-only.** Any hook, permission rule or instruction that blocks, denies or asks
  before an action is a safety guard. A finding that would loosen, skip or remove one is
  `flag-only` with the reason, never measured or candidate, never `now`.
- **Unclassifiable is flag-only.** A check you cannot classify as either a guard or a verifying
  check is `flag-only`, and `reason` says why it could not be classified.
- **Fewer checks need a guard metric.** A finding that runs a verifying check (test, lint, build,
  CI check, pre-commit verifier) on fewer changes sets `effect: fewer-checks` and a `guard_metric`.
- **Dropping or weakening a check is not proposed here.** It sets `effect: drops-check` and
  `fix_owner: /overengineering:audit`.
- **Lowering model, effort or verification depth is flag-only** (`effect: lower-model`,
  `lower-effort` or `lower-verification`).
- **A candidate rests on a catalog row.** It needs a row in a named catalog file whose `area`
  cell holds the area slug (or `all`), and an expected size from a count this entry names. Fetch
  the row's `pointer` with WebFetch in this run and cite it as `{url, as_of: <the run's date>, recheck:
  <the row's recheck_trigger>}`, with `confidence` the row's label. A row you cannot fetch is not
  cited, and a candidate that needed it is not reported. No row, no candidate.
- **Fix owner.** A measured finding names the owner its entry gives. Where none is given, use the
  cited row's remedy as `steps-for-you`; with no cited row, `/performance:target`.
- **Which gh account.** Every gh call below inherits the caller's `GH_CONFIG_DIR`. Only when the
  caller's environment does not set it and the repository's own instructions (the CLAUDE.md or
  AGENTS.md this session loaded) name a value for this repository, pass that value on the
  `gh repo view` probe and the `ci-timing` and `pr-timing` calls as a single-quoted prefix,
  `GH_CONFIG_DIR='<value>' ...`, and record it as
  `gh_config_dir` in each GitHub finding's `conditions` (in the reason of a `not-checked` one).
  Never choose an account directory any other way, and never use a named value that holds a
  quote, `$`, a backtick or a line break, or that is not an absolute path outside the repository
  (a directory inside it could hold another account's `hosts.yml`): treat it as unset. A gh failure either way is the
  `auth-gap` below.
- **One GitHub probe.** Before the first of `ci-cd`, `gates`, `pr-review` and `tests`, run
  `gh repo view --json nameWithOwner --jq .nameWithOwner` once, with `GH_CONFIG_DIR` as the rule
  above sets it. It prints `OWNER/REPO` for `ci-timing --repo` below. On failure all four areas
  are `not-checked`, `auth-gap`, reason "gh repo view failed: <its first error line>; run
  `gh auth status`, and `gh auth login` if it shows no login for this host; this run used
  GH_CONFIG_DIR=<the value used, or unset>, so set the right one in the session that starts the
  run and rerun /performance:go-faster".
- **GitHub numbers come from findings.py.** After the probe, the four GitHub areas make two calls:
  `"$PY" "$ROOT/scripts/findings.py" ci-timing --repo <OWNER/REPO>` and
  `"$PY" "$ROOT/scripts/findings.py" pr-timing`. Each runs gh itself, with `GH_CONFIG_DIR` as above,
  and prints JSON whose numbers are objects with `value`, `unit`, `samples`, `excluded` and
  `command`; record `value` and `unit` as printed and copy `command` into the finding. A number
  whose `samples` is 0 is not recorded as measured. An area left with no recorded number is
  `not-checked`, `no-data`: when the call listed nothing (`runs_listed` or `prs` is 0), with the
  area's own reason below. Otherwise count the excluded items: the number's `excluded`, plus
  `runs_excluded` for a `ci-timing` number. Above 0: reason "every timed sample was excluded
  (<that count> excluded): their timestamps were missing or unparsable; this area times only items
  whose GitHub timestamps parse". Zero: reason "the runs
  or pull requests read had no job, step or review to time". Never run
  `gh run list`, `gh api` or `gh pr list` yourself, and never save gh output to a file. Exit 1
  makes every area fed by that call `not-checked`, `auth-gap`, reason "<the error line it
  printed>; run `gh auth status`, and `gh auth login` if it shows no login for this host, then
  rerun /performance:go-faster".
- **History is not contended.** CI, review and job timestamps were recorded before this sweep, so
  findings built from them are tier E2 (aggregate) in both modes. Only timings the sweeper takes
  itself follow the contention rule.

**Owner calls.** This table is the complete list of calls this sweep makes into another plugin;
an area entry uses only a call listed here. Check the skill
is in your skill listing, invoke it with the Skill tool and exactly these arguments, and follow the
procedure it returns. A missing skill, a refused call, or a result you cannot read makes the area
`not-checked`, `owner-unavailable`, with the reason in the last column.

| Area | Call | Read from what it returns | Stop following it when | `owner-unavailable` reason |
|---|---|---|---|---|
| `hooks` | `/harness-ops:observability latency` | per hook event p50 and p95, and which events it flags | never; the `latency` action is read-only | "hook latency needs /harness-ops:observability; enable the harness-ops plugin and rerun /performance:go-faster" |
| `instructions`, `plugins-startup` | `/context-budget:audit --ledger` | the latest history row's startup token counts | its procedure asks you to take a snapshot, spawn a session, install anything or persist a report: stop, record `owner-unavailable`, reason "the ledger history is not reachable read-only from this run; this area applies only once /context-budget:audit's ledger holds a row, which it records only for a measured lever change" | "startup tokens need /context-budget:audit; enable the context-budget plugin and rerun /performance:go-faster" |

Never invoked, named only as a fix owner or as a step for the user:

- `/session-flow:audit-sessions`: every run collects into session-flow's own store first.
- `/context-budget:audit` with any argument other than `--ledger`: a full audit takes snapshots,
  spawns sessions and offers an install.
- `/harness-ops:audit-performance`: it writes a report file.

**Upstream pointers.** The commands and file lists below depend on these upstream specifics; read
them live when a command's output, or the files you find, do not match the entry.

- **Pointer**: [git update-index, `--test-untracked-cache` and UNTRACKED CACHE](https://git-scm.com/docs/git-update-index)
- **As of**: 2026-10-03
- **Recheck trigger**: a git release changes what that option tests or its exit codes.

- **Pointer**: [gh repo view](https://cli.github.com/manual/gh_repo_view) JSON fields
- **As of**: 2026-10-03
- **Recheck trigger**: a gh release drops or renames `nameWithOwner` in `gh repo view --json`.

- **Pointer**: [GitHub REST, list jobs for a workflow run](https://docs.github.com/en/rest/actions/workflow-jobs)
- **As of**: 2026-10-03
- **Recheck trigger**: the job or step objects drop `created_at`, `started_at` or `completed_at`.

- **Pointer**: [gh run list](https://cli.github.com/manual/gh_run_list) and [gh pr list](https://cli.github.com/manual/gh_pr_list) JSON fields
- **As of**: 2026-10-03
- **Recheck trigger**: a gh release renames `attempt`, `createdAt`, `mergedAt` or `reviews`.

- **Pointer**: [Claude Code settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect),
  [where the local settings file sits in a git repository](https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository),
  and [ask and deny rules](https://code.claude.com/docs/en/permissions#manage-permissions)
- **As of**: 2026-10-03
- **Recheck trigger**: a settings file moves, or `permissions.ask` or `permissions.deny` is renamed.

- **Pointer**: [how CLAUDE.md files load](https://code.claude.com/docs/en/memory#how-claude-md-files-load),
  [when Claude Code reads AGENTS.md](https://code.claude.com/docs/en/memory#when-claude-code-reads-agents-md),
  [path-specific rules](https://code.claude.com/docs/en/memory#path-specific-rules) and
  [user-level rules](https://code.claude.com/docs/en/memory#user-level-rules)
- **As of**: 2026-10-03
- **Recheck trigger**: the set of files loaded at launch changes, or rules stop using a `paths:`
  frontmatter key.

- **Pointer**: [gh auth status](https://cli.github.com/manual/gh_auth_status),
  [gh auth login](https://cli.github.com/manual/gh_auth_login) and
  [GH_CONFIG_DIR](https://cli.github.com/manual/gh_help_environment)
- **As of**: 2026-10-03
- **Recheck trigger**: a gh release renames `gh auth status` or `gh auth login`, or
  `GH_CONFIG_DIR` stops naming gh's configuration directory.

- **Pointer**: [CLAUDE_CONFIG_DIR](https://code.claude.com/docs/en/env-vars)
- **As of**: 2026-10-03
- **Recheck trigger**: the page changes what `CLAUDE_CONFIG_DIR` moves; this file relies on it
  moving the user's `settings.json` only, and names the user `CLAUDE.md` and `rules/` by their
  `~/.claude` paths.

- **Pointer**: [OpenTelemetry tool decision event](https://code.claude.com/docs/en/monitoring-usage#tool-decision-event)
- **As of**: 2026-10-03
- **Recheck trigger**: the `tool_decision` event is renamed or removed.

## git

- **Source**: `git status` timed under trace2; git's untracked-cache test run in a scratch repo.
- **Run**: `"$PY" "$ROOT/scripts/findings.py" status-timing --data "$DATA" --runs 5`, then
  `bash "$ROOT/scripts/untracked-cache-probe.sh"`, then `git config --get core.untrackedCache`.
- **Owner**: none.
- **Record**: one measured finding from status-timing: unit `elapsed-ms`, value `median_ms`,
  title naming `min_ms` to `max_ms` as the spread, label "status without index refresh",
  `command` the printed command, `fix_owner` `/performance:goal`, route `performance-chain`,
  horizon `later`, workload `git status x5, main session active` (attended) or
  `git status x5, main session waiting` (unattended). Then
  `"$PY" "$ROOT/scripts/findings.py" compare --data "$DATA" --findings "$RUN/findings.json" --id <id>`
  and keep its line for your return. From the probe: exit 0 (`result=supported`) while the config
  read is not `true` is a candidate, tier E3, title naming the `volume=` it printed,
  `expected_size` null (a status time in ms is not a count, so it sorts unsized), `command` `bash "$ROOT/scripts/untracked-cache-probe.sh"`, `fix_owner` `steps-for-you`, horizon
  `later`, route `next-run`. Exit 1 (`unsupported`) or a config already `true` adds nothing.
- **Not checked**: outside a repository: `no-data`, reason "not inside a git repository; run
  /performance:go-faster from inside the repository's working tree". A guard refuses
  status-timing: `refused-by-guard`, reason "git status timing refused by a guard; this area
  applies only where this session's guards allow `git status`". Probe exit 2: a second `git`
  finding, `not-checked` with the `reason_code=` it printed and its `reason=` text. A guard
  refuses the probe call itself: `refused-by-guard`, reason "untracked-cache probe refused by a
  guard; this check applies only where this session's guards allow the probe;
  `git update-index --test-untracked-cache` tests it separately, outside go-faster".
- **Guard**: none.
- **Catalog**: [catalog/git.md](catalog/git.md) rows with area `git`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## hooks

- **Source**: hook execution latency from locally captured telemetry, through its owner.
- **Run**: `/harness-ops:observability latency`.
- **Owner**: harness-ops.
- **Record**: one measured finding per hook event it flags: unit `elapsed-ms`, value the p95, tier
  E2 (a per-event total spans every matching hook), workload `hook latency, last 7 days`,
  `command` exactly `/harness-ops:observability latency`, `fix_owner`
  `/harness-ops:audit-performance`, horizon `later`, route `performance-chain`. Flags nothing: one measured finding for the
  slowest event it lists.
- **Not checked**: no rows, or it cannot evaluate: `no-data`, reason "no hook latency rows;
  /harness-ops:observability says it needs <the telemetry it names>; set that up and rerun
  /performance:go-faster". Not in the listing, or the call fails: `owner-unavailable`, with the
  owner-call table's reason.
- **Guard**: a hook that blocks, denies or asks is a guard. A finding that would disable, skip or
  narrow one is `flag-only`. A slow guard is reported by its time only; making it faster without
  changing what it stops is `/harness-ops:audit-performance`'s to judge.
- **Catalog**: [catalog/harness.md](catalog/harness.md) rows with area `hooks`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## permissions

- **Source**: the permission rules in the settings files this run can read: the project's
  `.claude/settings.json` and `.claude/settings.local.json`, and the user's `settings.json` under
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. Outside Windows, in a git repository, the local file
  sits at the repository root (the main checkout's root in a worktree).
  Settings files can hold tokens in `env`, so never Read them; findings.py reads them and prints
  only counts.
- **Run**: `"$PY" "$ROOT/scripts/findings.py" permission-counts --file <path> --file <path> ...`
  with each file's path. It prints, per file, `status` (`read`, `missing`, `invalid` or
  `unreadable`) and, when read, the `ask` and `deny` rule counts. A file not `read` is listed as
  unread.
- **Owner**: none.
- **Record**: one `flag-only` finding per scope that has ask or deny rules: title
  "<n> ask and <m> deny rules in <scope>", reason "a permission rule that asks or denies is a
  safety guard; loosening it is yours to decide; prompt counts need OpenTelemetry tool_decision
  events, which this version does not read".
- **Not checked**: no ask or deny rule in any scope read: `no-data`, reason "no ask or deny rule
  in <scopes read>; prompt timing needs OpenTelemetry tool_decision events, which this version
  does not read" plus the unread scopes.
- **Guard**: every finding in this area is `flag-only`.
- **Catalog**: [catalog/harness.md](catalog/harness.md) rows with area `permissions`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## instructions

- **Source**: the instruction files loaded at launch, read only: `CLAUDE.md` and
  `CLAUDE.local.md` in the working directory and every directory above it, `.claude/CLAUDE.md`,
  `AGENTS.md` and `.claude/AGENTS.md` when a `CLAUDE.md` imports them or when no `CLAUDE.md`,
  `.claude/CLAUDE.md` or `CLAUDE.local.md` other than the user's own exists in the working
  directory or above it, the user's `~/.claude/CLAUDE.md`, and each project
  `.claude/rules/**/*.md` and user `~/.claude/rules/**/*.md` with no `paths:` key in its
  frontmatter. Startup token history through its owner.
- **Run**: `wc -l` over the files that exist; `/context-budget:audit --ledger`.
- **Owner**: context-budget (history only). A missing or stopped owner drops only the token
  finding; the line-count candidate still stands.
- **Record**: a candidate, tier E3, `expected_size`
  `{count: <total lines>, source_kind: repo-count, source: "always-loaded instruction lines"}`,
  `command` "run /context-budget:audit to measure startup tokens", `fix_owner`
  `/instruction-placement:audit`, horizon `later`, route `next-run`. When the ledger row reports
  instruction tokens on its own, add a measured finding instead: unit `tokens`, tier E2, workload
  `startup ledger, latest row`, `command` `/context-budget:audit --ledger`.
- **Not checked**: no instruction file exists: `no-data`, reason "no always-loaded instruction
  file found: nothing loads at launch, so there is no instruction cost to measure".
- **Guard**: an instruction that blocks, denies or asks is a guard; a finding that would remove or
  relax one is `flag-only`. A speedup that conflicts with a loaded instruction sets
  `conflicts_instruction` to the file and line, and is `flag-only`.
- **Catalog**: [catalog/harness.md](catalog/harness.md) and
  [catalog/agentic-workflow.md](catalog/agentic-workflow.md) rows with area `instructions`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## plugins-startup

- **Source**: startup token history through its owner.
- **Run**: `/context-budget:audit --ledger` (one call serves this area and `instructions`).
- **Owner**: context-budget (history only).
- **Record**: from the latest history row: a measured finding, unit `tokens`, value the startup
  total, tier E2, workload `startup ledger, latest row`, `command` `/context-budget:audit --ledger`,
  `fix_owner` `/context-budget:audit`, horizon `later`, route `performance-chain`.
- **Not checked**: no history rows: `no-data`, reason "startup cost needs /context-budget:audit
  ledger history; this area applies only once that ledger holds a row, which it records only for a
  measured lever change". Owner missing or stopped per the owner
  table: `owner-unavailable`, with the owner-call table's reason.
- **Guard**: none.
- **Catalog**: [catalog/harness.md](catalog/harness.md) rows with area `plugins-startup`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## bash-windows

- **Source**: the cost of one external process spawn under Git Bash, timed with this plugin's
  interleaved harness.
- **Run**: only when `uname -s` starts with `MINGW` or `MSYS`:
  `bash "$ROOT/scripts/ab.sh" --a ':' --b '/usr/bin/true; :' --iterations 20 --label-a builtin --label-b spawn`.
- **Owner**: performance (this plugin's own script).
- **Record**: a measured finding, unit `elapsed-ms`, value the `spawn` arm's p50 minus the
  `builtin` arm's p50 (the cost of one spawn), title naming both p50 values, tier E3 (attended) or
  E1 (unattended), workload `spawn ab x20, main session active` or
  `spawn ab x20, main session waiting`, `command` the ab.sh line, `fix_owner`
  `/harness-ops:audit-performance`, horizon `later`, route `performance-chain`.
- **Not checked**: not a Git Bash host: `no-data`, reason "not a Git Bash on Windows host; this
  area applies only on Windows under Git Bash". ab.sh
  exits 2: `no-data`, reason "spawn timing refused: <its first stderr line>; fix what that line
  names and rerun /performance:go-faster". ab.sh exits 1: `no-data`, reason "spawn timing failed:
  <its first stderr line>; an arm lost or gained sample rows, so the run cannot be compared".
  ab.sh prints an OUTLIER line: `no-data`, reason "spawn timing unstable: <the OUTLIER line>;
  rerun /performance:go-faster unattended while the machine is idle".
- **Guard**: none.
- **Catalog**: [catalog/windows-machine.md](catalog/windows-machine.md) rows with area
  `bash-windows`; [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## machine

- **Source**: none. This version reads no machine performance recording, so the area is always
  `not-checked`.
- **Run**: nothing.
- **Owner**: none.
- **Record**: `not-checked`, `no-data`, reason "this version reads no performance
  recording; machine remedies are flag-only".
- **Not checked**: always, as above.
- **Guard**: every machine remedy (an antivirus exclusion, moving work to a Dev Drive, any change
  to a security setting) is `flag-only`, whatever evidence a later version holds.
- **Catalog**: [catalog/windows-machine.md](catalog/windows-machine.md) rows with area `machine`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## ci-cd

- **Source**: GitHub Actions run and job timestamps.
- **Run**: `"$PY" "$ROOT/scripts/findings.py" ci-timing --repo <OWNER/REPO>`. It lists the 20
  most recent completed runs and fetches jobs for the five newest. Keep its JSON in context;
  `gates` and `tests` read the same output.
- **Owner**: none.
- **Record**: a measured finding for queue wait from `queue_wait` (per job, `started_at` minus
  `created_at`, skipped jobs excluded, median across the five runs): unit `wait-ms`, tier E2,
  workload `ci jobs, last 5 completed runs`, `command` its `command`. A second measured finding
  for run length from `run_length` (per run, latest job `completed_at` minus earliest job
  `started_at`, median): unit `ci-minutes`, same tier and workload. Both horizon `later`, route
  `performance-chain`, `fix_owner` `/performance:goal`.
- **Not checked**: `runs_listed` is 0: `no-data`, reason "no completed CI runs in this
  repository; this area applies once this repository has completed GitHub Actions runs; this
  sweep reads GitHub Actions only".
  GitHub probe failed or `ci-timing` exited 1: `auth-gap`, with that reason.
- **Guard**: none beyond `gates`.
- **Catalog**: [catalog/ci-cd.md](catalog/ci-cd.md) and
  [catalog/measurement.md](catalog/measurement.md) rows with area `ci-cd`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## gates

- **Source**: CI step timings for recent runs, from the `ci-cd` job data.
- **Run**: no new call; read `slowest_step` from the `ci-timing` output `ci-cd` holds.
- **Owner**: none.
- **Record**: a measured finding for the slowest step by median duration across those runs
  (skipped steps excluded): unit `elapsed-ms`, tier E2, workload `ci steps, last 5 completed runs`,
  title naming its `step` and its `job`, `command` its `command`, horizon `later`, route
  `performance-chain`, `fix_owner` `/performance:goal`. Classify the step: a
  verifying check (test, lint, build, type or security check) or a guard. A remedy that runs it on
  fewer changes is `effect: fewer-checks` with a `guard_metric`; one that drops or weakens it goes
  to `/overengineering:audit`; a step you cannot classify is `flag-only` with the reason.
- **Not checked**: `runs_listed` is 0: `no-data`, reason "no completed CI runs in this
  repository; this area applies once this repository has completed GitHub Actions runs; this
  sweep reads GitHub Actions only". Runs listed but `slowest_step` has `samples` 0: `no-data`,
  with the shared samples-0 reason above. GitHub probe failed or `ci-timing` exited 1: `auth-gap`, with that
  reason.
- **Guard**: a step that blocks a merge or a deploy (a required check, an approval gate) is a
  guard; a finding that would skip or relax it is `flag-only`.
- **Catalog**: [catalog/ci-cd.md](catalog/ci-cd.md) and
  [catalog/review-and-tests.md](catalog/review-and-tests.md) rows with area `gates`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## pr-review

- **Source**: merged pull request timestamps and reviews.
- **Run**: `"$PY" "$ROOT/scripts/findings.py" pr-timing`. It lists the 20 most recent merged pull
  requests.
- **Owner**: none.
- **Record**: a measured finding for open to first review from `first_review` (earliest review
  `submittedAt` minus `createdAt`, over PRs with a review), and one for open to merge from
  `open_to_merge` (`mergedAt` minus `createdAt`): median each, unit `wait-ms`, tier E2, workload
  `merged PRs, last 20`, `command` its `command`, horizon `later`, route `next-run`, `fix_owner`
  `/performance:goal`. PR size is a
  candidate only: `expected_size`
  `{count: <size value>, source_kind: repo-count, source: "merged PRs, last 20"}`.
- **Not checked**: `prs` is 0: `no-data`, reason "no merged pull requests to time; this area
  applies once this repository has merged pull requests on GitHub". GitHub probe
  failed or `pr-timing` exited 1: `auth-gap`, with that reason.
- **Guard**: a required review or approval is a guard; a finding that would skip or relax one is
  `flag-only`.
- **Catalog**: [catalog/review-and-tests.md](catalog/review-and-tests.md) and
  [catalog/measurement.md](catalog/measurement.md) rows with area `pr-review`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## tests

- **Source**: CI re-runs and test step timings, from the `ci-cd` data.
- **Run**: no new call; read `reruns` and `test_steps` from the `ci-timing` output `ci-cd` holds.
- **Owner**: none.
- **Record**: a measured finding from `reruns`, unit `count`, value the runs among the 20 with
  `attempt` above 1, tier E2, workload `ci runs, last 20`, `fix_owner` `/testing:diagnose`,
  `command` its `command`, horizon `later`, route `next-run`. A measured finding from `test_steps` for the median duration of steps
  whose name contains `test` (any case), unit `elapsed-ms`, tier E2, workload
  `ci steps, last 5 completed runs`, `command` its `command`, horizon `later`, route
  `performance-chain`, `fix_owner` `/performance:goal`. Running fewer tests per change is
  `effect: fewer-checks` with a `guard_metric`; deleting or weakening tests goes to
  `/overengineering:audit`.
- **Not checked**: `runs_listed` is 0: `no-data`, reason "no completed CI runs in this
  repository; this area applies once this repository has completed GitHub Actions runs; this
  sweep reads GitHub Actions only".
  GitHub probe failed or `ci-timing` exited 1: `auth-gap`, with that reason.
- **Guard**: as `gates`.
- **Catalog**: [catalog/ci-cd.md](catalog/ci-cd.md),
  [catalog/review-and-tests.md](catalog/review-and-tests.md) and
  [catalog/measurement.md](catalog/measurement.md) rows with area `tests`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## session-work

- **Source**: this session's transcript, read only.
- **Run**: `"$PY" "$ROOT/scripts/findings.py" transcript-counts "$TRANSCRIPT"`.
- **Owner**: none (a cross-session baseline waits on session-flow).
- **Record**: a measured finding (tier E1, `command` that same line, workload `transcript counts`)
  for each of: the tool with the most `wait_ms` (unit `wait-ms`), each command in
  `repeated_commands` and each file in `repeated_reads` (unit `count`), and any tool whose
  `errors` exceed one (unit `count`). A repeat whose cure changes only how this session works
  (reuse the earlier output while its inputs are unchanged) is horizon `now`, effect `batching`,
  confidence `HIGH` (a direct count), with `guard_metric` "a reused result differs from a fresh run" and `revert_if` "the inputs
  changed since the earlier run"; its route is `next-run`. Everything else is `later`, route
  `next-run`, `fix_owner` `/performance:goal`.
- **Not checked**: `TRANSCRIPT` `none` and `SESSION` `unknown`: `no-data`, reason "no transcript
  found for session unknown: the session id did not expand; this area reads only the live
  session's transcript". `TRANSCRIPT` `none` otherwise: `no-data`, reason "no transcript found
  for session <SESSION>: its transcript file is missing; this area reads only the live session's
  transcript". Else `EVIDENCE` false: `no-data`, reason "no session evidence yet; rerun
  /performance:go-faster after this session has done some work".
- **Guard**: none beyond the rules above.
- **Catalog**: [catalog/agentic-workflow.md](catalog/agentic-workflow.md) rows with area
  `session-work`; [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## how-you-work

- **Source**: a cross-session baseline. Its only owner writes its own store on every run, so this
  version does not call it.
- **Run**: nothing.
- **Owner**: session-flow (later, once it offers a read-only consumer mode).
- **Record**: `not-checked`, `no-data`, reason "needs a cross-session baseline go-faster cannot
  read yet; /session-flow:audit-sessions shows it separately".
- **Not checked**: always, as above.
- **Guard**: none.
- **Catalog**: [catalog/agentic-workflow.md](catalog/agentic-workflow.md) rows with area
  `how-you-work`; [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## skills

- **Source**: skill invocations in this session's transcript, from the `session-work` counts.
- **Run**: no new call; read `skills` from the transcript-counts output.
- **Owner**: none.
- **Record**: a candidate per catalog row with area `skills` whose cause these counts size, one
  per skill invoked more than once: tier E3, `expected_size`
  `{count: <invocations>, source_kind: session-count, source: "skill invocations this session"}`,
  horizon `later`, route `next-run`.
- **Not checked**: `TRANSCRIPT` `none` and `SESSION` `unknown`: `no-data`, reason "no transcript
  found for session unknown: the session id did not expand; this area reads only the live
  session's transcript". `TRANSCRIPT` `none` otherwise: `no-data`, reason "no transcript found
  for session <SESSION>: its transcript file is missing; this area reads only the live session's
  transcript". Else `EVIDENCE` false: `no-data`, reason "no session evidence yet; rerun
  /performance:go-faster after this session has done some work". Counts, and a row whose fetch failed: `no-data`, reason
  "WebFetch of <pointer> failed; rerun /performance:go-faster when that host is reachable from this session". Counts but no row whose
  cause these counts size: `no-data`, reason "no catalog row covers this cause".
- **Guard**: none.
- **Catalog**: [catalog/harness.md](catalog/harness.md) and
  [catalog/agentic-workflow.md](catalog/agentic-workflow.md) rows with area `skills`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## orchestration

- **Source**: subagent calls in this session's transcript, from the `session-work` counts.
- **Run**: no new call; read `tools.Agent` (and `tools.Task`, its older name) and `subagents`.
- **Owner**: none.
- **Record**: a measured finding, unit `wait-ms`, value the summed `wait_ms` of those tools, title
  naming the call count and `subagents`, tier E1, workload `transcript counts`, `command` the
  transcript-counts line, `fix_owner` `/multi-agent:assess`, horizon `later`, route `next-run`.
  A delegation, parallelism or batching change may be `now` only when it meets every `now` rule.
- **Not checked**: `TRANSCRIPT` `none` and `SESSION` `unknown`: `no-data`, reason "no transcript
  found for session unknown: the session id did not expand; this area reads only the live
  session's transcript". `TRANSCRIPT` `none` otherwise: `no-data`, reason "no transcript found
  for session <SESSION>: its transcript file is missing; this area reads only the live session's
  transcript". Else `EVIDENCE` false: `no-data`, reason "no session evidence yet; rerun
  /performance:go-faster after this session has done some work". No subagent calls: `no-data`,
  reason "this session made no subagent calls, so there is no delegation time to measure".
- **Guard**: a change that lowers a subagent's model or effort, or drops its verification, is
  `flag-only`.
- **Catalog**: [catalog/agentic-workflow.md](catalog/agentic-workflow.md) rows with area
  `orchestration`; [catalog/measurement.md](catalog/measurement.md) rows with area `all`.

## model-cache

- **Source**: token and cache counts in this session's transcript, from the `session-work` counts.
- **Run**: no new call; read `tokens` (`input`, `output`, `cache_read`, `cache_creation`).
- **Owner**: none.
- **Record**: a measured finding, unit `tokens`, value `cache_creation`, title naming
  `cache_read` and `input` beside it, tier E1, workload `transcript counts`, `command` the
  transcript-counts line, horizon `later`, route `next-run`. Counts only, never a price.
- **Not checked**: `TRANSCRIPT` `none` and `SESSION` `unknown`: `no-data`, reason "no transcript
  found for session unknown: the session id did not expand; this area reads only the live
  session's transcript". `TRANSCRIPT` `none` otherwise: `no-data`, reason "no transcript found
  for session <SESSION>: its transcript file is missing; this area reads only the live session's
  transcript". Else `EVIDENCE` false: `no-data`, reason "no session evidence yet; rerun
  /performance:go-faster after this session has done some work".
- **Guard**: a lower model or effort is `flag-only` (`effect: lower-model` or `lower-effort`).
- **Catalog**: [catalog/harness.md](catalog/harness.md) and
  [catalog/measurement.md](catalog/measurement.md) rows with area `model-cache`;
  [catalog/measurement.md](catalog/measurement.md) rows with area `all`.
