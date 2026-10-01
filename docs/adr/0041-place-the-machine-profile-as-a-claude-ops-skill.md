# Place the machine profile as a claude-ops skill

- Status: accepted
- Date: 2026-09-29

## Context

The [machine profile design](https://github.com/melodic-software/claude-code-plugins/blob/9a0d6f5cf47098fa73bb4b8bb41336be1945c70e/docs/specs/machine-profile-design.md) (issue #4666) describes a
re-runnable profile that discovers host facts once, stores them, and hands each plugin's `setup`
the answers. The design needs one owner. Two placements were on the table: a skill in
`claude-ops`, or a new plugin.

Three existing surfaces sit next to it:

- `claude-ops` owns fleet state and ships `prerequisites` (probes the binaries each enabled plugin
  declares) and `inventory` (lists what this machine can invoke), the two skills the profile reads.
- `machine-health` owns severity, trend, history, and reporting for host findings.
- `claude-config` audits Claude Code configuration files and `claude-memory` audits the
  instruction and memory layer.

## Decision

Place the profile as a skill in `claude-ops`, not as a new plugin.

- **Why not a new plugin.** A new plugin would be a third owner of host facts beside
  `claude-ops` and `machine-health`, and would re-declare tool knowledge the `prerequisites.json`
  manifests already hold.
- **machine-health.** The profile is not a second drift checker. It is the host-fact document
  that machine-health's declared-configuration drift check consumes. The profile records observed
  facts, verdicts, and provenance, and assigns no severity and keeps no history. machine-health
  reads the document and reports findings in its own schema, and does no option discovery. Until
  that check exists, the profile's `diff` is the only consumer.
- **claude-config and claude-memory.** They audit files Claude Code reads (settings, hooks, MCP
  configuration, `CLAUDE.md`, rules, auto-memory) for correctness against upstream docs. The
  profile records what the host contains (binaries, identity domains, tree boundaries, roots),
  not whether a Claude Code file is correct. Where a value belongs to one of those surfaces, the
  profile records the observation and that surface's audit stays the judge of the file.

## Status scope

Accepted. The skill, its scripts, its tests and the `claude-ops` version bump are authorized. The
invocation-mode change (class (ii) and the hidden `setup` skills) and any change to the setup
contract are not part of this decision.

## Consequences

The skill's directory is under `plugins/claude-ops/skills/`. A move to a new plugin would
supersede this record.
