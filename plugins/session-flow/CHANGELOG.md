# Changelog — session-flow plugin

## 0.6.0 — 2026-07-16

Changed:

- orchestration-brief renamed to `orchestrate`. The default action
  arms/primes the current session — the skill's primary job — which the old
  name undersold by foregrounding the secondary export brief; the verb also
  matches the action-skill naming convention. Invocation is now
  `/session-flow:orchestrate`; the old `/session-flow:orchestration-brief`
  token no longer resolves. Export modes are unchanged (`handoff` / `worker`
  args), and the exported document is still an orchestration brief.

Added:

- orchestrate: seventh imperative CALIBRATE TO CONDITIONS — size the whole
  orchestration (whether to delegate at all, fan-out width, nesting depth) to
  the active model's capability, advisor/verifier availability, context
  pressure, and concurrent-session / rate-limit headroom, with
  small/medium/large fan-out sizing and single-agent as the floor.

## 0.5.0 — 2026-07-15

Added:

- handoff: mandatory redaction pass over ALL outbound handoff content
  (file, resume prompt, `--bg` launch) — secrets/tokens/credentials/PII
  replaced with shape markers before anything is written or emitted; the
  `--bg` process-argument visibility note now leans on it. New checklist
  ticks on both paths.
- handoff: mandatory "Suggested skills" body section — fully-qualified,
  "if installed"-qualified forward pointers naming the skills the
  resuming session should invoke for the remaining work (eight body
  sections now).
- handoff: fork-beats-compaction guidance — once the session is deep
  enough into its context window that reasoning quality degrades
  (roughly beyond the final third), a fresh-session fork from the
  handoff file beats continuing over a compacted history; threshold is
  relative, never a token count.
- handoff: re-read-from-disk + append-over-rewrite discipline when
  extending a handoff file that already exists on disk.
- workflow: on-ramp classes that merge into the stage sequence partway
  (raw bug/issue intake via diagnosis into implement, foggy
  too-big-to-plan efforts via wayfinding into plan, codebase-upkeep
  findings entering a fresh cycle), with graceful if-installed
  cross-plugin routing and no enumerated skill catalog.
- workflow: single-owner routing when two adjacent capabilities both
  fit — exclusion language wins, then the more specific claim, then the
  earlier stage.
- workflow: stale-map gotcha — re-check the described flows against the
  actual capability inventory whenever capabilities are added, renamed,
  or retired.

## 0.4.0 — 2026-07-15

Added:

- retro: `reference/ecosystem-improvement-catalog.md` — placement decision
  tree (project vs personal scope, laptop-dies test), per-target
  recommendation formats (memory, rules, hooks, skills, agents, MCP
  servers, settings), and a hook-event table verified against the current
  official hooks docs. Loaded by session-mode Phase 3.
- handoff: `context/gotchas.md` — failure patterns (prompt-only when
  durability is required, plan-anticipated work dropped on batch pushback,
  handoff without verifiable sanity-check evidence, continuing past an
  explicit stop). Loaded on demand from the SKILL.md checklist.

## 0.3.0 — 2026-07-14

Adopt the marketplace topic-docs convention
(`docs/conventions/topic-docs/`, contract v1.0.0):

- Handoff save-points move from `.claude/handoffs/` to the memory
  tier's concern-scoped handoffs directory — `<memory_dir>/handoffs/`
  (default `.work/handoffs/`), never committed. The workflow
  checklist moves to the topic's own memory slice —
  `<memory_dir>/<slug>/workflow-checklist.md` (default
  `.work/<slug>/`), a per-topic stage ledger: a fixed filename in the
  shared handoffs directory would clobber across two in-flight
  topics. The session's first memory-tier write verifies the resolved
  memory root's self-ignore guard (a `.gitignore` containing `*`),
  creating it (announced) when absent. No skill edits the consumer's
  root `.gitignore`. A consumer-declared convention
  (`.claude/topic-docs.yaml`, `CLAUDE.md` / rules) still wins;
  filename timestamps stay ISO-basic UTC.
- New `reference/topic-docs.md` — the plugin's binding to the contract
  (memory tier, handoffs concern directory, resolution order, guards).
  The handoff, workflow, and retro skills resolve placement through
  it; none bakes its own paths.
- The prior `.claude/handoffs/` location is retired outright — no
  compatibility layer, no dual-read window, no migration tooling;
  move residual content manually.
