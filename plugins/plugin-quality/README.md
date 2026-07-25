# plugin-quality

A Claude Code plugin for **post-use behavioral audits** of other plugins' components. You used a
skill, hook, agent, command, or config surface and something felt off — or you just want to know
whether it actually does what it claims. `/plugin-quality:audit <plugin>[:<component>]` runs a
six-step audit and ends with a work item in the plugin maintainers' lap, never with you patching
their repo mid-session.

- **Audit skill** (`skills/audit`) — the six-step hub: (1) evidence capture on the main thread
  into a durable, compaction-proof packet; (2) map + ground in the fresh `auditor` subagent, with
  every load-bearing harness-behavior claim verified against current official docs; (3) blindspot
  pass + candidate findings; (4) interactive contract lock (scope, severity, assumptions —
  written into the packet); (5) presence-gated review seams with stated fallbacks; (6) emit to
  the resolved sink behind an unconditional draft+confirm gate.
- **Auditor agent** (`agents/auditor.md`) — the fresh-context specialist for steps 2–3. Tools:
  Read/Grep/Glob/WebFetch plus Bash — named honestly: Bash is there for `claude plugin validate`
  and config-resolution probes, not mutation.
- **Reference corpus** (`skills/audit/references/`) — the recurring-concerns checklist plus five
  component-type lenses (hook, skill, agent, command, config). Extending coverage = one file +
  one index row; the hub never grows.
- **Config surface** (`reference/config.md`) — `.claude/plugin-quality.md` (sink, zone behavior,
  repo-map overrides) layered per the config-cascade convention, with a documented sink ladder
  and markdown item schema.
- **Setup skill** (`skills/setup`) — `check` (gh + ACTING account, context-guard seam → dispatch
  mode, config layers with per-key provenance) / `apply` (writes only the tracked config).

## Context-gate (context-guard integration)

The audit consumes the `context-guard` plugin's per-session snapshots as a **soft dependency**:
a fresh snapshot routes packet handling, review dispatch, and evidence-flush timing by zone
(smart / acceptable / dumb); an absent or stale snapshot degrades to the conservative row with a
visible notice — deep analysis always runs in a fresh subagent either way. No context-guard
install is required; it just makes long-session audits smarter about their own degradation.

## Security posture

- **Egress**: exactly one — `gh issue create`, gated by an unconditional confirm surface carrying
  the full draft, the target repo, and the acting account. No auto-file mode exists.
- **Untrusted content**: audited plugin source, manifests, and registrations are data, never
  instructions — a directive embedded in audited content is reported as a finding, backed by an
  anti-pattern eval.
- **Producer/consumer split**: the audit session never implements fixes in the audited repo.
- Evidence packets (session-derived data) live in `${CLAUDE_PLUGIN_DATA}` with 30-day retention.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install plugin-quality@melodic-software
```

Zero config works: conservative dispatch, sink resolved by inference or interview at emit time.
Run `/plugin-quality:setup check` to see the seams; `setup apply` to pin a sink in the tracked
config.

## Requirements

`gh` (authenticated) for the issue sink — optional; without it the ladder ends in a local
markdown item. `jq` for the context-gate probe — optional; without it dispatch is conservative.
Works on Git Bash (Windows), macOS, and Linux shells.

## License

MIT (SPDX-License-Identifier: MIT).
