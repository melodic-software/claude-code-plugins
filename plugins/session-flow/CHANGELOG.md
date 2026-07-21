# Changelog — session-flow plugin

## [0.12.3]

### Changed

- orchestrate: sharpened imperative 7's per-worker tiering into an explicit volume-based default.
  Past a wide fan-out the cheaper tier is now the DEFAULT the whole fleet inherits (volume
  multiplies every notch of over-provisioning), with an explicitly-hard stage (verify,
  judge/adjudicate, judgment-heavy synthesis) as the standing exception that keeps the parent
  tier — closing the residual enhancement from the spawn-inherit fix. Tier is also broadened
  beyond model to reasoning effort: the doc-confirmed per-worker `effort` lever means a cheaper
  tier can be a cheaper model, a lower effort, or both. Guidance stays model-/tool-agnostic in the
  imperatives and export brief; the version-pinned platform specifics behind it (the fleet-model
  inherit mechanism, the platform's own wide-run threshold, and the `effort` enum) are recorded as
  citations in the skill's `context/sources.md`.

## [0.12.2]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.12.1] — 2026-07-21

Changed:

- handoff: the "Full-path write procedure" doc's `MEMORY_ROOT` placeholder
  note now points at the shared `parse-concern-value.sh` helper (the
  retro skill's Phase 1.1 snippet is the worked call form) instead of a
  bare "resolve it first" reminder with no mechanism named. Doc pointer
  only — the handoff skill has no script of its own to rewire.

## [0.12.0] — 2026-07-21

Added:

- orient: new skill. Read-only session orientation — answers "where do we stand,
  what are we doing, and why" by synthesizing both the live conversation and the
  durable, off-thread state a conversation does not hold: handoff save-points,
  the workflow checklist, running-retro ledgers (resolved through the plugin's
  topic-docs binding), plus git state, open PRs, open work-items, and a glance at
  off-thread work. It complements the built-in `/recap` (conversation-only,
  auto-fires) by adding the durable layer recap never sees; a skill cannot invoke
  `/recap` (built-ins other than a small allowlist are not Skill-invocable), so it
  synthesizes the conversation summary inline. Strictly read-only: it writes
  nothing, ends nothing, and routes rather than acts — freshness verification to
  `reanchor`, off-thread recovery to `keep-going`, next-stage to `workflow`,
  learnings to `retro`. The plugin now bundles nine skills.

Changed:

- keep-going: hardened. (1) Broadened from "after an interruption" to also cover
  a live-session poke — "check the monitor", "poke it", "is it stuck", "stop
  staring at it" — with an active-verification protocol: read the real
  monitor/subagent output first, treat progress-vs-elapsed as a suspicion-raiser
  only, and act on evidence; killing or restarting off-thread work is now gated
  as a side effect so live-but-slow work is not killed on a hunch. (2) Usage-limit
  stall fix: once a limit lifts and the session is executing again the block is
  already over, so it continues rather than summarizing-and-stalling; the
  time-vs-reset check is scoped to the orchestration case (a limited worker),
  reset information being available in-session only via the limit message text and
  interactive `/usage`. While still blocked it hands back via `/session-flow:handoff`
  rather than self-arming a scheduler. (3) Intent is inferred from the
  conversation, arguments optional. Existing recovery behavior and all prior
  trigger phrases are preserved.

## [0.11.0] — 2026-07-20

Added:

- running-retro: new skill. Takes an in-flight retrospective checkpoint
  mid-session — the live counterpart to `retro`'s end-of-session pass. Zero-arm:
  nothing to set up in advance, because the session transcript on disk is
  lossless across compaction (the same record `retro`'s parser already reads in
  production). The main agent contributes a 2-3 line subjective-state note — the
  one signal disk cannot hold — then delegates the analysis to a fresh subagent
  that runs `retro`'s parser and selectively reads flagged transcript spans,
  classifies each finding by category and suggested resolution route (CLAUDE.md
  fix / rule fix / skill change / new-skill candidate / tracker issue), and
  returns a compact findings block. Findings append to a cumulative running
  ledger — one stable file per session chain — resolved through the plugin's
  topic-docs binding (`<memory_dir>/running-retros/`, default
  `.work/running-retros/`, memory-tier, never committed). It captures and routes
  only: codification stays with `/session-flow:retro codify`, tracker filing is
  offered never automatic, the session is never scored, and the skill is
  non-terminating (unlike `handoff`, it does not `/clear`). A mandatory redaction
  pass runs on both the subagent findings and the ledger write. Composes with
  `/loop` for periodic checkpoints; ships no scheduler of its own. The plugin now
  bundles eight skills.

## [0.10.4] — 2026-07-20

Fixed:

- retro: the Phase 1.1 multi-session snippet no longer truncates a quoted
  `memory_dir` at an interior `#`. `HANDOFF_DIR` resolution now routes through the
  shared `parse-concern-value.sh` helper (materialized from
  `lib/parse-concern-value.sh`), which peels surrounding quotes *before* stripping
  comments, so `memory_dir: "a#b"` resolves to `a#b` rather than `a`. The snippet
  also surfaces resolution rung 2 — a save-point convention inferred from
  `CLAUDE.md` / `.claude/rules`, passed as `DECLARED_SAVEPOINT` — instead of
  collapsing straight from an absent concern file to `.work`; prose stays an
  inference source the agent resolves, not a machine key.
- retro: a comment-only `memory_dir` (e.g. `memory_dir: # use default`, YAML-null)
  now resolves through the fallback instead of being taken literally as
  `# use default/handoffs`, so the handoff-chain search degrades to the declared
  save-point / `.work` default rather than a bogus directory.

## [0.10.3] — 2026-07-19

Changed:

- workflow / retro: the override boundary is now explicit. The stage taxonomy
  and the pre-PR sequence skeleton (workflow) and the five scoring dimensions
  (retro) are documented as fixed plugin identity with no consumer-config seam
  to swap them — what adapts is stage execution, gate commands, and the
  conventions each dimension scores against, all flowing through the consumer
  conventions the skills already name, never by editing the plugin. Documents
  the existing boundary per the extensibility contract; no behavior change.

## [0.10.2] — 2026-07-19

Fixed:

- retro: the Phase 1.1 multi-session snippet now derives `HANDOFF_DIR` from the
  resolved `memory_dir` (reads the `.claude/topic-docs.yaml` concern file, falls
  back to `.work`) instead of hard-coding the bare default `.work/handoffs`. A
  copy-as-is run of the snippet previously bypassed the memory_dir seam, missing
  the handoff chain in any repo that relocates its memory tier.

## [0.10.1] — 2026-07-19

Changed:

- Topic-docs binding points instead of restating (fleet conformance wave,
  registry single-home): the binding doc no longer restates the contract's
  five-rung resolution order and runtime guards — it applies the contract's
  own sections and keeps only the plugin-specific no-project-root fallback
  detail.

## [0.10.0] — 2026-07-18

Added:

- clean-stop: new skill. Gets a session to a durable, linked stopping point
  before the machine may go away — inspect every repo/worktree touched, push
  unpushed or coherently committable work durable (surfacing ambiguous WIP and
  stashes rather than force-committing or dropping them), ensure every pushed
  branch has a PR, file follow-ups as issues linked to that PR, and put the
  resume context in PR/issue bodies (never only a local file) to a cold-agent
  acceptance bar. Prunes only provably-safe branches and worktrees; gates
  destructive cleanup on proven safety. Closes on a free-and-clear verdict or a
  named dangling list. It is the go/stop mirror of keep-going (which recovers
  after an interruption; this makes the interruption safe beforehand) and
  supersedes a local handoff when the machine itself may go away. PR / issue /
  worktree mechanics route to whatever capabilities are installed, falling back
  to direct git / gh. The plugin now bundles seven skills.

## [0.9.1] — 2026-07-18

Fixed:

- orchestrate: worker model tier is now an explicit spawn decision. SPEC EVERY SPAWN adds the
  model tier to the per-worker spec, and CALIBRATE TO CONDITIONS adds per-worker tiering (cheap
  tier for high-volume mechanical work, parent tier reserved for judgment-heavy
  synthesis/verify; wider fan-out defaults cheaper). Closes the failure mode where a wide
  fan-out silently inherited the parent session's premium model on every worker — an omitted
  model defaults to `inherit` per the subagents doc (resolution order and cost-control quote
  now cited in `context/sources.md`).

## [0.9.0] — 2026-07-18

Added:

- reanchor: new skill. Verifies a session's working assumptions against live
  reality before it builds on them — for the PRs/issues/branches a handoff or
  locked plan references it confirms each is still in the claimed state, reports
  current behind-base divergence, confirms cited skills/plugins still exist under
  that name and that installed versions match the repo source, and flags
  memory-tier entries whose subjects have since landed. It reports the drift and
  re-anchors; it does not resume the work (the keep-going sibling), enumerate
  worktrees, or triage PR feedback. The plugin now bundles six skills.

## [0.8.0] — 2026-07-17

Changed:

- Adopt topic-docs contract 2.0.0 (visibility semantics): `reference/topic-docs.md` states
  handoffs and the workflow checklist are checkout-local; the checklist is the stage-ledger kind
  the contract's `.worktreeinclude` template carries into new worktrees, while handoffs are
  session-scoped and deliberately not carried.

## [0.7.1]

### Changed

- References to the renamed `/planning:plan` skill (was `/planning:architect`, planning 0.13.0 breaking rename) retargeted. Version bumped so existing installs receive the rewritten prompts.

## [0.7.0] — 2026-07-17

Added:

- keep-going: new skill. Recovers and continues a session after any
  interruption (rate limit, crash, disconnect, gap) — inventory off-thread
  work, inspect each item's real state from its artifact rather than
  assuming, resume the resumable / restart the dead / surface the
  unrecoverable, then reconcile the main thread from a fresh read of its
  backing plan or handoff file and continue. Safe/idempotent work
  auto-resumes; re-running side-effectful work (push, PR comment, deploy) is
  gated against double-firing. It is the resume counterpart to handoff, and
  the interruption cause is deliberately not diagnosed (recovery is
  identical regardless). The plugin now bundles five skills.

## [0.6.0] — 2026-07-16

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

## [0.5.0] — 2026-07-15

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

## [0.4.0] — 2026-07-15

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

## [0.3.0] — 2026-07-14

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
