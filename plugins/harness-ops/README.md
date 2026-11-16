# harness-ops

## Contents

- [Skills](#skills)
- [Session telemetry](#session-telemetry)
- [Install](#install)
- [How the skills adapt to your repo](#how-the-skills-adapt-to-your-repo)
- [Requirements](#requirements)
- [Configuration](#configuration)
- [License](#license)

A Claude Code plugin for running Claude Code well over time. It ships eighteen
skills and no hooks, including a skill that diagnoses why
most of an installed skill fleet never gets used.
audit-native-overlap maps native Claude Code surfaces against the current
repo's own components so a custom skill never silently duplicates what the
product now ships.
audit-install-state reports on the machine-scope `~/.claude` install directory
itself. audit-performance captures slowness evidence at the moment a machine or
session feels slow so the cause is diagnosed instead of nuked, including the
fan-out layer of hooks, statusline, spawn cost, and subagent concurrency.
observability reads what your sessions actually did. known-issues tracks what
upstream has broken, and changelog integration keeps your repo current with what
upstream has shipped. The plugins skill keeps your own plugin fleet current,
and lanes launches and manages your loop lanes as background sessions; the
operator morning view that reads their telemetry is `/work-items:morning-brief`. A
re-runnable `setup` action settles where the known-issues registry lives.
Observability also reads the per-hook execution telemetry Claude Code's native
OTEL cannot see, which the session-telemetry plugin records.

## Skills

| Skill | What it does |
|---|---|
| `/harness-ops:audit-skill-visibility` | Audits whether the model can actually **see** each installed skill, the question behind "why does most of my fleet never get used?", since a skill the model cannot see can never be chosen. Reports three independent things per skill: **reachability** (visible, `user-only` by design, hidden by an override or disabled plugin, or invisibly misconfigured), **observation** (what usage was actually recorded, always horizon-qualified), and **starvation** (whether it is losing the description-budget contest: Claude Code drops descriptions starting with the skills you invoke least, so an unused skill loses the keywords a request would match and stays unused). Whether the listing overflows is computed from documented settings; which particular skills lose their descriptions is a labeled likelihood band, never an exact cutoff. Withholds every cold verdict the data cannot support instead of reporting absence of data as absence of use. Read-only. |
| `/harness-ops:audit-install-state` | Read-only audit of the machine-scope Claude Code installation directory, the `~/.claude` tree plus the home-root `~/.claude.json`. Inventories every file (entries labeled as an authored surface or a rolled-up bulk tree, with the complete per-file rows in a CSV artifact), separates what Claude Code's own `cleanupPeriodDays` sweep already manages from what nothing manages, resolves what each number in a filename actually *is* before attempting any process-liveness lookup, and deny-lists any subtree holding a revert ledger before classifying anything as stale. Never deletes; hands off to `claude purge` and `/disk-hygiene:clean`. |
| `/harness-ops:audit-native-overlap` | Maps native Claude Code surfaces, built-in CLI commands, bundled skills, plugin-backed built-ins, session-provided skills, against the current repo's plugin skills and agents. Bare invocation is a read-only overlap report (candidates with evidence, detection integrity floors carried through, and a shared-listing-budget exposure section); verdicts (`prefer-native` / `prefer-ours` / `complementary` / `superseded` / `defer`) are human-gated in a committed store (`docs/native-surfaces/records.json`) rendered into a generated registry (`docs/native-surfaces.md`) whose every row carries an observable recheck trigger; only an explicit `apply` step bakes presence-gated native references into component descriptions and Boundary sections. |
| `/harness-ops:audit-plugin-landscape` | On-demand, read-only report on installed plugins and known marketplaces: the date of the last upstream commit touching each source path (batched `gh api`), flagged when 60+ days old, archived, moved or renamed, or missing its source path; overlapping plugins grouped across marketplaces with the one to keep named; current alternatives with evidence links; and an adopt, adapt or drop recommendation per plugin. Files no issues and changes no installed state. |
| `/harness-ops:audit-mod-posture` | Read-only inventory of the mods this Claude Code can run: installed mods (found by `modules` in `hooks/hooks.json`, their hooks and mods API calls read by `claude plugin validate` without loading them) and built-in mods (from an `/harness-ops:inventory` report, with whether each can be turned off), plus whether the built-in guard is seated on this machine. Scores M1-M5: guard not seated, mods hooking tool calls, mods hooking prompts or stored history, and mods reaching files and processes outside deny rules. Prints names only, never settings or env values. On demand; no hook. |
| `/harness-ops:audit-performance` | Read-only slowness-diagnostic capture, run at the moment the machine or a session feels slow, before restarting or deleting anything. One timed engine pass separates four documented suspects: accumulated install-tree state, version regression, component bloat, and the fan-out layer, plus on Windows a kernel-object census that names the host-level Token-object leak beneath all four. Each suspect's evidence and verdict routing is documented in the skill. Phase timings count as evidence in their own right; content reads are allowlisted to four non-secret config files (`settings.json`, `.last-cleanup`, `hooks.json`, `installed_plugins.json`), so `~/.claude.json` and `history.jsonl` stay stat-only. Reports and routes; never mutates, never elevates, and never executes a discovered hook or statusline command. |
| `/harness-ops:observability` | Reads locally captured Claude Code telemetry, OTEL DuckDB store, machine-owned collector, optional Aspire dashboard, hook-event JSONL, ccusage, and renders cross-session trend reports (`session`/`day`/`week`/`month`/`since:`/`all` scopes). Read-only except the explicit `clean` action, which prunes the JSONL log and OTEL store by age. |
| `/harness-ops:known-issues` | Searches known Claude product GitHub bugs before you build on a feature, checks service health and model quality, and maintains a persistent registry of tracked issues (what they block, workarounds, follow-ups when fixed). Actions: `status` (default), `search`, `check-all`, `scan`, `list`, `quality`, `create`. |
| `/harness-ops:changelog` | Ingests Claude Code changelog entries and integrates them into the current repo: `fetch` (read-only display), `diff` (decision rows by owner surface and action lens over a release range, no edits), `status` (the read marker from the repo's Claude Code ledger, the default range to the newest release, and the replay cap), and `apply` (executes the decisions in scope one PR per owner plugin, hands larger ones off as work items, then runs a native-surface drift pass that files work items for new overlap candidates, fired store triggers, and a degraded or broken inventory; explicit user intent only). |
| `/harness-ops:behavior-probes` | Runs live probes of Claude Code platform behavior (permission rules, auto mode, hooks, worktrees, subagent caps, sandbox) as data-driven cases, each negative case with a paired positive control, and gives each a pass, fail or inconclusive verdict stamped with the Claude Code version. `--dry-run` (the default) runs every scaffold against a fake `claude` and costs nothing; a live run is opt-in and capped per case and per suite. `recheck` lists the cases a changelog range touches. Outcomes are recorded in the skill's `records.md`. |
| `/harness-ops:plugins` | Brings a machine's plugin fleet current on demand: marketplace refresh, updates for the plugins that actually load (including in-repo project/local-scope installs), new-catalog-plugin install per policy, and scope-divergence detection. Actions: `sync` (default, CLI-mediated mutations only), `converge` (the one action that can touch a committed `.claude/settings.json`. Previews and confirms per plugin first). User-invoked only. |
| `/harness-ops:plugins-audit` | Read-only dry run of `/harness-ops:plugins sync`: predicts the refreshes, updates, installs, enables and scope divergences sync or converge would act on, and issues none of those calls. Model-invocable. |
| `/harness-ops:lanes` | Starts, restarts, stops, and reports loop lanes as named background Claude Code sessions seeded from canonical prompt files. `start` (default) / `restart` pull the repo and refresh the plugin marketplace, then launch each configured lane (`claude --bg -n <lane> --permission-mode auto`, plus `--permission-prompts none` on CLI 2.1.259 or later) with its per-lane `model`/`effort`; `status` shows per-lane running state and live sessionId; `stop` ends a lane via `claude stop`; `consume-restarts` is the OS-schedulable restart-request consumer. It reads each configured lane's telemetry `restart_request` and relaunches the stopped lanes that asked, through the same launcher (#1653). Acts only on sessions whose name is a configured lane. Lanes come from a JSON config (`--config`, else `$HARNESS_OPS_LANES_CONFIG`, else `<repo>/.work/lanes/lanes.json`, with a temporary default-only fallback to the pre-move `<repo>/.work/lanes.json` under a deprecation warning); config and prompts live in the reserved `lanes/` concern home under a hardcoded `.work` root, which is a sanctioned placement but still session-local, so a durable cross-machine home stays #480's job. |
| `/harness-ops:control-claude-code` | The control skill `/app-control:drive` reads to run Claude Code's terminal UI with one plugin loaded and record screenshots, video and stream-json logs of its mods, skills, hooks, commands and permission dialog. Its driver launches `claude` restricted, with API-key and cloud-provider variables cleared, and Ready refuses a session whose `apiKeySource` is not `none`; under `--unattended` it keeps the one CI credential `credentials.ci` names, with the subprocess scrub on, and Ready accepts that credential's source. Screenshots and videos are redrawn from the masked screen, with the account, working directory and usage lines hidden, and each gets a `<path>.txt` text sidecar; Launch starts one session per changed plugin. Runs attended or unattended on the session it launches and never attaches to another; Claude Desktop is never driven, and is covered only through `claude plugin test`. User-invoked. |
| `/harness-ops:prerequisites` | Read-only report of the external tools the enabled plugin fleet declares, and which of them are missing on this machine. Never installs. |
| `/harness-ops:machine-profile` | Discovers this machine's facts and identity domains (each tree's git include, `gh` directory and verdicts), stores them as a re-runnable profile that records the observation behind every value, and reports drift between the stored profile and the host now. Actions: `profile` (default), `diff`, `explain <key>`, `apply --option <key>`. Read-only unless the operator confirms a write: `record --confirm` writes the profile document, and `apply --confirm` prints what to hand to each setup and writes nothing. Never installs and never reapplies a stored value on its own. Design: [machine-profile-design](https://github.com/melodic-software/claude-code-plugins/blob/038c2ae22c23f60500b339fd2f66e4569ecbe2fd/docs/specs/machine-profile-design.md). |
| `/harness-ops:setup` | `check` reports the effective known-issues-registry, skill-usage-log and hook-log-root destinations, their defaults, path containment, the hook log root's self-ignoring guard, and retired conventions (`retirements.yaml`), and prints the guidance for routing personal option changes through Claude Code's plugin configuration prompt; `apply` writes exactly one file, the guard inside the hook log root, and runs the gated retirement cleanup. |
| `/harness-ops:inventory` | Lists every Claude Code surface this machine can invoke: built-in commands, subagents, tools, bundled skills and workflows, and installed plugin components. `/harness-ops:audit-mod-posture` reads its report for built-in mods; the on-disk audit is `/harness-ops:audit-install-state`. |

## Session telemetry

The `*-audit` hooks, the telemetry sink and the per-session hook event log that observability,
audit-skill-visibility and setup read are the `session-telemetry` plugin's; the hook-failure audit and
the session-start prerequisite notices are the `plugin-diagnostics` plugin's. harness-ops does not
depend on either: each reading skill says when session-telemetry is not enabled, prints the commands
that turn it on, and reports what earlier sessions recorded. Where the records live:
[session telemetry data](../../docs/contracts/session-telemetry-data/README.md).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install harness-ops@melodic-software
```

## How the skills adapt to your repo

The defaults are repo-agnostic and everything project-specific routes through
your own repository's context:

- **Observability data locations.** The OTEL store defaults to
  `<project-root>/.claude/observability/otel` and is overridable via the
  `CC_OTEL_STORE` env var (retention windows via `CC_OTEL_RETENTION_DAYS` /
  `CC_OTEL_BODY_RETENTION_DAYS`). The hook-event JSONL source is read from
  the hook log root (`<project-root>/.observability/claude` by default, the
  `session_event_log_dir` option moves it): `sessions/<session_id>.jsonl`
  when the per-session event log is on or the sink is wired, and the shared
  `hook-events.jsonl` (rotated to `.1` at the size cap) for envelopes without
  a session id; every source degrades gracefully when absent.
- **Persistent state** defaults to the plugin's own per-machine data directory
  (`${CLAUDE_PLUGIN_DATA}`): the known-issues registry
  (`registry.json`), `check-all` output, `--write` observability reports, and
  the `lanes` skill's per-lane launch-commit markers
  (`${CLAUDE_PLUGIN_DATA}/lanes/<repo-key>/<lane>-launch-commit`, overridable
  via `lane-launcher.sh --data-dir`). `<repo-key>` namespaces markers by
  repository, the data directory is plugin-wide, while a lane name like `work`
  is only unique within one checkout. `<repo-key>` is a digest of the repository's
  canonical path; print the one for a given checkout with
  `printf '%s' "$(git rev-parse --show-toplevel)" | git hash-object --stdin`. By default nothing is written into your
  repository. Opt in for the registry with `registry_dir` in `harness-ops.yaml`
  (see Configuration) to keep it git-tracked and team-shared inside your repo
  instead.
- **Work-item and docs integration.** Where the skills propose follow-up work
  items or cross-reference quirks/workaround docs, they use whatever tracker
  and docs your project has (e.g. `gh issue create`, your `CLAUDE.md` /
  `.claude/rules`) and skip silently when there is none.

## Requirements

`audit-install-state` needs **Python 3.11+ only**. No PowerShell, no third-party packages, no
`jq`. Its inventory, surface classification, filename-scheme resolution, retention resolution and
sampling are pure `os.walk` + `stat` + regex and behave identically on every platform. The only
OS-specific code is one function, `probe_pid()`, with a POSIX body (`os.kill(pid, 0)`) and a Windows
body (`OpenProcess`); a probe that cannot run reports `unverified`, never `dead`.

Core flows need only `git`, `jq`, `gh` (authenticated), `python3`, and `node` (resolving the
known-issues registry directory, and whether session-telemetry is enabled).
Optional: `duckdb` for OTEL store queries and `npx` for ccusage. The machine-level
`otelcol-contrib` service and Aspire dashboard Compose stack are provisioned separately; the
plugin observes them but does not start them. Every skill reports missing optional tooling
instead of failing.

## Configuration

A repository can commit `harness-ops.yaml` in its convention home (default `docs/conventions`)
to set these keys, checked against
[`schemas/harness-ops.schema.json`](schemas/harness-ops.schema.json):

| Key | Values | Default | What it controls |
|---|---|---|---|
| `registry_dir` | a contained project-relative directory of letters, digits, `.`, `_`, `-`, `/` and `\` | none: `${CLAUDE_PLUGIN_DATA}` | Where `/harness-ops:known-issues` keeps `registry.json`, for everyone working in the repository. Beats the `registry_dir` option; a personal `harness-ops.local.yaml` beats it. Read from the working tree by `scripts/registry-dir.mjs`, which reports the layer that set it (`/harness-ops:setup` shows it); an absolute, drive, UNC, traversal or escaping-symlink value, or one holding any other character (the value reaches a shell command), is named and dropped, and resolves to the plugin data directory. Team and personal values join the git toplevel; the option joins the session's project directory, as it always has. |
| `verification`, `verification_skills.<skill>` | `off`, `light`, `standard`, `strict` | `light` | Whether `/harness-ops:audit-install-state` dispatches its fresh-context cross-review (`strict` also for a single-agent run) and `/harness-ops:changelog` its local verifier: `light` and `off` skip both and mark what they would have checked `unverified`. Read from the default branch only, through `lib/read-verification.sh`; a skill entry beats the plugin value ([verification level](../../docs/contracts/verification-level/README.md)). |

These `userConfig` options tune the skills:

- **`install_new`** (string, optional). New-catalog-plugin install policy for the `plugins`
  skill's `sync` action. `ask` (default) offers not-yet-installed catalog plugins in
  `AskUserQuestion` chunks (at most 4 options per question, 4 questions per call, a further call
  past 16; a chunk of 1, including one left over, is a single-select Install/Skip question), then installs and enables each pick; `all` installs every one
  automatically, leaving one the CLI installs disabled by default off; `none` reports them without
  installing. `/config` shows these three as a picker; a value set by hand outside it is treated
  as `ask` and named in the sync digest.
- **`directory_source_pull`** (string, optional). What `sync` does when a `directory`
  marketplace's git checkout is clean, on a branch with an upstream, and only behind it. `ask`
  (default) asks once whether to run `git -C <path> pull --ff-only`; on yes the skill runs the
  sync again with the pull first: the script re-checks the checkout, fast-forwards it, refreshes
  the marketplace and finishes the sync against the new catalog, and its report says from which
  commit to which. `never` keeps the pull-and-rerun bullet. An autonomous session (`CLAUDE_CODE_REMOTE`,
  `/loop`, `/schedule`) never asks or pulls. A value set by hand outside the picker runs as `ask`
  and is named in the report.
- **`quiet_auto_update_marketplaces`** (string, optional). Comma-separated marketplace names
  whose `sync` report shows `autoUpdate: off` without the suggestion to enable it, for a
  marketplace you keep off on purpose. Unset keeps the suggestion.
- **`registry_dir`** (string, optional). Project-relative directory for the
  known-issues registry (`registry.json`). Set it to keep the
  registry inside your repo (git-tracked, team-shared) instead of the
  per-machine plugin data directory; leave unset to use `${CLAUDE_PLUGIN_DATA}`.
  This option is personal: Claude Code reads it from user settings only, so for
  a registry everyone in the repository shares, commit `registry_dir` in
  `harness-ops.yaml` instead (see [Configuration](#configuration)), which beats
  the option. Absolute, drive-qualified, UNC, traversal, and escaping-symlink
  paths are invalid; such a value is named and dropped, never written outside
  the project.
- **`lane_app_slug`** (string, optional). The GitHub App slug the `lanes` skill passes as
  `--app-slug` to the restart consumer and to `telemetry-upsert.sh`, so both read telemetry
  comments written by `<slug>[bot]` when the lanes run `gh` under that App's installation
  token. Leave it unset under a personal or machine-user token. An empty value, or an
  unrendered `${user_config.lane_app_slug}` placeholder, is treated as no slug.

Run `/harness-ops:setup` to validate this choice. Claude Code owns persistence through its plugin
configuration prompt; rerun setup afterward to verify the rendered value.

Remaining variability is covered by the env vars above and conventional
project-relative defaults; the bundled scripts make no outbound network calls
except `gh`/`curl` reads of GitHub and Claude status pages in the
known-issues skill.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `registry_dir` | string | *(none)* | Project-relative directory holding the known-issues registry (registry.json). Unset: the plugin data directory, ${CLAUDE_PLUGIN_DATA}. A repository's registry_dir in harness-ops.yaml beats this option. Absolute, drive, UNC, traversal, and escaping-symlink paths are invalid. |
| `install_new` | string | `"ask"` | Sync action for catalog plugins not yet installed. ask (default) offers them in AskUserQuestion chunks, at most 4 options per question and 4 questions per call; a chunk of 1 is a single-select Install/Skip question. Each pick is installed and enabled. all installs every one; none only reports them. |
| `directory_source_pull` | string | `"ask"` | Sync action for a directory marketplace whose git checkout is clean, on a branch with an upstream, and only behind it. ask (default) offers to run git pull --ff-only and continues the sync with the refreshed catalog; never only reports the command. An autonomous session never asks or pulls. |
| `quiet_auto_update_marketplaces` | string | *(none)* | Comma-separated marketplace names whose sync report shows autoUpdate: off without the suggestion to enable it. Empty, the default, keeps the suggestion for every marketplace with autoUpdate off. |
| `update_other_paths` | boolean | `false` | Whether sync also updates the outdated project and local plugin records of every other present path on this machine, one CLI call per record. Off (the default), sync reports how many it left and how to update them. |
| `lane_app_slug` | string | *(none)* | Slug of the GitHub App whose installation token the lanes run gh under, passed as --app-slug to the restart consumer and the telemetry upsert so they read the lanes' own telemetry. Needed only under an App token. Absent: the identity resolves from gh api user. Must match ^\[a-z0-9\]\[a-z0-9-\]*$. |

### How to set these

Set the options above for `harness-ops@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
