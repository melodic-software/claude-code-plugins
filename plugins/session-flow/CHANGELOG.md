# Changelog — session-flow plugin

## [0.17.3]

### Fixed

- **The shared concern-value parser no longer reads a declared key as absent over YAML key spacing.**
  `parse-concern-value.sh` anchored on the exact regex `^<key>:`, so `memory_dir : .work` (YAML
  permits whitespace before the `:`) and a root block mapping written at a uniform indent both
  resolved to the caller's fallback — substituting a value the repo never chose for one it did.
  Both shapes now resolve, with an unindented key preferred so a nested key of the same name cannot
  outrank the top-level one. Synced from `lib/parse-concern-value.sh`; version bumped so installed
  copies receive it.

## [0.17.2]

### Fixed

- **Setup's headless reconfigure recipe no longer claims `-y` is CLI-required for a non-TTY
  `uninstall`.** Verified against the live CLI (2.1.220) and current docs: `-y` only skips
  `uninstall`'s `--prune` confirmation, and this recipe never passes `--prune` — so `-y` had no
  effect and is no longer part of the recipe (#1410).

## [0.17.1]

### Changed

- **Setup's `apply` now documents the headless reconfiguration route beside the interactive one.**
  Every observer tunable is native `userConfig`, and `apply` routed reconfiguration through
  `/plugin configure session-flow` only. A headless or CI consumer reading that had no path at all,
  and the obvious guess — re-running `claude plugin install --config` — silently does nothing on an
  already-installed plugin, so the reader would have concluded the value was set when it was not.
  The flag's fresh-install-only behavior is now stated where the reconfiguration guidance lives,
  along with the uninstall-then-reinstall route it forces and the note that one install should carry
  every key being changed. The recipe passes `-s <scope>` on both halves and `-y` on the uninstall:
  both commands default to `-s user`, so an unscoped pair removes a separate user record while a
  project- or local-scoped install keeps loading, and a non-TTY uninstall requires the confirmation
  flag to run at all.

## [0.17.0]

### Changed

- **handoff: the save-point body-section taxonomy is restructured.** The old eight sections led with
  the costly layer — a resuming session learned what to do next in section six of eight — which
  inverts the ladder the org's `progressive-disclosure` convention prescribes. The set now opens
  with a six-line `Resumption brief` a reader can stop at, and the remaining sections are ordered
  frame, world, memory, frontier. Three kinds of state that previously had no home are now owned:
  invariants that must hold, persistent side effects that must not be repeated, and hard-won
  findings that are neither a decision nor a failed approach. `Open questions / next steps` is split
  four ways — a slash in a heading meant it owned more than one taxon, and its numbered list mixed
  the ordered remainder of the work with self-resolvable unknowns and outside blockers — and the
  `Progress` / `Files modified` overlap is resolved into a single file-role map. Every section is now always
  present, with an explicit "nothing to report" rather than an omission, so a cold reader can tell
  silence from oversight. The file-role map owns *how far each file's change got*, not just its
  role: the old blanket "nothing about what changed inside it" left completed progress and
  half-finished uncommitted edits with no owner at all — completion criteria describe outcomes and
  the ordered remainder describes future work — so a cold session had to reconstruct both from the
  working tree, the exact rediscovery this document exists to prevent. Committed work still points
  at its commit range rather than transcribing a diff; uncommitted or half-done work says which part
  is implemented and working and which part is not, because no commit records that.
- **handoff: the emitted resume directive no longer names a section.** It read
  `continue per its "Open questions / next steps"`; it now reads `continue its remaining next steps`.
  The heading was the only runtime coupling to the taxonomy, so the section set can move again
  without touching `save-point.md`, and handoffs already on disk stay resumable. Nothing parses a
  handoff body heading, so existing save-points are unaffected.
- **handoff: consumers cite the section list instead of restating it.** `save-point.md` carried a
  full inline recap that had already drifted from the owner doc on two of eight names, and four more
  files carried partial or differently-spelled copies — one section had accumulated five spellings.
  Per the org's `reference-dont-duplicate` convention a closed enumeration is a mapping table that
  must be cited, never recapped, so `reference/structure.md` is now the single home and the copies
  are pointers.
- **handoff: the "all eight body sections present" checklist assertion is retired.** A count is
  satisfiable by eight wrong sections, it has gone stale before, and it duplicated a value derivable
  from the doc it described. The checklist now walks the structure doc.
- **orchestrate: documents the shape of a multi-tier delegation tree** — what the top tier owns,
  why coordination belongs low in the chain, what a tier-crossing return payload should carry,
  ephemerality as a cost control rather than tidiness, and why a clean worker return is not
  evidence of a correct one. No new machinery; the existing imperatives already permit the tree,
  this names its shape.

### Removed

- **handoff: the write-only `previous_session_id` frontmatter field.** The chain walker
  (`skills/retro/scripts/parse_transcript.py`) only ever read `session_id` and `previous_handoff`;
  the third field was written by the spec, asserted by five documents, seeded by test fixtures, and
  consumed by nothing. Storing the prior session's id in a second place invited the two pointers to
  disagree — the walker resolves it by reading the prior file's own `session_id`. Chain-walking is
  unchanged, verified by the existing chain tests with the field removed from their fixtures.
  The `running-retro` ledger's own `previous_session_id` is a separate, live field and is untouched.

## [0.16.0]

### Added

- find-handoff: new skill (#976). Recovers a lost handoff after `/clear` — the
  failure mode where `/session-flow:handoff` wrote a save-point but the operator
  cleared the session before copying the dashed-rail resume prompt, leaving the
  fresh session with zero context and no path to the handoff on disk. Runs a
  read-only detection ladder: known-location glob of the current repo's
  `<memory_dir>/handoffs/`, then a bounded, recency-ranked scan of transcripts
  (excluding the current session's own file — `/clear` opens a new transcript in
  the same project dir, so the pre-clear content is a sibling) for the handoff
  directive and dashed-rail markers, then a confirm-before-resume gate. Detection
  is substring matching over transcript JSONL (empirically verified: the
  `Read @…-handoff-*.md` directive and `─` rails survive verbatim), not JSON
  parsing — so the skill ships no parser and does not couple to `retro`'s
  transcript parser. Handles both handoff output modes (file-based and
  prompt-only, which writes no file). Read-only and redaction-aware throughout:
  surfaces only the resume prompt + handoff metadata, never raw transcript
  content. Routes to `/session-flow:keep-going` when the recovered session ended
  mid-work. Chains in from `keep-going` step 4 when a post-`/clear` session has no
  known handoff path.

### Changed

- reference/save-point.md: documented the resume-prompt output shape (the
  `Read @…-handoff-*.md` directive, the `─` rails + instruction line, and
  `Prior session: <UUID>`) as a stable detection contract `find-handoff` keys
  off, so a future format change is a knowing break. reference/structure.md notes
  the `type: handoff` frontmatter is part of the same contract, and
  reference/topic-docs.md lists `find-handoff` among the skills that read the
  topic-docs binding to locate the handoffs directory. keep-going step 4 routes
  to `find-handoff` when the handoff path was lost.

## [0.15.2]

### Fixed

- **`reanchor`'s eval case 7 renamed off the pre-rename plugin name (`#1328`).**
  `skills/reanchor/evals/evals.json` still named the negative-routing case
  `negative-routing-rule-discipline-is-re-anchor-plugin` after the `re-anchor` -> `discipline`
  plugin rename (`#1276`); the case's `expected_output` and `expectations` were rewritten in that
  commit but its `id` field was missed. Renamed to
  `negative-routing-rule-discipline-is-discipline-plugin`, matching the sibling
  `negative-routing-*` case names. No other file references the old name.

## [0.15.1]

### Changed

- All five skills whose pre-computed context block injects the session id
  (`orient`, `retro`, `running-retro`, `handoff`, `continue-in-background`) now
  carry a `|| echo "unknown"` fallback on that injection, matching the sibling
  git injections in the same block. Injection failure, timeout, and stderr
  semantics are undocumented upstream, so the standing convention is a
  `|| <fallback>` on every injected command — `skill-quality:check` flags a
  missing one as an advisory WARN. On this particular line the guard is
  unreachable in practice (`${VAR:-unknown}` resolves at expansion time, so
  `echo` receives a formed string and exits 0); it buys block-wide uniformity
  and a quiet gate, not protection against a failure mode the sibling git lines
  genuinely have.

## [0.15.0]

### Added

- running-retro: detached-observer substrate + lifecycle. Evolves running-retro
  from PULL-only (invoked in-session) to a path that can also fire *after* the
  session ends — a `/loop` structurally cannot. A stdlib-only Python 3.10+ tailer
  (`skills/running-retro/scripts/observer.py`, launched detached by
  `arm_observer.py`) outlives the session, tails the transcript out-of-band at
  zero context cost via a no-persistent-handle poll→open→read-new-bytes→close
  loop (safe by construction against the Windows share-mode write edge), detects
  end by mtime-idle, then runs the same checkpoint method headless (a cheap
  `claude -p`) and appends the redacted findings to this session's ledger. The
  analysis run is Read-only (`--allowedTools Read` under `--permission-mode
  dontAsk`) — no code execution over untrusted transcript content — and is the
  single semantic redaction pass; the transient distilled observations are
  machine-local (`${CLAUDE_PLUGIN_DATA}/session-flow-observer/`) and deleted
  after use, so only redacted findings reach the durable ledger. Entry: a new
  `arm` action on running-retro is primary; an OPT-IN SessionStart hook
  (`observer_enabled`, default off — zero-config behavior unchanged) automates the
  same launcher, guarded against self-arming (`CLAUDE_CODE_ENTRYPOINT`, stdin
  `agent_type`, `source`, analysis-run marker). Untrusted-data boundary cites the
  shared `reference/off-thread-work.md`. Native Observer-Agents recorded as a
  deferred alternative (trigger: transcript-level feed / documented-stabilized
  upstream), substrate kept thin so migration stays cheap. Full substrate +
  lifecycle in `reference/observer.md`. The plugin now bundles twelve skills.
- setup: new check-centric skill (`disable-model-invocation`), added because the
  observer introduced an external prerequisite (Python 3.10+) and a `userConfig`
  surface — the uniform setup contract's trigger. `check` verifies the observer's
  prerequisites (Python 3.10+, `jq`, `claude` on PATH) and reports the effective
  config, flagging the `--bare`/OAuth-auth and idle-threshold hazards; no write
  path (reconfiguration routes through `/plugin configure`).
- `userConfig`: the plugin's first config surface — six observer keys
  (`observer_enabled`, `observer_analysis_enabled`, `observer_analysis_model`
  [default `claude-haiku-4-5`, the cost lever], `observer_analysis_bare`,
  `observer_idle_seconds`, `observer_max_seconds`), all defaulting to zero-config
  behavior.
- hooks: opt-in `SessionStart` hook (`hooks/observer-arm.sh`) — the plugin's
  first hook asset; no-ops unless `observer_enabled` is on.

### Notes

- `--bare` on the analysis run is off by default and gated behind
  `observer_analysis_bare`: verified on CLI 2.1.218, `--bare` drops the OAuth-login
  credential state and the run reports "Not logged in". The measured cost lever is
  the model, not `--bare` (which was a projected, never-measured optimization in
  the design memo). Enable it only where auth is an env-var API key that survives it.

## [0.14.0]

### Added

- reconcile: new skill. The prune-and-reconcile counterpart to
  `keep-going`'s resume — where keep-going asks "is it stuck, pick it back up",
  reconcile asks "is anything still running that should be retired, and
  does the task ledger
  match reality?" Inventories the off-thread work this session spawned, inspects
  each item's real state, retires the genuinely finished by clearing them from
  tracking, and closes this session's task-ledger items whose work is proven
  complete. Also reports the read-only liveness of sibling sessions in the same
  project — transcript mtime plus a coarse tail read, never a deep parse of the
  officially-unstable JSONL. Auto-settles the provably-finished (closing a task
  is evidence-gated — the mirror of keep-going's "never kill what you cannot
  prove is dead"); GATES any kill of still-running work, the gate kept in-skill
  because the three inventory skills' blast radii differ. Fixes this session
  only: sibling sessions are visible but report-only, and a spawned subagent's
  internal task list is not readable. MCP / browser / playwright tool-state
  enumeration is deferred with a trigger (no generic tool-state surface exists;
  closing user-owned state would be destructive-against-user). The plugin now
  bundles eleven skills.
- reference/off-thread-work.md: shared engine doc. The open-ended
  off-thread-work inventory kinds and the inspect-real-state-first invariant —
  the mechanics `keep-going`, `orient`, and `reconcile` all share (Rule of
  Three) — are extracted to a plugin-level reference all three cite via
  `${CLAUDE_PLUGIN_ROOT}`, each thinned to its own delta (same
  point-not-copy shape as `reference/topic-docs.md` and re-anchor's
  `context/re-anchor-audit-correct.md` engine doc). The three skills' autonomy
  gates are deliberately NOT extracted — different blast radii, kept in-skill.

### Changed

- keep-going: inventory + inspect steps now cite the shared
  `reference/off-thread-work.md` for the off-thread kinds and the
  inspect-real-state invariant rather than restating them inline; the duplicated
  "tools change over time" gotcha (now owned by the shared doc) is removed. The
  richer Active-verification protocol stays in keep-going (reconcile
  cites it). Description gains a reciprocal boundary line pointing at
  `reconcile` for
  retire/reconcile vs resume; all prior trigger phrases preserved.
- orient: the off-thread-work glance in "What it reads" now points at the shared
  `reference/off-thread-work.md` for the full open-ended kinds set while keeping
  its at-a-glance examples; no behavior change.

## [0.13.1]

### Changed

- Fresh-eyes review/verify delegation sites now prefer a cross-vendor
  advisor when one is installed, with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing
  convention (#933). `workflow`'s Review stage (`context/steps.md`) names
  the example command (the OpenAI Codex plugin, invoked per its own docs);
  `orchestrate`'s fresh-context-verify imperative states the preference
  tool-agnostically and names no command, because that imperative is
  exported verbatim into the skill's model- and tool-agnostic
  worker/handoff brief, where a named command would be exactly the
  unresolvable route the rule forbids.

## [0.13.0]

### Added

- continue-in-background: new skill (#233). Background delegation extracted from
  `/handoff --bg` into its own honestly named, discoverable entry point: produce a
  save-point, then launch a detached `claude --bg` session seeded with the rails
  resume prompt. Owns the delivery: explicit-intent hard gate (model-invocable for
  discoverability, but launches only on the user's explicit request — never
  self-elected, with an eval covering the gate), dirty-tree gate,
  launch + report, fallback-on-failure, and its own STOP rule. Also surfaces the
  The rails prompt is passed to the launch via a temp file rather than an inline
  heredoc — prompt content is untrusted session text, and a crafted line matching
  a heredoc sentinel could otherwise break out of the quoting into the shell; the
  resolved topic slug is sanitized to `[a-z0-9-]` before it reaches the `--name`
  flag for the same reason. Also surfaces the
  launched-session behavior the flag never documented: the agent is a NEW session
  that inherits neither the current session's CLI flags nor its model/effort
  choices — both resolve from the launch command's own flags and the launch
  directory's settings (per the agent-view and env-vars official docs, cited in
  the skill).
- reference/save-point.md: shared save-point engine. Save-point production —
  destination resolution, locate-position, full-vs-prompt-only choice, mandatory
  redaction pass, handoff-file write, rails resume prompt — extracted from the
  handoff skill into a plugin-level reference both delivery skills cite via
  `${CLAUDE_PLUGIN_ROOT}` (same shape as `reference/topic-docs.md`). No content
  duplicated in either skill; no runtime skill-to-skill invocation. The handoff
  document-structure doc moves with it (`skills/handoff/context/structure.md` →
  `reference/structure.md`) so the shared engine never reaches into one
  consumer's internal layout.

### Changed (breaking)

- handoff: `--bg` removed outright — no alias, no deprecation window. `/handoff`
  is now purely the manual `/clear`-then-paste save-point; background delegation
  lives in `continue-in-background`. The background trigger phrase ("continue in
  the background") moves from handoff's description to the new skill's — the
  trigger partition leaves zero overlap. Handoff's two `--bg` evals
  (no-launch-default, dirty-tree fallback) migrate to the new skill's eval set,
  rephrased for the new entry point; handoff keeps default-path coverage.

### Fixed

- retro / handoff: reconciled the "declared save-point" vocabulary mismatch between the
  retro multi-session snippet and the handoff skill's "Where handoffs live". Both now
  consistently name the CLAUDE.md/`.claude/rules`-inferred rung-2 value a **working-docs
  convention** resolving the memory-tier ROOT (`memory_dir`) — never the full handoffs
  path directly. Previously, a declared handoffs location such as `.claude/handoffs`
  passed through retro's snippet doubled into `.claude/handoffs/handoffs` because the
  snippet's "save-point convention" label implied a full location while its code appended
  `/handoffs` to it. The snippet's env var is renamed `DECLARED_SAVEPOINT` ->
  `DECLARED_MEMORY_DIR` to match. The snippet also no longer silently swallows a missing
  handoff chain: an empty `ls` result now surfaces an explicit fallback message and drops
  to the single-session parser form instead of passing an empty `--chain-from` value.

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
