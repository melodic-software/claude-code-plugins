# harness-ops

The skills of `plugins/harness-ops`. Each one is driven with `<plugin-dir>` set to `plugins/harness-ops`.

## Parts

- `audit-install-state`: Audit a Claude Code install directory. What is there, what the product manages, what is stale.
- `audit-mod-posture`: Inventory installed and built-in mods with their hooks and calls, and the guard state.
- `audit-native-overlap`: Map native Claude Code surfaces against this repo's components and record owner-directed verdicts.
- `audit-performance`: Capture slowness evidence while slow. Version, sweep health, tree walk, sessions, fleet, fan-out.
- `audit-plugin-landscape`: Report plugin and marketplace staleness, overlaps and alternatives; recommend only. No plain-words entry.
- `audit-skill-visibility`: Which skills the model can actually see, which are starved, and which are unobservable.
- `behavior-probes`: Run data-driven live probes of Claude Code permission and platform behavior and record the outcomes.
- `changelog`: Ingest a Claude Code release changelog and integrate its changes into the repo.
- `check`: Report whether node and jq resolve for the harness-ops hooks. Never installs.
- `control-claude-code`: Control skill /app-control:drive reads to run Claude Code's terminal UI with a plugin loaded and record screenshots ... No plain-words entry.
- `inventory`: Enumerate every command, skill, agent, and plugin component this machine can invoke.
- `known-issues`: Look up and track known Claude product issues, health, and workarounds.
- `lanes`: Start, restart, stop, and check loop lanes as named background sessions. No plain-words entry.
- `machine-profile`: Discover, store and diff machine facts and per-tree identity domains. Read-only by default.
- `morning-brief`: Print the operator's read-only morning view. Queues, merge-ready PRs, parked decisions.
- `observability`: Report on locally captured telemetry. Token burn, cost, hook latency, per-session activity.
- `plugins`: Bring the machine's plugin fleet current. Refresh, update, install per policy. No plain-words entry.
- `prerequisites`: Report external tools the enabled fleet declares missing. Never installs.
- `setup`: Verify harness-ops's personal path configuration for this repository (where the known-issues registry, the skill-usage ... No plain-words entry.

## Sub-features

none

## Entry points

- `/harness-ops:<skill> <args>` as the `logs` prompt, in print mode | driven
- `/harness-ops:<skill> <args>`, typed at the prompt of the terminal session | driven
- A request in plain words that names the skill's job, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

The `## Reset` of the driving tool's `skills/invoke` feature.

## Drive

Drive the skill as the driving tool's `skills/invoke` feature, with `<plugin>` set to `harness-ops` and
`<skill>` from Parts. The skill's own `plugins/harness-ops/skills/<skill>/SKILL.md` gives its arguments.

## Gotchas

- A skill marked `No slash command.` runs only from its plain-words entry point; one marked `No plain-words entry.` runs only from its slash command.
