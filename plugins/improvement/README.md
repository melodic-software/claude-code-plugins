# improvement

A Claude Code plugin for improving anything, from one method to a whole feature, and knowing why
the change is better. `find` answers **"what should we improve here, and how do we know?"** with a
ranked, evidence-cited list. `improve` answers **"make this better"** by shipping one improvement,
measured against a stated standard, as one small PR, ready or draft by the repository's open-state rule.

| Skill | What it does |
|---|---|
| `/improvement:improve` | Improve-one-thing. Point it at any target (a symbol, file, feature, skill, doc, or process) with an optional focus such as performance, naming, or currency with current upstream guidance. It finds one gap against the repo's written standards (and upstream guidance when the focus asks for it), ships the smallest complete fix as one PR (ready or draft by the repository's open-state rule) within the [PR scope budget](reference/pr-scope-budget.md), and hands larger changes to planning. With no arguments it reads the conversation and confirms target and focus with you first. Runnable unattended on a schedule. |
| `/improvement:find` | Evidence-first improvement finder. Point it at a repo, a feature, a concept, or a process surface, with a vague or specific prompt, and it produces a ranked, evidence-cited list of improvement candidates led by the highest value-to-effort, deliberates on the picked candidate through an interview, and hands off to the planning pipeline. Runnable unattended as a tech-debt-sweep routine. |
| `/improvement:setup` | Verifies or writes the config cascade and reports the effective evidence-source configuration. `check` (default) is read-only across every layer and names any old-location file; `apply` moves an old file's settings to the new location after a yes, then interviews and writes the team file. Key contract: [reference/config.md](reference/config.md). |

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install improvement@melodic-software
```

## Evidence-first identity

Every candidate cites its evidence: repo-native signals such as churn hotspots and CI health,
local telemetry, or (weakest) model judgment from reading the target. Ranking confidence is
a function of evidence strength. When the target has no measurement at all, the top-ranked
candidate becomes "instrument this so future runs can rank on data," handed to the pipeline like
any other improvement. The finder records each evidence gap.

The finder never edits the target's tracked files: it discovers and deliberates, and execution
requests route through the normal interview → discovery → planning → implementation → verification
pipeline, or to `/improvement:improve` when the pick fits one small PR. Unattended, it keeps its
report under its own plugin data directory and files work items. When code-metrics is enabled, in either mode, its duplication input keeps a report in
code-metrics' data directory (`reports/<state-key>/audit-duplication-<UTC stamp>.json`, the next
run's trend baseline), and a growing clone class gets one review-findings file at
`<memory_dir>/improvement/<branch-slug>/<UTC stamp>-clone-growth.md` in the git-ignored memory tier,
plus a `.gitignore` containing `*` in `<memory_dir>` when that file is absent. It delegates to
installed specialized lanes where they add value and never re-implements what an owned lane
already does.

## Configuration

Zero config is a fully working state: Tier 0 repo-native evidence needs nothing declared. To tune
churn analysis or declare Tier 2 MCP telemetry sources, run `/improvement:setup`. Settings resolve
lowest first from the bundled default, the plugin's `userConfig` options (per person, set with
`/plugin configure improvement@<marketplace>`), the team `docs/conventions/improvement.yaml`,
then the gitignored `docs/conventions/improvement.local.yaml`, per
[config locations](reference/config-locations.md). The key contract lives in
[reference/config.md](reference/config.md).

The old files `~/.claude/improvement.md`, `.claude/improvement.md` and
`.claude/improvement.local.md` are still read while they exist, with a warning on each run;
`/improvement:setup apply` moves their settings to the new locations and deletes them.

## Running it as a standing routine

`/improvement:find`'s unattended mode implements the tech-debt-sweep routine shape: a scheduled
run persists a ranked report and files top candidates as work items, with prioritization always
human-gated. The recommended wrapper is a **weekly
[Routine](https://code.claude.com/docs/en/routines)**. Each firing gets a fresh session, and the
routine's saved prompt is where you tune it. Consult that docs page for current Routine
capabilities and limits rather than relying on numbers written here.

### Prerequisite: the plugin must be loaded in the fired session

A routine fires a fresh cloud session, and this skill exists there only when the `improvement`
plugin is installed in that session's environment. Per this marketplace's
[docs/cloud-sessions.md](../../docs/cloud-sessions.md), a SessionStart-hook install is never
visible to the session that ran it. So the plugin must be pre-installed by the cloud environment's
setup script (or otherwise present before the session process starts). That is why the template
below opens with a hard guard: if `/improvement:find` is unavailable, stop and report. A run
that improvises an "improvement sweep" without the skill's contract is worse than no run.

### Recommended Routine prompt (weekly)

```text
If /improvement:find is unavailable in this session, stop and report that the
improvement plugin is not installed in this environment — do nothing else.

