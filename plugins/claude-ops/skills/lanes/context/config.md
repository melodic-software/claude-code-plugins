# Lane config contract

The launcher (`scripts/lane-launcher.sh`) reads a JSON config describing the lanes
to manage. This file is the full contract; the SKILL.md keeps only the summary.

## Resolution

First hit wins:

1. `--config FILE`
2. `$CLAUDE_OPS_LANES_CONFIG`
3. `<repo>/.work/lanes.json` (repo = `--repo DIR`, else the git toplevel of the cwd)

A missing config exits `4`; malformed JSON or a config with no lanes exits `3`.

## Schema

```json
{
  "prompt_dir": ".work",
  "lanes": [
    { "name": "work",    "prompt": "work.md",    "model": "opus",   "effort": "high",
      "settings": { "pluginConfigs": { "autonomy@<marketplace>": { "options": {
        "lane_stop_gate_enabled": true, "lane_stop_gate_marker": ".lane-complete" } } } } },
    { "name": "work-2",  "prompt": "work-2.md",  "model": "opus",   "effort": "high" },
    { "name": "babysit", "prompt": "babysit.md", "model": "sonnet", "effort": "medium" },
    { "name": "decide",  "prompt": "decide.md" }
  ]
}
```

| Field | Required | Meaning |
|---|---|---|
| `prompt_dir` | no | Base dir for relative `prompt` paths. Default `.work`. Relative values resolve against the repo root; absolute (POSIX `/…` or Windows `C:\…`) are used as-is. |
| `lanes[].name` | yes | The lane's session name — the `--name` value the launcher gives the background session, and the key `status`/`stop` match on. Keep distinct from ad-hoc session names. |
| `lanes[].prompt` | yes | Path to the lane's canonical prompt file. Relative → resolved against `prompt_dir`; absolute → used as-is. The file's full contents seed the session (positional prompt). A missing or empty file skips that lane with an error. |
| `lanes[].model` | no | Passed as `claude --model`. An alias (`opus`, `sonnet`, `fable`) or a full model id. Omit to inherit the machine default. |
| `lanes[].effort` | no | Passed as `claude --effort`. One of `low`, `medium`, `high`, `xhigh`, `max` (validated; a bad value skips the lane). Omit to inherit the default. |
| `lanes[].settings` | no | A JSON **object** passed inline as `claude --settings` — a session-only override that never persists. The motivating use is opting a lane into the `autonomy` plugin's lane-stop gate via a `pluginConfigs` override (example above; the plugin id is marketplace-qualified, `<plugin>@<marketplace>`, for however the plugin was installed). A non-object value skips the lane with an error. |

Lane names are free-form (`work`, `work-2`, `babysit`, `decide`, …); nothing is
hardcoded. The set above mirrors the lanes this repo's telemetry conventions use,
but any names work — `status`/`stop` only ever act on names present in this config.

## Prompt-storage seam (#480)

`prompt_dir` defaulting to `.work` reflects today's reality: canonical prompts live
in a session-local `.work` dir, which is **not durable** — a fresh machine or
session starts empty until the prompts are authored there.

Issue #480 (loop-prompt authoring skill) is slated to **own durable prompt
storage**. This skill deliberately does not build that: it reads prompt files from
wherever `prompt_dir` points today and leaves a single seam for the durable home.

When #480 lands, the only change here is to repoint `prompt_dir` (per-config) or the
`resolve_prompt_dir` function in the script (the default) at the durable location.
No other part of the launcher knows where prompts live.
