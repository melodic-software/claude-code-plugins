# multi-agent

A Claude Code plugin that owns the marketplace's guidance on two questions:
whether a task should run as a workflow, and which model and effort each agent
in a multi-agent run gets. Other plugins call it rather than restating either
answer.

## The skills

| Skill | What it does |
|---|---|
| `/multi-agent:assess <task>` | Returns `workflow`, `subagent` or `single` with a one-line reason. Checks whether workflows are available in this session first; when they are not, `workflow` becomes `subagent`. Writes nothing. |
| `/multi-agent:route <role\|all\|vendors <task>> [code\|research\|mechanical] [session=<alias>]` | Resolves the role map and `vendors` settings through the config cascade and prints them as fenced JSON: per role a `single` and a `fanout` variant, each with model, effort, source layer and basis, plus resolved `vendors` switches and preferences. `all` is the map a workflow reads from `args.roles`; `vendors <task>` chooses a vendor, model and effort for one delegated task via the benchmark trust model and `vendors` settings. |
| `/multi-agent:audit-defaults [<role>\|fanout\|repo\|registry]` | Fetches each bundled default's pointer and reports which defaults have drifted, whose pointer does not state its value, or whose recheck trigger has fired, with evidence and a proposed diff. `repo` checks the repository's own model, effort, subagent and workflow statements against upstream. `registry` rechecks every shipped and team benchmark registry row (reachability, page date and age, work-type coverage, current-model testing) through `multi-agent:registry-audit` and proposes a diff to `reference/benchmarks.json`. Proposes only in its default modes; an explicit apply request in `registry` mode opens a PR in the marketplace repository only. |
| `/multi-agent:setup [check\|apply]` | `check` prints the resolved map and whether the personal override is gitignored. `apply` previews a change to the user, team or local layer as a diff, writes it on your explicit yes, and shows the map before and after. Run by hand only. |

## How a workflow uses it

1. The calling skill runs `/multi-agent:route all session=<alias>`, where
   `<alias>` is the family of its own model (`claude-opus-5-5` is `opus`).
2. It passes the `roles` object of that JSON as `args.roles` to the Workflow
   tool.
3. The script merges `args.roles` over its own built-in fallbacks. A generic
   `agent()` call takes the `fanout` variant when its stage runs more than one
   agent and the `single` variant otherwise; it omits `opts.model` when the
   model is `inherit` and always passes `opts.effort`.

The map governs generic `agent()` calls and Agent dispatches that name no
agent type; a caller of the Agent tool passes one variant's model and effort
on the call, as `/multi-agent:route` describes. A named agent, such as
`implementation:implementer`, `implementation:scoped-implementer` or
`implementation:phase-verifier`, owns its tier through its own frontmatter
and its dispatcher's rules, including any model or effort the dispatcher
passes on the call, and the fan-out guard does not reach it.

When `/multi-agent:route` is not in the session's skill listing, the caller
omits `args.roles`, the script's fallbacks apply, and the caller says once
that enabling this plugin makes the routing configurable.

`/review:fanout-sweep` in the `review` plugin is the first workflow built this
way.

## The drift-audit workflow

`multi-agent:drift-audit` is the evidence pass behind `/multi-agent:audit-defaults`.
First a `multi-agent:docs-fetcher` agent per source page runs `scripts/docs-raw.sh`
on it: a fresh, raw read of the page or its section map, through the shared docs
lookup. A fetcher gets a URL and section ids, never a claim. The workflow passes
those slices inline, inside a data fence, to the judging agents.
Finders (one per default owner, or one per area of the repository) judge each
claim against the slices, ask for sections or pages the slices lack (the
workflow fetches them and asks once more), and fetch a page themselves only
when no slice covers it; plain code dedups what they find; then
three skeptics per batch try to refute each finding, and a majority decides it.
In repo mode a `multi-agent:drift-reader` agent (Read, Grep, Glob) first quotes
each area's claims, and the finders see only those quotes. Finders and skeptics
run as `multi-agent:drift-checker` (WebFetch only, no search). Neither agent
has a shell or can edit, write or spawn agents, and none holds both file and
web access: the only repository text a checker holds is the quoted claim
lines, and the hook below confines its fetches. The
workflow returns findings and, for the defaults, a proposed diff; applying any
of it is a reviewed edit.

