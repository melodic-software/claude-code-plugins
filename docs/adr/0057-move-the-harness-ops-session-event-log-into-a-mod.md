# Move the harness-ops session event log into a mod

- Status: accepted
- Date: 2026-10-04

## Context

The harness-ops per-session hook event log is off by default (`session_event_log_enabled: false`).
Even so, harness-ops registered 29 settings rows for it: one `session-event-log.sh` row on each of
the 28 events the generated registry (`plugins/harness-ops/hooks/hook-events.registry.json`) marks
observable, and one `session-retention.sh` row on `SessionEnd`. Each row ran
`node exec-bash.mjs --require-true SESSION_EVENT_LOG_ENABLED ...`, so with the log off every one of
those events still started one node process to read the switch: every prompt, every tool batch,
every `Stop`, every subagent start and stop. #4393 accepted that residual on 2026-09-27 as a harness
limit, before [ADR 0052](0052-adopt-claude-code-mods.md) adopted mods.

The owner measured the cost on 2026-10-04 from local transcripts (the measurement comment on #6246):
in 69 hours, at least about 43,700 node starts for the disabled feature, 39,108 of them on
`PostToolBatch`. On that host the event-log row was the only settings hook on `PostToolBatch` and
`UserPromptSubmit`, so each of those fires waited on it: an estimated 2.5 to 5.1 hours a week of
serial wait, 0.13 to 0.27% of main-thread turn time.

A mod receives each settings hook event as `classic.<Event>` with the payload a settings hook gets
on stdin, and a mod hook starts no process unless it calls `$.process.run`. ADR 0052 lets a plugin
convert to a mod only when the mod matches every behavior of what it replaces, except differences
the owner accepts by name.

## Decision

**The log moves into a harness-ops mod (#6246, option A), and the 29 settings rows are removed in
the same change.** The hooks module `plugins/harness-ops/hooks/register.ts`:

- hooks nothing while `session_event_log_enabled` is off, so with the log off no event starts a
  process;
- while it is on, hooks `classic.<Event>` for each event the registry marks observable, and hands
  the event's payload to the unchanged `session-event-log.sh` through `exec-bash.mjs`, with the
  plugin's options as `CLAUDE_PLUGIN_OPTION_*` and the project root as `CLAUDE_PROJECT_DIR`, the
  environment the settings rows had;
- on `SessionEnd`, also runs the unchanged `session-retention.sh`.

The record writer stays one script, so the records are the ones the settings rows wrote, and no
second formatter exists. `scripts/gen-hook-event-registry.sh` writes the module's `classic.<Event>`
hooks from the registry, since Claude Code reads each hooked event from a string literal, and its
`--check` fails while any event-log or retention row is in `hooks.json`. The four
`.performance/ratchets.json` census entries that measured the retired rows are removed; the
module's own `claude plugin test` cases count its processes, per the hook-budget convention's rule
for mods.

The owner accepted these six differences by name on #6246: the first four in the decision comment,
and the last two, found while building the module, in a
[later comment](https://github.com/melodic-software/claude-code-plugins/issues/6246#issuecomment-5987066808):

1. **Managed machines.** On a machine with managed settings, or for a user signed in with a Team or
   Enterprise plan, the built-in guard `sec-default` holds `classic.*` events, so the log does not
   run there.
2. **No append.** A mod cannot append to a file, so a log that is on costs one process per write
   (or a capped rewrite). The module takes the process per write.
3. **No 64 KB read cap on a parsed payload.** The mod receives the payload already parsed, and has
   no direct equivalent of the script's 64 KB read cap. The module serializes the payload and the
   script still reads only its first 64 KB, so the records keep the cap.
4. **Mods off.** Where mods are off, the log does not run.
5. **No `traceparent`.** A settings hook received `TRACEPARENT` when tracing was on, and a mod
   receives no per-hook trace context, so records written by the module carry no `traceparent` key.
   The module clears `TRACEPARENT` rather than pass on a value the Claude Code process itself holds.
6. **CLI-only writes.** The per-build types declare `$.process` "CLI only". On a host where mods load
   but `$.process.run` cannot start a command, the module writes nothing and logs that once to the
   debug log, where the settings rows wrote. Which hosts those are is not probed.

## Alternatives considered

- **Split the log into its own opt-in plugin** (#6246, option B). Off would mean not installed. Rejected:
  a new plugin, a migration for anyone who enabled the option, and a second home for harness-ops
  observability.
- **Keep the rows and correct the option's description** (#6246, option C). Rejected: it documents
  the per-event node start instead of removing it.
- **Write the record in the module and use a process only to append.** Rejected: two formatters of
  one record, against ADR 0052's one implementation at a time, for no saving, since an append still
  needs a process.
- **Keep the settings rows as a fallback where mods are off.** Rejected by ADR 0052: two
  implementations of one behavior running at once.

## Consequences

- With the log off, a session starts no harness-ops process on the 28 events the rows covered. The
  per-turn saving is one node start for each prompt, each tool batch and each `Stop`, plus two per
  subagent, and one for each less frequent event.
- With the log on, the cost per event is what the settings rows cost: one node process that resolves
  bash and runs the script.
- The log needs Claude Code 2.1.287 or later with mods on.
- Option values reach the module from the same `pluginConfigs` the settings rows read (user or
  managed scope), so `session_log_pre_prune_command` keeps its trust boundary.
- `scripts/gen-hook-event-registry.test.sh` asserts the generated module block and the absence of
  event-log rows in `hooks.json`, in place of the retired producer rows.
