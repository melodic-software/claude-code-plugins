# autonomy

Governed autonomous agent operation. This plugin is the capability-distribution home for the
AI-adoption-ladder contract set: it ships the tool-agnostic contracts an adopting org binds to
its own repositories, tools, and policies, plus a guided-setup skill that discovers the org's
state and records that binding.

## Shipped capability (0.7.0)

- **Topology contracts** (`reference/`): role topology for the repositories an adoption spans,
  the binding-seam shape that maps contract roles to an org's real instances, and the
  wiring-vs-advisor principle governing how setup lands changes.
- **Telemetry contract** (`reference/telemetry.md`): standards-pinned OTLP from every execution
  context, the `autonomy.work_item.url` join attribute, one causal tree by context propagation,
  sink classes with a zero-cost file-artifact default — plus the setup telemetry slice, its
  snippet templates, and the emission-conformance check.
- **Return-accounting convention** (`reference/return-accounting.md`): the two human-attested
  return questions captured as a tracker-resident record at the task boundary of
  autonomous-class work, joinable to cost telemetry by the join attribute — plus the setup
  capture slice and its close-boundary templates. Agents prompt and aggregate; they never
  estimate the human fields.
- **Trigger-dispatch contract** (`reference/trigger-dispatch.md`): four signal-surface
  classes normalized by adapters into the governed work-item queue under six class-generic
  obligations, a schema-versioned signal envelope, security-surface work-class stamping, and
  one dispatch entrypoint (push kick + scheduled drain through the queue seam's race-safe
  lease) — plus the setup trigger/dispatch slice, its adapter and acknowledgment templates,
  and the signal-envelope conformance check.
- **Guardrail matrix** (`reference/guardrails.md`): five semantic work classes (`C1`–`C5`)
  crossed with five enforcement columns — isolation floor, verification layers, merge policy,
  cost tier, escalation — as one progressive-disclosure hub with on-demand leaves (isolation
  ladder, work classes, security review, admission policy), human-ratified promotion with
  automatic fail-closed demotion, and a two-surface binding split by governance sensitivity
  (security axes on the settings-as-code home outside agent blast radius; non-security remaps
  repo-local) — plus the contract-owned security-binding schema and its semantic check, and the
  setup guardrail slice that detects substrates per surface, live-validates isolation with an
  in-boundary probe before binding, folds in security-review wiring, and fail-closes autonomous
  dispatch where no `L2` substrate exists.
- **Standing-routine catalog** (`reference/routines.md`): the routine classes an adopting org can
  stand up as governed background maintenance — a progressive-disclosure hub whose glance-layer
  table classifies every class (judgment, output, access → derived guardrail row) under
  contract-owned catalog-to-matrix mapping rules, with `reference/routines/` definition leaves for
  the v1 subset and the invariant that a routine is a scheduled `temporal`-class trigger adapter
  behind the governed queue, never a private execution or merge path — plus the setup routine slice
  that discovers scheduling surfaces, wires the free CI-cron/local-scheduler defaults as reviewable
  changes, homes each routine's work-class mapping on the security surface, and
  detect-diff-reconciles existing org schedulers and bots instead of duplicating them.
- **Runner design pack** (`reference/runner.md`): the architect-ready design contract for the
  autonomous-drain runner — the composition spine and its eight seams, the lifecycle state
  model, the two-family stop-criteria taxonomy with terminal-handoff escalation and
  severity-routed notification fan-out, the matrix-derived launch backend set, and the topology
  ownership seam map, as a progressive-disclosure hub with `reference/runner/` leaves. Design
  only — the build stays gated on the charter's own triggers and the runner-execution home
  stays unborn; setup records nothing runner-specific beyond the escalation notification routes
  (severity axis + personal-push tier) bound through the security binding.
- **Guided setup** (`/autonomy:setup`): discovery-first interview of the adopting org's state —
  role homes, substrate availability, budget posture — writing a schema-versioned binding under
  `.claude/autonomy/` as reviewable changes. Never assumes any particular org or repo shape.

## Roadmap (deferred, trigger-gated)

Each capability below lands with its own work package; none ships before its contracts are
locked (no step-skipping — trust before scale).

