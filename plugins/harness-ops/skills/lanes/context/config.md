# Lane config contract

The launcher (`scripts/lane-launcher.sh`) reads a JSON config describing the lanes
to manage. This file is the full contract; the SKILL.md keeps only the summary.

## Resolution

First hit wins:

1. `--config FILE`
2. `$HARNESS_OPS_LANES_CONFIG`
3. `<repo>/.work/lanes/lanes.json` (repo = `--repo DIR`, else the git toplevel of the cwd)

A missing config exits `4`; malformed JSON or a config with no lanes exits `3`.

`lanes/` is a reserved first-level concern name under the memory root; the config
and the lane prompt files live inside it rather than as bare files at the root.
The `.work` root is **hardcoded**: the launcher does not resolve a repointed
memory root, because it runs as an operator script outside any session
that could resolve one. A consumer that has repointed the memory root passes
`--config` or sets `$HARNESS_OPS_LANES_CONFIG` instead.

**Pre-move compatibility.** When step 3 finds nothing and the pre-move
`<repo>/.work/lanes.json` exists, that file is read and a one-line deprecation
warning names the move. Only the default falls back: `--config` and
`$HARNESS_OPS_LANES_CONFIG` are used verbatim, so a config kept outside the memory
root still fails loudly rather than silently resolving to a leftover file. A
config resolved at the pre-move path also keeps the pre-move `prompt_dir` default
(`.work`), so a config that never named one still finds the prompts it left beside
itself. Move both into `.work/lanes/` to clear the warning; the fallback is
temporary.

## Schema

```json
{
  "prompt_dir": ".work/lanes",
  "lanes": [
    { "name": "work",    "prompt": "work.md",    "model": "opus",   "effort": "high",
      "settings": { "pluginConfigs": { "autonomy@<marketplace>": { "options": {
        "lane_stop_gate_enabled": true, "lane_stop_gate_marker": ".lane-complete" } } } } },
    { "name": "work-2",  "prompt": "work-2.md",  "model": "opus",   "effort": "high" },
    { "name": "babysit", "prompt": "babysit.md", "model": "opus",   "effort": "medium" },
    { "name": "decide",  "prompt": "decide.md",                    "effort": "high" }
  ]
}
```

Each example lane's level is our choice for the work the lane does. `work`, `work-2` and `decide`
pin `high`: they render verdicts, the worker lanes' fail-closed admission verdict and `decide`'s
decisions. `babysit` pins `medium`: the merge lane's root coordinates, partitioning the rungs and
handing the fixing to workers, so it sits one level below the verdict lanes. A pinned lane does not follow a later change to its model's default level.

- **Pointer**: for choosing a level, see
  [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level).
- **As of**: 2026-10-02
- **Recheck trigger**: that section is renamed or moved, its rows change, or the default level of
  a model a lane launches on changes.

