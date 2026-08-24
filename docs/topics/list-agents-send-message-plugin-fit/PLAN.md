# list-agents-send-message-plugin-fit

## Brief

### TLDR

Decide whether the built-in Claude Code tools `ListAgents` and `SendMessage` deserve first-class
treatment in this repo's plugins. Verdict: name the mechanism where posture skills already assume
it, fix two stale in-repo claims, and adopt nothing else yet. Groundwork: a verified
`/discovery:explore` pass over the repo's coordination surfaces and a verifier-passed
`/discovery:research` pass over the official docs (memory slice
`.work/list-agents-send-message-plugin-fit/`, not committed).

### Goal

Close the named-mechanism gap in the orchestration posture skills and correct factual drift, while
keeping the repo's existing governance idiom (presence-gated prose with upstream-drift stamps) as
the only integration mechanism for built-in tools.

### Constraints

- Every baked claim re-verified against the live raw-markdown docs channel the same day, with a
  verbatim quote, URL, as-of date, and an observable recheck trigger (upstream-drift convention).
- Empirical backing where testable: subagent resume via `SendMessage` by agent ID was exercised
  twice in this session (completed researcher and verifier subagents auto-resumed with context
  intact); `ListAgents` confirmed absent from this cloud session's tool pool.
- No `tools:`/`allowed-tools:` frontmatter changes: grants naming these tools are no-ops (they
  never prompt), and the discovery agents deliberately omit allowlists to keep inherited pools.
- Skill descriptions untouched (instruction-economy budget); guidance lands in bodies and
  reference spokes only.

### Acceptance criteria

- `docs/OFFICIAL-DOCS.md` cross-session-messaging row states the version floors instead of the
  stale "not on native Windows", with a refreshed verified date.
- `plugins/session-flow/reference/observer.md` no longer claims agent-teams gating for
  cross-session `SendMessage`; the corrected bullet is quoted and stamped; the durable-ledger
  decision itself is unchanged.
- `plugins/session-flow/skills/orchestrate/SKILL.md` priming addendum names `SendMessage` for
  imperative 4, presence-gated, with quotes and the empirical probe recorded in
  `context/sources.md`; export modes still omit it.
- `plugins/playbooks/skills/fable-5/context/orchestration.md` names the continuation mechanism
  with the auto-resume/refusal caveats, stamped.
- Both touched plugins get a minor version bump and a changelog entry.

### Captured assumptions

- `babysit-prs` needs no edit: its orchestration reference already names `SendMessage` by agent
  id, warns against faking a resume via the `Agent` tool, and falls back to completion
  notifications where messaging is unavailable (re-verified this session).

### Out-of-scope (recorded decisions, with recheck triggers)

- **Dedicated skill for these tools: deferred.** The shipped `SendMessage` schema already teaches
  addressing, resume, anti-polling, and permission-laundering discipline in-session; the residue
  (cross-session setup: `crossSessionInbound`, deny rules, availability matrix) is thin. Recheck
  trigger: a concrete multi-session workflow in this repo needs cross-session configuration
  guidance more than once, or the fleet adopts agent-teams-based workflows.
- **Native-overlap registry lane for built-in tools: declined.** The registry's four lanes
  deliberately exclude built-in tools; upstream-drift stamping is the governing idiom. Recheck
  trigger: built-in-tool references appear in a third plugin (today: discovery, source-control,
  session-flow) or the registry's extraction inputs start enumerating tools.
- **`ListAgents` adoption: wait.** Foreground-and-messaging-enabled only, never in background
  subagent pools, absent from cloud sessions; `find-handoff` already carries a sourced
  `claude agents --json --all` enumeration contract. Recheck trigger: a workflow needs live-agent
  discovery from inside a foreground session, or the tool ships in background/cloud pools (a
  changelog entry touching `ListAgents` availability).
- **Durable-channel designs (observer findings-return, loop-lane escalation,
  continue-in-background): unchanged.** Messaging remains at most a future additive latency layer.
  Recheck trigger: a recorded consent/auditability design for live messaging, or upstream inbound
  approval semantics change materially.

### Deferred questions

None. All five interview questions were answered (register:
`.work/list-agents-send-message-plugin-fit/interview-checklist.md`).

## Plan

(Not filled: the Brief's acceptance criteria were executed directly in the deciding session; see
the branch's commit for the diff.)