| Capability | Trigger |
|---|---|
| Fleet adapter materializations (reusable workflows, labels, drain routine) | Work-item backlog, post trigger-package graduation. |
| Fleet guardrail materializations (binding instances, workflow gates, scanner wiring) | Work-item backlog, post guardrail-package graduation. |
| Fleet routine stand-up + existing-scheduler reconciliation | Work-item backlog, post routine-package graduation. |
| Vendor-binding capability templates (routine/workflow files) | Build stage, post-architect. |
| Cost enforcement (hard spend caps; cost tiers stay policy vocabulary until then) | 3→4 transition work begins. |
| Runner charter execution pack (design pack shipped) | The runner build trigger fires (charter's own conditions). |

## Trigger register (plugin-scoped)

| Trigger | Action |
|---|---|
| Role vocabulary changes in `reference/role-topology.md` | Update the org-policy home's binding instance doc to the new vocabulary version. |
| A second plugin consumes `.claude/autonomy/` config | Graduate the binding schema to a versioned concern contract per the marketplace's concern-named-folder convention. |
| A second repository consumes the security binding | Stand up a mechanical cross-repo binding drift check. |

## Lane-stop gate + operator notification (`Stop` hook)

`hooks/lane-stop-gate.sh` makes "a lane that stops itself before its goal is met is a bug" a
mechanism instead of a prompt admonition. On every stop attempt of an **opted-in** lane it does a
deterministic completion self-check; if completion is not explicitly signaled it blocks the first
stop with a re-injected self-check (keep going, or declare done), and if the lane stops anyway it
allows the stop and alerts the operator via `hooks/lane-notify.sh` (OS toast + terminal bell/OSC 9,
local machine only).

Completion is signaled either way (a shell hook cannot re-run the `/goal` evaluator model): the exact
sentinel token in the agent's final message, or a marker file. The marker is consumed (deleted) when
it authorizes a stop — one marker, one stop — so a file left in the checkout by a prior completed
run never authorizes the stops of a later lane run. It is the settings-scoped,
cross-session sibling of `/goal`'s session-only completion condition — use `/goal` for a single
session, this gate for a standing lane.

**Default OFF** — a Stop-blocking hook must never engage for an interactive session.

**Config is honored from trusted sources only (#1784).** The gate never takes its config off the
bare `CLAUDE_PLUGIN_OPTION_*` environment: for an unconfigured key, a watched repository's own
`.claude/settings.json` `env` block populates that variable freely, and a gate whose enablement (or
sentinel, or marker path) the watched repository controls is not a gate
(`docs/conventions/hook-config-delivery`). Per-key precedence, mirroring Claude Code's own settings
merge:

1. **Managed settings** (fixed root-owned paths + `managed-settings.d/` drop-ins) — an org can veto
   with `lane_stop_gate_enabled: false`.
   [Server-managed settings](https://code.claude.com/docs/en/server-managed-settings) are
   deliberately excluded — their only on-disk artifact is the user-writable cache
   `~/.claude/remote-settings.json`, which fails the root-owned trust test (the page itself calls
   the channel "a client-side control, not a security boundary") — so an org vetoing via the server
   channel must also deliver an endpoint `managed-settings.json` to veto lanes.
2. **The per-session arm record** — the `claude-ops` lane launcher arms a lane at launch: give the
   lane a `settings` object requesting the gate in its lanes-config entry (see that skill's
   `context/config.md`), and the launcher runs this plugin's `hooks/lane-stop-gate-arm.sh` (writing
   a record under the plugin's own install-derived data directory) and injects the random record id
   as `lane_stop_gate_arm_id` in the session's `--settings`. The id is a capability pointer, never
   authority: the gate validates it, honors only its own store, binds it to the first presenting
   session, and expires it after 7 days. The record is not consumed on a stop — a lane is one
   session across many `/loop` cycles, each of whose stops must stay gated — so it lives for the
   claiming session and is retired by TTL plus the launcher's relaunch sweep. To arm a hand-launched
   session, run the arm helper from the installed plugin the same way, then pass the id via
   `--settings '{"pluginConfigs":{"autonomy@<marketplace>":{"options":{"lane_stop_gate_arm_id":"<id>"}}}}'`.
3. **User `settings.json`**, located from the hook's own install path — a *persistent* enable that
   also gates interactive sessions, which defeats the default-OFF design; prefer the launcher.

A `--settings`-only `lane_stop_gate_enabled=true` (the pre-0.12.0 opt-in) is **no longer honored** —
that value reaches the hook only as the forgeable env mirror. The gate says so with a visible
once-per-session notice instead of disengaging silently, which is also how a stale (pre-arming)
lane launcher surfaces. A `--plugin-dir` checkout install has no trusted user-settings or record
location, so only managed settings can enable the gate there.

It is fail-open (unreadable stdin / missing `jq` / a `SubagentStop` never trips it) and bounded
against runaway by the `stop_hook_active` one-nudge guard plus Claude Code's consecutive-block cap.
It catches a graceful self-stop only — a closed laptop, a killed process, or `/loop` expiry emit no
`Stop` event.

When the consuming repo sets `HOOK_TELEMETRY_SINK`, the gate emits one fire-and-forget envelope per
evaluated outcome (`hook: "lane-stop-gate"`; payload contract in the marketplace's hook-telemetry
convention, `data/lane-stop-gate.schema.json`), so premature lane stops are measurable fleet-wide.
The payload is a fixed vocabulary — never the sentinel token, marker path, cwd, or branch.

| userConfig option | Default | Effect |
|---|---|---|
| `lane_stop_gate_enabled` | `false` | Opt this session's lane into the gate. |
| `lane_stop_gate_sentinel` | `LANE-STOP-OK` | Token the agent emits alone on its own line to declare the goal met. |
| `lane_stop_gate_marker` | *(unset)* | Marker file whose existence also authorizes a stop (absolute, or relative to the session cwd). Consumed on use. |
| `lane_stop_gate_arm_id` | *(unset)* | Launcher-written arm-record id (capability pointer, never authority). Not set by hand. |
| `lane_notify_enabled` | `true` | Master switch for the operator alert. |
| `lane_notify_os_toast_enabled` | `true` | OS-native toast channel (macOS/Linux). |
| `lane_notify_terminal_enabled` | `true` | Terminal bell + OSC 9 channel. |

## Configuration

Setup writes tracked config to `.claude/autonomy/` in the consuming repo (concern-named — the
config outlives any plugin restructure). Personal overlays follow the marketplace overlay
convention: `.claude/autonomy/**/*.local.*` stays gitignored; layers resolve per the
binding-seam ladder — user-global → org binding (when pointed) → project → local overlay —
additively.