| Field | Required | Meaning |
|---|---|---|
| `prompt_dir` | no | Base dir for relative `prompt` paths. Default `.work/lanes` (`.work` for a config resolved at the pre-move path above). Relative values resolve against the repo root; absolute (POSIX `/…` or Windows `C:\…`) are used as-is. |
| `lanes[].name` | yes | The lane's session name, the `--name` value the launcher gives the background session, and the key `status`/`stop` match on. Keep distinct from ad-hoc session names. |
| `lanes[].prompt` | yes | Path to the lane's canonical prompt file. Relative → resolved against `prompt_dir`; absolute → used as-is. The file's full contents seed the session (positional prompt). A missing or empty file skips that lane with an error. |
| `lanes[].model` | no | Passed as `claude --model`. An alias (`opus`, `sonnet`, `fable`) or a full model id. Omit to inherit the machine default. |
| `lanes[].effort` | yes | Passed as `claude --effort`. Required on every lane, chosen from the "Choose an effort level" table above: `start` and `restart` refuse a lane with no effort (or a `null` one) with an error naming the lane, this key and that table, and still launch the other lanes; `restart` refuses before stopping, so the running session stays up. When `CLAUDE_CODE_EFFORT_LEVEL` is set in the launcher's environment, which every lane inherits, the launcher prints one warning per run that the configured levels may not hold. Pointer: for how that variable ranks against `--effort` and effort pins, see its row under [Variables](https://code.claude.com/docs/en/env-vars#variables). As of: 2026-10-02. Recheck trigger: that row's precedence changes. One of `low`, `medium`, `high`, `xhigh`, `max`, `ultracode` (validated; a bad value skips the lane). `ultracode` [requires Claude Code v2.1.203 or later](https://code.claude.com/docs/en/model-config#adjust-effort-level); below that floor the CLI rejects the value outright (`Unknown --effort value 'ultracode'`) and starts the session at the default effort, so the launcher checks the installed `claude --version` and skips the lane rather than launching it at an unintended effort. `restart` makes that check before stopping, so a refused lane keeps running. For what `ultracode` does to the effort level and when a model cannot run it, see the same section. As of 2026-10-02; recheck when the effort level set or the ultracode version floor changes. |
| `lanes[].settings` | no | A JSON **object** passed inline as `claude --settings`, a session-only override that never persists. The motivating use is opting a lane into the `autonomy` plugin's lane-stop gate via a `pluginConfigs` override (example above; the plugin id is marketplace-qualified, `<plugin>@<marketplace>`, for however the plugin was installed). A non-object value skips the lane with an error. A gate request (`lane_stop_gate_enabled: true` under an `autonomy` key) additionally triggers launch-time ARMING: the launcher runs autonomy's `hooks/lane-stop-gate-arm.sh` and injects a random `lane_stop_gate_arm_id` into the launched settings, the trusted per-session channel the gate actually honors (it ignores the bare env mirror a repo `env` block could forge). A gate-requesting lane that cannot be armed (autonomy missing/pre-0.12.0, arming error, managed-settings veto) is skipped with an error rather than launched silently ungated. |
| `lanes[].stage` | no | The stage skill the lane runs, as `<plugin>:<skill>` (for example `work-items:work-loop`). Selects the lane's `skill.<plugin>.<skill>` key in the execution target below. Lowercase letters, digits and `-` on each side of one `:`. Any other value, a non-string included, prints a warning naming the config file, the lane, `stage` and the value, and that lane runs with no stage; other lanes and actions proceed. Without it, a lane resolves only `default`. |
| `lanes[].schedule` | no | `{"every_minutes": N}`, N a whole number from 1 to 999. Absent by default. Only a lane with one gets `print-schedule` entries; see "Scheduled runs" below. `20.0` reads as `20`. Any other value prints a warning naming the config file, the lane, `schedule` and the value, and that lane is treated as having no schedule; other lanes and actions proceed. |
| `lanes[].telemetry` | no | The lane's telemetry binding (`issue`, `repo`, `marker`), the same object the restart consumer reads (`context/restart-consumer.md`), plus an optional `author`, a GitHub user login whose comments count besides the `gh`-authenticated login's. The lanes file is lane-writable, so `author` must name a person the operator vouches for. Any login ending in `[bot]` is refused: an app's bot account writes for every workflow or installation holding its token, so it names no single writer. A `cloud-session` lane reads its probe fallback from it and needs a numeric `issue`; its `repo`, when set, must be origin's own `owner/repo`. |

Lane names are free-form (`work`, `work-2`, `babysit`, `decide`, …); nothing is
hardcoded. The set above mirrors the lanes this repo's telemetry conventions use,
but any names work. `status`/`stop` only ever act on names present in this config.

One constraint on the name, enforced at preflight: it is also the filename of the
lane's launch-commit marker
(`<data-dir>/lanes/<repo-key>/<name>-launch-commit`), so it must be a single path
component. A name containing `/` or `\`, or equal to `.` or `..`, exits `3`.
Without that check, `work` and `group/../work` would share one marker file and a
targeted restart of either would corrupt the other's staleness probe. The
`<repo-key>` component keeps same-named lanes in different repos apart, since the
data directory is plugin-wide rather than per-repo.

Types are checked, and a wrong type is never read as an absent field. `name`, `prompt`, `model` and
`effort` must be JSON strings; a non-string value exits `3` at preflight alongside the checks above.
`settings` is checked per lane instead, so only that lane is skipped. An explicit `null` is the JSON
spelling of "no value" and is equivalent to omitting the field. The distinction matters: a
`false` is falsy, and a reader that treats falsy as absent silently launches the lane without the
setting rather than reporting the mistake.

## Execution target

`start` and `restart` choose each launching lane's host from the consumer repository's
`docs/conventions/execution-target.yaml`. The contract, including the values, the cloud launch
rule and the stage-start probe, is `docs/conventions/execution-target/README.md` in the
marketplace repository; this section covers only what the launcher does.

- **Read.** Once per run the launcher checks that origin's own `HEAD` (`git ls-remote --symref
  origin HEAD`) names the same branch as the local `origin/HEAD`, fetches that branch, reads the
  file at the fetched commit with `git show`, never from the working tree, and prints the SHA. No
  `origin/HEAD`, a failed fetch, an absent file or a file the shared reader rejects keeps every
  lane on today's launch, with the reason printed. An unreadable or disagreeing origin `HEAD`, a
  `url.<base>.insteadOf` or `pushInsteadOf` rule that rewrites origin's URL, or more than one
  `remote.origin.url` does the same and also skips every `work-items:triage` lane. These checks
  catch a stale or moved symref; they are not a boundary against someone who can write the
  checkout's git config.
- **Keys.** `skill.<plugin>.<skill>` for the lane's `stage`, then `class.untrusted-provenance` for
  `work-items:triage` (its input is always untrusted), then `default`. An unknown value launches
  today's way and is reported. Each lane prints `execution target <value> (<key>)`.
- **`local-worktree`.** Today's launch from the repository root.
- **`local-background`.** The same `claude --bg -n <name> --permission-mode auto` launch from the
  lane's linked worktree, `<data-dir>/lanes/<repo-key>/worktrees/<name>`, created detached at the
  fetched commit. A clean existing worktree moves to that commit; one with changes is used as it
  stands.
- **`cloud-session`.** A lane whose stage may read untrusted input (every stage in the contract's
  table today, a lane with no `stage`, and any stage outside the table) is skipped with an error
  naming `/work-items:attend-queue` as the escalation route; it files nothing and does not run
  locally. Otherwise, `claude --cloud` from the lane's linked worktree, which must be clean and is
  moved to the fetched commit, with the stage-start probe in front of the prompt. The launch is
  refused, and the lane launches today's way, when the Claude GitHub App does not cover origin's
  `owner/repo` (from origin's configured URL, checked with `gh api user/installations`), the worktree
  has changes, the lane's telemetry cannot be read (no numeric `telemetry.issue`, or a
  `telemetry.repo` other than origin's), or the lane requests the lane-stop gate. A not-yet-honored
  `execution_target_fallback` from an authorized author in the lane's telemetry moves one launch to
  today's launch. `claude agents --json` does not list cloud sessions, so the
  launcher writes `<data-dir>/lanes/<repo-key>/<name>-cloud-launch`: `start` skips a lane while it
  stands, and `restart` sends a new session (archive the earlier one at claude.ai).
- **`cloud-routine`, `cloud-project`.** Setup steps are printed and nothing launches; `restart`
  leaves a running local session of the lane up. A lane whose stage may read untrusted input gets no
  setup steps: it is skipped with the same `/work-items:attend-queue` error as `cloud-session`.
- **`--telemetry-json FILE`.** A test aid: it replaces the GitHub comment read with a local file of
  the same shape, and the launcher prints a warning on stderr whenever it reads one. Do not use it
  for a real launch.

## Scheduled runs

`run-once <lane>` runs one headless pass of a lane and returns: `claude -p --permission-mode auto
[--permission-prompts none] [--model M] --effort E [--settings JSON] "<prompt>"`, with the same
effort refusal, version gate and lane-stop gate arming as `start`. It does not pull or update the
marketplace. It places the pass by the lane's execution target: `local-worktree` from the
repository root, `local-background` from the lane's linked worktree, and nothing for a cloud host,
whose own trigger runs the stage there. A lane already running as a background session is skipped.
A per-lane `mkdir` lock at `<data-dir>/lanes/<repo-key>/<lane>-run-once.lock` keeps two passes of
one lane apart on one host: a run that finds the lock held exits `0` having run nothing, and a lock
whose recorded owner pid has exited is reclaimed.

For a drain lane, the prompt file names the stage with its single-pass flag, for example
`/work-items:work-loop --drain --single-pass` when that skill is among the available skills.

`print-schedule [--write-script] [lane...]` prints, for each lane with a `schedule`, a Task
Scheduler entry and its removal, and a cron line when cron can express the interval (otherwise a
systemd timer or launchd interval to use). Every entry calls
`<repo>/.work/lanes/scheduled/<lane>.sh`, which `--write-script` writes and which calls `run-once`
through this launcher's absolute path, with the config, data directory and `PATH` in effect when it
was written. Rewrite the script after a harness-ops update moves the launcher. Calling a short
script keeps the Windows `/TR` payload to `"<bash>" "<script>"`; a lane whose payload would pass
schtasks' 262-character limit is refused, so move the checkout to a shorter path. A scheduled
lane's name must be letters, digits, `.`, `_` or `-`, because it names the script and the task.
Registering an entry is the operator's step. Run the `schtasks` lines from cmd.exe, as
[restart-consumer.md](restart-consumer.md) explains for its own entries.

A Task Scheduler task created without an XML definition starts no new run while one is running;
the lock covers cron and the other schedulers.

- **Pointer**: the `IgnoreNew` row of
  [MultipleInstancesPolicy](https://learn.microsoft.com/en-us/windows/win32/taskschd/taskschedulerschema-multipleinstancespolicy-settingstype-element)
  and the `/tr` row of
  [schtasks create](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/schtasks-create).
- **As of**: 2026-10-04
- **Recheck trigger**: either row changes its default or its limit.

## Where prompt files are read from

`prompt_dir` defaulting to `.work/lanes` settles **where** the canonical prompts
sit: inside this skill's reserved concern home rather than loose at the memory
root. It does not make them durable. The memory root is session-local, so a fresh
machine or session starts empty until the prompts are authored there.

This skill deliberately does not build durable cross-machine prompt storage: it
reads prompt files from wherever `prompt_dir` points and leaves a single place to
change. To
move prompts to a durable home, repoint `prompt_dir` (per config) or the
`resolve_prompt_dir` function in the script (the default). No other part of the
launcher knows where prompts live.
