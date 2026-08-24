# improvement

A Claude Code plugin answering the question the fleet had no entry point for: **"what should we
improve here, and how do we know?"** Two skills, one concern: finding improvement candidates across dimensions, at any size, and backing every one with evidence.

| Skill | What it does |
|---|---|
| `/improvement:find` | Evidence-first improvement finder. Point it at a repo, a feature, a concept, or a process surface, with a vague or specific prompt, and it produces a ranked, evidence-cited list of improvement candidates led by the highest value-to-effort, deliberates on the picked candidate through an interview, and hands off to the planning pipeline. Runnable unattended as a tech-debt-sweep routine. |
| `/improvement:setup` | Verifies or writes the `.claude/improvement.md` config cascade and reports the effective evidence-source configuration. `check` (default) is read-only across all three layers; `apply` interviews and writes the team file. Key contract: [reference/config.md](reference/config.md). |

## Evidence-first identity

Every candidate cites its evidence. Repo-native signals such as churn hotspots and CI health,
local telemetry, or (weakest) model judgment from reading the target, and ranking confidence is
a function of evidence strength. When the target has no measurement at all, the top-ranked
candidate becomes "instrument this so future runs can rank on data," handed to the pipeline like
any other improvement. Evidence gaps are recorded, never papered over.

The finder is read-only: it discovers and deliberates, and execution requests route through the
normal interview → discovery → planning → implementation → verification pipeline. It delegates to
installed specialized lanes where they add value and never re-implements what an owned lane
already does.

## Configuration

Zero config is a fully working state: Tier 0 repo-native evidence needs nothing declared. To tune
churn analysis or declare Tier 2 MCP telemetry sources, run `/improvement:setup`. It manages the
`.claude/improvement.md` cascade. Resolution order `~/.claude/improvement.md` (user-global), then
the team `.claude/improvement.md`, then the gitignored `.claude/improvement.local.md` overlay, whose key contract lives in
[reference/config.md](reference/config.md).

## Running it as a standing routine

`/improvement:find`'s unattended mode implements the tech-debt-sweep routine shape: a scheduled
run persists a ranked report and files top candidates as work items, with prioritization always
human-gated. The recommended wrapper is a **weekly
[Routine](https://code.claude.com/docs/en/routines)**. Each firing gets a fresh session, and the
routine's saved prompt is the tuning surface. Consult that docs page for current Routine
capabilities and limits rather than relying on numbers written here.

### Prerequisite: the plugin must be loaded in the fired session

A routine fires a fresh cloud session, and this skill exists there only when the `improvement`
plugin is installed in that session's environment. Per this marketplace's
[docs/CLOUD-SESSIONS.md](../../docs/CLOUD-SESSIONS.md), a SessionStart-hook install is never
visible to the session that ran it, the plugin must be pre-installed by the cloud environment's
setup script (or otherwise present before the session process starts). That is why the template
below opens with a hard guard: if `/improvement:find` is unavailable, stop and report, a run
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

The prompt is the tuning surface for cap, scope/size band, and dismissed-candidate handling: every unattended control is a soft default the invocation prompt overrides (see
[skills/find/context/unattended.md](skills/find/context/unattended.md)). Iterate on the wording
after observing real runs; never fork the skill to tune a run.

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

### What is NOT a standing wrapper

`/loop` is session-scoped only: it repeats a prompt inside one session and dies with it. It can
babysit a working session, but it is not a standing schedule, a recurring unattended sweep needs
a Routine or a cron workflow, which fire fresh sessions on a standing cadence.