Run /improvement:find. This runs unattended as a scheduled routine — there is
no interactive user to answer any question. Persist the report and file top
candidates as work items.

Tuning — edit these lines as you observe real runs:
- File at most 3 items this run.
- All sizes; whole-repo scope.
- Suppress previously dismissed candidates.
```

Cadence and time of day belong to the scheduler. The cap, scope, size band and dismissed-candidate
handling resolve from the prompt, then the config cascade, then the bundled default (see
[skills/find/context/unattended.md](skills/find/context/unattended.md) and
[reference/config.md](reference/config.md)). The open cap is the exception: the prompt cannot raise
it, and personal settings can only lower it.

Each item find files carries one source label the repository must already have:
`source: architecture-improve` for a verified `Strong` candidate from `/architecture:improve`, which find
runs inline when that plugin is installed, and `source: improvement-find` for every other. While the
open items carrying a label number at or above `find_open_item_cap` (default 5), an unattended run
files nothing under that label. Iterate on the wording after observing real runs; never fork the
skill to tune a run.

### Improve-one-thing prompt (daily or hourly)

`/improvement:improve --unattended` ships one PR per run, a draft unless the prompt authorizes the
ready flip, measured against the repo's written
standards only, and stops when three of its PRs are already open. A human merges every one.

```text
If /improvement:improve is unavailable in this session, stop and report that the
improvement plugin is not installed in this environment. Do nothing else.

Run /improvement:improve --unattended. This is a scheduled run with no user present.

Tuning (edit these lines as you observe real runs):
- Target: the most recently changed files.
- Stop when 3 improve PRs are already open.
```

### Alternative: GitHub Actions cron

Where Routines are not available (or the schedule must live in the repo), wrap the same prompt in
a scheduled workflow using [`claude-code-action@v1`](https://github.com/anthropics/claude-code-action)
with its `plugins:` input, which solves the same fired-environment prerequisite by installing the
plugin into the action's session. Sketch. Adapt input details to the action's current README:

```yaml
on:
  schedule:
    - cron: "0 6 * * 1" # weekly
jobs:
  improvement-sweep:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      issues: write
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0 # full history — a shallow clone downgrades churn evidence to a gap
      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          plugin_marketplaces: melodic-software/claude-code-plugins
          plugins: improvement@melodic-software
          prompt: |
            <the same Routine prompt template as above>
```

These permissions fit the `find` prompt, which only files issues. The improve-one-thing prompt
pushes a branch and opens a pull request, so its job needs `contents: write` and
`pull-requests: write` in place of `contents: read`, plus `issues: write` for filed overflow.

### What is NOT a standing wrapper

`/loop` is session-scoped only: it repeats a prompt inside one session and dies with it. It suits
repeating a check during a working session, but it is not a standing schedule. A recurring unattended sweep needs
a Routine or a cron workflow, which fire fresh sessions on a standing cadence.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `churn_window` | string | *(none)* | Your git log --since window for the hotspot recipe, such as 90 days ago. A repository's docs/conventions/improvement.yaml overrides it. Unset: 90 days ago. |
| `churn_exclude` | string (multiple) | *(none)* | Extra ERE patterns, one per entry, left out of churn counting in every repository. Unioned with the repository's own patterns. |
| `churn_exclude_defaults` | boolean | *(none)* | false drops the lockfiles, generated output, snapshots and vendored trees resolved from each repository, leaving only declared patterns. Unset: true. |
| `find_open_item_cap` | number<br>*min 0* | *(none)* | Lowers the cap on open items per source label that unattended /improvement:find files under. Applies only when below the repository's cap. 0 stops unattended filing. |
| `find_run_item_cap` | number<br>*min 1* | *(none)* | Where the adaptive per-run filing cap starts. Unset: 3. |
| `find_run_item_cap_floor` | number<br>*min 1* | *(none)* | Lowest value the per-run filing cap adapts to. Unset: 1. |
| `find_run_item_cap_ceiling` | number<br>*min 1* | *(none)* | Highest value the per-run filing cap adapts to. Unset: 5. |
| `find_size_band` | string | *(none)* | Candidate sizes an unattended run ranks: all, small, medium or large. Unset: all. |
| `find_scope` | string | *(none)* | What an unattended run scans: repo, or a target /improvement:find accepts. Unset: repo. |
| `find_suppress_dismissed` | boolean | *(none)* | Whether an unattended run leaves out candidates an operator dismissed before. Unset: true. |
| `evidence_sources_file` | file | *(none)* | A YAML file of yours whose evidence_sources key declares Tier 2 telemetry sources (MCP server, kind, scope, hints) for every repository. A repository's own declarations merge over it per source name. |

### How to set these

Set the options above for `improvement@<marketplace>`, replacing `<marketplace>` with the
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
