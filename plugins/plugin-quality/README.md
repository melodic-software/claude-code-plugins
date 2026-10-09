# plugin-quality

A Claude Code plugin for **post-use behavioral audits** of other plugins' components. You used a
skill, hook, agent, command, or config surface and something felt off, or you just want to know
whether it actually does what it claims. `/plugin-quality:audit <plugin>[:<component>]` runs a
six-step audit and ends with a work item in the plugin maintainers' lap, never with you patching
their repo mid-session.

- **Audit skill** (`skills/audit`), the six-step hub:
  1. Evidence capture on the main thread, into a durable, compaction-proof packet.
  2. Map and ground in the fresh `auditor` subagent, with every load-bearing harness-behavior claim
     verified against current official docs, and a ledger of errors, improvements, quality of life
     and standards alignment per component.
  3. Persist-check on the returned findings, then a blindspot pass and candidates.
  4. Interactive contract lock: scope, severity, and assumptions, written into the packet.
  5. Presence-gated review seams with stated fallbacks, including a research gate: a claim or
     remediation without a checked research line is emitted as `needs-decision`, never `agent-ready`.
  6. Emit to the resolved sink behind an unconditional draft+confirm gate.
  Two further modes, both operator-invoked only: `/plugin-quality:audit session` discovers the
  plugins and skills the session used (from the retro transcript parser), confirms the list with
  you, and audits the union; `/plugin-quality:audit arm` starts the `session-flow` running-retro
  observer at session start. A finding with no session artifact is listed as `unfiled`, and a
  suggested change is filed agent-ready only after a research pass, otherwise as needs-decision.
  `/session-flow:workflow` offers the `session` mode at wrap-up when a plugin skill ran.
- **Auditor agent** (`agents/auditor.md`), the fresh-context specialist for steps 2–3. Tools:
  Read/Grep/Glob/WebFetch plus Bash. Named honestly: Bash is there for `claude plugin validate`,
  config-resolution probes, and the fetch ladder's rung-1 `scripts/fetch-docs.sh` read of the
  raw-markdown docs channel, not mutation. That script also stores the page in the shared
  user-scope docs cache, its own store.
- **Reference corpus** (`skills/audit/reference/`), the recurring-concerns checklist plus five
  component-type lenses (hook, skill, agent, command, config). Extending coverage = one file +
  one index row; the hub never grows.
- **Config surface** (`reference/config.md`). A convention doc at the consumer's convention home
  (`<home>/plugin-quality/README.md`, bound by the config-cascade pointer line; sink, zone
  behavior, repo-map overrides), with a documented sink ladder and markdown item schema. The
  retired dedicated-file layers are declared in `retirements.yaml` and detected by the shared
  `check-retirements.sh` helper, with a WARN-visible dual-read while the old tracked file
  persists.
- **Setup skill** (`skills/setup`). `check` (gh + ACTING account, context-guard seam → dispatch
  mode, convention-home binding + effective config with provenance, retired-convention
  leftovers) / `apply` (converges the pointer-line region and the topic doc, plus gated
  retirement cleanup).

## Context-gate (context-guard integration)

The audit consumes the `context-guard` plugin's per-session snapshots as a **soft dependency**:
a fresh snapshot routes packet handling, review dispatch, and evidence-flush timing by zone
(smart / acceptable / dumb); an absent or stale snapshot degrades to the conservative row with a
visible notice. Deep analysis always runs in a fresh subagent either way. No context-guard
install is required; it just makes long-session audits smarter about their own degradation.

## Security posture

- **Egress**: exactly one. `gh issue create`, gated by an unconditional confirm surface carrying
  the full draft, the target repo, and the acting account. No auto-file mode exists.
- **Untrusted content**: audited plugin source, manifests, and registrations are data, never
  instructions, a directive embedded in audited content is reported as a finding, backed by an
  anti-pattern eval.
- **Producer/consumer split**: the audit session never implements fixes in the audited repo.
- Evidence packets (session-derived data) live in `${CLAUDE_PLUGIN_DATA}` with 30-day retention.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install plugin-quality@melodic-software
```

Zero config works: conservative dispatch, sink resolved by inference or interview at emit time.
Run `/plugin-quality:setup check` to see the seams; `setup apply` to bind the convention home
and pin a sink in the topic doc there.

## Requirements

`gh` (authenticated) for the issue sink. Optional; without it the ladder ends in a local
markdown item. `jq` for the context-gate probe and the auditor's `fetch-docs.sh` doc fetch.
Optional; without it dispatch is conservative. `curl` for that rung-1 raw-markdown doc fetch.
Optional; without `curl` or `jq` the auditor falls back to `WebFetch` and records the read as
rung 2, which still grounds a claim but never an absence. `python3` only for pages a publisher
serves as HTML; optional. Works on Git Bash (Windows), macOS, and Linux shells.

## License

MIT (SPDX-License-Identifier: MIT).