The `docs-fetcher`, `drift-checker`, `registry-fetcher` and `registry-judge` definitions set `omitClaudeMd: true`:
each reads untrusted pages and follows only the prompt its workflow gives it,
so all four opt out of the CLAUDE.md instruction hierarchy. The pointer sits
here, not in the agent bodies, so none spends a fetch on it.

- **Pointer**: when you need what the field drops and what still loads, fetch
  [sub-agents: supported frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields)
  and [sub-agents: what loads at startup](https://code.claude.com/docs/en/sub-agents#what-loads-at-startup)
  live.

`multi-agent:registry-audit` is the read-only benchmark registry pass behind
`/multi-agent:audit-defaults registry`. It reads shipped rows in
`reference/benchmarks.json` plus any repository team rows in
`docs/conventions/multi-agent/benchmarks.json` (always running on a manual
invocation regardless of `vendors.*` switches). One `multi-agent:registry-fetcher`
(Bash only, gated to `docs-raw.sh` on the exact hosts of `reference/benchmarks.json`)
fetches each allowlisted row page raw; one `multi-agent:registry-judge` (TodoWrite only,
no shell, no web, no file access) inspects the slice as data and returns a closed JSON
verdict (`source_id`, `reachable`, `page_date`, `covers_work_types`,
`tests_current_models`, `notes` without quoting page text). Page text never enters the
skill session. The workflow proposes a diff to `reference/benchmarks.json` for shipped
rows only; an explicit apply step writes it in a worktree and opens a PR through
`/source-control:pull-request create`, only in [the marketplace repository](https://github.com/melodic-software/claude-code-plugins/tree/main).

A `PreToolUse` hook on `WebFetch` (`hooks/drift-checker-fetch-gate.mjs`) makes
the host rule a gate: inside a `drift-checker` subagent it denies any fetch
that is not an https URL on a first-party docs host with no query string. Every
other agent and the main thread pass through. The workflow drops any source
outside those hosts before a stage runs.

Two `PreToolUse` hooks on `Bash` (`lib/docs-fetcher-gate.mjs`) hold `docs-fetcher`
and `registry-fetcher`: inside each subagent the gate denies every tool call except
one shape, `bash "<plugin root>/scripts/docs-raw.sh" '<url>' [<section id>...]`,
with no query string. The URL must be on first-party docs hosts for `docs-fetcher`, and on the exact
host set of `reference/benchmarks.json` for `registry-fetcher` (enforced by
`hooks/registry-fetcher-gate.test.sh`), which alone may put `--render` before the URL:
`docs-raw.sh` then checks the page for that row's `expect` marker and, when the docs-cache
`renderer` is `firecrawl`, renders a blocked page or an empty script shell through the Firecrawl
CLI, which sends the public URL to Firecrawl's service. Route's board fetch (`fetch-boards`, run in
the main session) renders registry rows the same way. For that command each gate makes no decision,
and passes once per agent run. `docs-raw.sh` fetches with `--public-only`, so the host
must resolve only to global addresses and curl connects to the checked one alone. A
stdin error or a crash inside the gate denies. Both rows set `"onFailure": "block"`
for a missing `node` or a timed-out gate (see Node.js below). Every other agent and
the main thread pass through.

- **Pointer:** when working out what applies to a call the gate leaves undecided, fetch
  [hooks: PreToolUse decision control](https://code.claude.com/docs/en/hooks#pretooluse-decision-control)
  live; for what `onFailure` does with a failed gate and which Claude Code release honors it, fetch
  [hooks: Block the action when a hook fails](https://code.claude.com/docs/en/hooks#block-the-action-when-a-hook-fails)
  live.

The row is always-on: it fires on every `Bash` call, at a budget of one process
(`node`) per call, ratcheted in `.performance/ratchets.json` as `multi-agent-pretooluse-bash-docs-fetcher-gate-spawns`.

An installed mod can stop this plugin's `PreToolUse` hooks from running, and can approve a call
they blocked, so the gate holds only where no installed mod overrides it. Where settings hooks run
relative to mod hooks is read live:

- **Pointer:** [mods events: where settings hooks run in the order](https://code.claude.com/docs/en/plugins/mods/events#where-settings-hooks-run-in-the-order)
  and [mods events: approve or refuse a tool call before the user is asked](https://code.claude.com/docs/en/plugins/mods/events#approve-or-refuse-a-tool-call-before-the-user-is-asked).

## The fan-out guard

The resolver names no frontier model for a stage that runs more than one agent.
Under a Fable session, or when the caller does not say which model
the session runs, every fan-out variant names `opus`; a single synthesis or
judge agent may still inherit the session model. The verifier role stays at
least as strong as what it checks: `opus` verifiers over `opus` workers. Turning
the guard off (`fanout.frontier_guard: false`) is an explicit opt-in to
frontier fan-outs. The basis for each default is recorded beside it in
[`reference/defaults.yaml`](reference/defaults.yaml).

## Haiku

No role routes to Haiku, by owner decision, and Haiku runs at effort `high`
wherever it runs. `/multi-agent:route` still resolves a
role set to `haiku`, or inheriting a Haiku session, and adds a note. The rule
and its evidence: [`reference/routing-rubric.md`](reference/routing-rubric.md).

## Configuration

One configuration, layered: your own file, named by the `role_map_file`
option (set it in `/config`), then the team file
(`docs/conventions/multi-agent.yaml`), then a gitignored personal override
(`docs/conventions/multi-agent.local.yaml`). Each overrides the bundled defaults
per key, for both role mappings and the `vendors` routing settings (`routing`,
`trials`, `auto_delegation`, `tiebreak`, `trials_prove`, `trials_fail`,
`promotion_audits`, `promotion_days`, per-vendor `in_use`/`rank`, and `sources.<id>.enabled`).
`/multi-agent:setup` writes any of the three. A repository can also append team
benchmark rows in `docs/conventions/multi-agent/benchmarks.json` (same closed
schema as `reference/benchmarks.json`; team row ids matching a shipped id are
refused). Keys, values, team rows and layering:
[`reference/config.md`](reference/config.md); where each file lives:
[config locations](reference/config-locations.md).

An old `~/.claude/multi-agent.yaml` or `.claude/multi-agent.local.yaml` is still read while its new
file is absent, and each run warns about it; `/multi-agent:setup apply --migrate` moves it and
deletes the old file.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `role_map_file` | file | *(none)* | Path to your own role map file, the layer that applies in every repository, under the team file and your personal override. Same keys as the team file. Unset: no user layer. /multi-agent:setup apply --layer user writes it; apply --migrate moves an old ~/.claude/multi-agent.yaml into it. |

### How to set these

Set the options above for `multi-agent@<marketplace>`, replacing `<marketplace>` with the
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

## Requirements

- **Bash 3.2 or later, awk and git.** The resolver parses the YAML subset with awk, so no
  `jq`, `yq` or Python is needed.
- **Node.js** for the `drift-checker` fetch gate, the `docs-fetcher` gate and the
  `registry-fetcher` gate. All three rows set `"onFailure": "block"`, and the rows fire on every
  `WebFetch` and every `Bash` call in any agent or the main thread, so a missing `node` can stop
  all of those calls. What a client does with the key is in the `onFailure` pointer above. Where a
  failed gate lets a call through, only the workflow's source filter and the agent's prompt hold
  the drift checker's fetches to first-party docs hosts, and `docs-fetcher` and `registry-fetcher`
  `Bash` go ungated.
  `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"` reports whether `node` resolves;
  `bash "<plugin root>/scripts/check-hook-registration.sh"` then reports whether `hooks/hooks.json`
  registers the fetch gate on `WebFetch` and whether the gate denies a sample off-host
  drift-checker fetch. Both are read-only. Which rows set
  the key and why: [hook budget](../../docs/contracts/hook-budget/README.md#which-rows-set-onfailure-block).
- **curl and jq** for the drift-audit fetch stage (`scripts/docs-raw.sh`). Without them every page
  is recorded unread, and the checkers read their sources with WebFetch alone.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install multi-agent@melodic-software
```

## License

MIT (SPDX-License-Identifier: MIT).
