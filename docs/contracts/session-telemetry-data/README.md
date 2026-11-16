# Session telemetry data: where session-telemetry's records are, for readers in other plugins

The `session-telemetry` plugin records hook runs, session events and skill use. A skill in another
plugin, such as harness-ops' `observability`, `audit-skill-visibility` and `setup`, reads those
records through the paths below and nothing else: never a file of the session-telemetry plugin's
install, never its hooks. The hook-unit rule in [`docs/review/hooks.md`](../../review/hooks.md) is why.

## Is it on

session-telemetry is not on by default. A reader decides from `enabledPlugins` in the user, project,
local and managed settings files: `session-telemetry@<marketplace>` set to `true` by the last of them
that names it. A reader that finds it off says so, prints the commands that turn it on, and carries on
with the records earlier sessions left:

```text
claude plugin install session-telemetry@<marketplace>    (only when it is not installed)
claude plugin enable session-telemetry@<marketplace>
```

A session started with `--plugin-dir` or `--settings` is not seen by that rule.
`plugins/harness-ops/scripts/session-telemetry-state.mjs` is harness-ops' reader of this section and
the next.

## Its data directory and options

- **Data directory**: `<config dir>/plugins/data/session-telemetry-<marketplace>`, where `<config dir>`
  is `CLAUDE_CONFIG_DIR`, default `~/.claude`.
  - **Pointer**: for where plugin data directories live and that they survive updates, fetch
    [plugins reference § Environment variables](https://code.claude.com/docs/en/plugins-reference#environment-variables)
    live.
- **`options.json`** in that directory: `{"plugin_root": <path>, "options": {<option>: <string>}}`,
  every option the plugin's hooks received at the last SessionStart, keyed by its `userConfig` name.
  An option it does not list takes its default from the plugin's `.claude-plugin/plugin.json`. The
  file is rewritten only when a value changes, so it shows the last session that started, on any
  project.
- **`hook-telemetry-sink.sh`** in that directory: the launcher `HOOK_TELEMETRY_SINK=@session-telemetry`
  (and its alias `@harness-ops`) resolves to, per
  [hook telemetry § Sink path resolution](../hook-telemetry/README.md#sink-path-resolution).

## Where the records are

Project-relative records join onto the main checkout, not a linked worktree, per
[hook telemetry § Consuming](../hook-telemetry/README.md#consuming-sink-side) (store anchoring).

| Record | Path | Options that move or cap it |
|---|---|---|
| Hook log root | `<main checkout>/<session_event_log_dir>`, default `.observability/claude`, carrying a self-ignoring `.gitignore` | `session_event_log_dir` |
| Per-session rows | `<hook log root>/sessions/<session_id>.jsonl`: the event log's rows and the sink's envelope rows for that session | `session_event_log_enabled`, `session_event_log_categories`, `session_event_log_content`; retention `session_log_keep_sessions`, `session_log_keep_days` |
| Shared hook runs | `<hook log root>/hook-events.jsonl` and its rotated `hook-events.jsonl.1`: envelopes that carry no session id | `hook_events_max_bytes` |
| Skill use | `skill-usage.jsonl` and its rotated `skill-usage.jsonl.1`: under `<main checkout>/<skill_usage_dir>` (scope `repo`, default `.claude/observability`), `$HOME/<skill_usage_dir>` (scope `user`), or `<data directory>/skill-usage/<repo slug>` (scope `data-dir`) | `skill_usage_scope`, `skill_usage_dir`, `skill_usage_max_bytes` |

Each capped file moves to its `.1` once it is over the cap, replacing any older `.1`, before the next
row is appended, so the pair stays near twice the cap.

The record shapes are stated once, where their formatter lives:
`plugins/session-telemetry/hooks/session-log-lib.sh` (`slog_event_record_to` for the hook log root)
and `plugins/session-telemetry/hooks/harness-ops-paths.sh` (`harness_ops::record_skill_use` and the
scope resolver for skill use). A reader that needs the same resolution carries a generated copy of
those two files (ADR 0019, `scripts/shared-copies.txt`), as harness-ops does.
