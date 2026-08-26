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
  sink classes with a zero-cost file-artifact default, plus the setup telemetry slice, its
  snippet templates, and the emission-conformance check.
- **Return-accounting convention** (`reference/return-accounting.md`): the two human-attested
  return questions captured as a tracker-resident record at the task boundary of
  autonomous-class work, joinable to cost telemetry by the join attribute, plus the setup
  capture slice and its close-boundary templates. Agents prompt and aggregate; they never
  estimate the human fields.
- **Trigger-dispatch contract** (`reference/trigger-dispatch.md`): four signal-surface
  classes normalized by adapters into the governed work-item queue under six class-generic
  obligations, a schema-versioned signal envelope, security-surface work-class stamping, and
  one dispatch entrypoint (push kick + scheduled drain through the queue seam's race-safe
  lease), plus the setup trigger/dispatch slice, its adapter and acknowledgment templates,
  and the signal-envelope conformance check.
- **Guardrail matrix** (`reference/guardrails.md`): five semantic work classes (`C1`–`C5`)
  crossed with six enforcement columns: isolation floor, verification layers, verification
  topology, merge policy, cost tier, escalation, as one progressive-disclosure hub with
  on-demand leaves (isolation ladder, work classes, security review, verification topology,
  admission policy), human-ratified promotion with automatic fail-closed demotion, and a
  two-surface binding split by governance sensitivity
  (security axes on the settings-as-code home outside agent blast radius; non-security remaps
  repo-local), plus the contract-owned security-binding schema and its semantic check, and the
  setup guardrail slice that detects substrates per surface, live-validates isolation with an
  in-boundary probe before binding, folds in security-review wiring, and fail-closes autonomous
  dispatch where no `L2` substrate exists.
- **Standing-routine catalog** (`reference/routines.md`): the routine classes an adopting org can
  stand up as governed background maintenance, a progressive-disclosure hub whose glance-layer
  table classifies every class (judgment, output, access → derived guardrail row) under
  contract-owned catalog-to-matrix mapping rules, with `reference/routines/` definition leaves for
  the v1 subset and the invariant that a routine is a scheduled `temporal`-class trigger adapter
  behind the governed queue, never a private execution or merge path, plus the setup routine slice
  that discovers scheduling surfaces, wires the free CI-cron/local-scheduler defaults as reviewable
  changes, homes each routine's work-class mapping on the security surface, and
  detect-diff-reconciles existing org schedulers and bots instead of duplicating them.
- **Routine prerequisite resolution** (`reference/prerequisite-resolution.md`): fail-closed,
  per-identity-per-surface verdicts (`supported` / `conditional` / `unsupported` / `unknown`) for
  which catalog identities can run against a repository, composing owning seams rather than a new
  prober, with `deferred(<trigger>)` (the row's own join trigger) marking `join:` rows that
  have no identities yet. Per-identity
  facts live in each `v1` leaf; `generated/identity-prerequisites.json` is the drift-gated
  emission derived from those leaves (generator under `skills/setup/scripts/`);
  `skills/setup/scripts/resolve-prerequisites.mjs` is the deterministic per-surface resolver;
  the setup skill's prerequisite-resolution slice (`check` / `apply`) consumes it.
- **Runner design pack** (`reference/runner.md`): the architect-ready design contract for the
  autonomous-drain runner, the composition spine and its eight seams, the lifecycle state
  model, the two-family stop-criteria taxonomy with terminal-handoff escalation and
  severity-routed notification fan-out, the matrix-derived launch backend set, and the topology
  ownership seam map, as a progressive-disclosure hub with `reference/runner/` leaves. Design
  only, the build stays gated on the charter's own triggers and the runner-execution home
  stays unborn; setup records nothing runner-specific beyond the escalation notification routes
  (severity axis + personal-push tier) bound through the security binding.
- **Autonomous-pipeline reminder** (`reference/autonomous-pipeline-reminder.md`): a drop-in
  standing reminder for an adopting org's *own* pipeline, against the two stopping failures a
  pipeline cannot recover from, a turn ending on unexecuted intent, and a turn stopping to ask
  permission nobody is there to give. States where it does not apply (an attended lane wants the
  opposite posture) and what the `lane-stop-gate` hook does and does not cover of it. One clause
  deterministically, the rest by instruction alone.

  **Provenance.** The clause set is this repository's own wording of guidance in Anthropic's Claude
  Fable 5 prompting guide, section "Rare cases of early stopping", folded together with the
  companion checkpoint instruction that section asks to be paired with it
  (<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>,
  fetched 2026-08-08). It is authored locally rather than reproduced, per this repository's rule
  against hand-copying upstream content. The citation lives here rather than in the contract file
  because `reference/` docs are written in surface classes and may not name vendors.
  **Recheck trigger:** that section changing its clause set, or a second model guide stating the same
  guidance in materially different terms.
- **Guided setup** (`/autonomy:setup`): discovery-first interview of the adopting org's state,
  covering role homes, substrate availability, and budget posture, that writes a schema-versioned
  binding under
  `.claude/autonomy/` as reviewable changes. Never assumes any particular org or repo shape.

## Roadmap (deferred, trigger-gated)

Each capability below lands with its own work package. None ships before its contracts are locked:
no step-skipping, and trust before scale.

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
it authorizes a stop, one marker, one stop, so a file left in the checkout by a prior completed
run never authorizes the stops of a later lane run. It is the settings-scoped,
cross-session sibling of `/goal`'s session-only completion condition. Use `/goal` for a single
session, this gate for a standing lane.

**Default OFF**, a Stop-blocking hook must never engage for an interactive session.

**Config is honored from trusted sources only (#1784).** The gate never takes its config off the
bare `CLAUDE_PLUGIN_OPTION_*` environment: for an unconfigured key, a watched repository's own
`.claude/settings.json` `env` block populates that variable freely, and a gate whose enablement (or
sentinel, or marker path) the watched repository controls is not a gate
(`docs/conventions/hook-config-delivery`). Per-key precedence, mirroring Claude Code's own settings
merge:

1. **Managed settings** (fixed root-owned paths + `managed-settings.d/` drop-ins), an org can veto
   with `lane_stop_gate_enabled: false`.
   [Server-managed settings](https://code.claude.com/docs/en/server-managed-settings) are
   deliberately excluded. Their only on-disk artifact is the user-writable cache
   `~/.claude/remote-settings.json`, which fails the root-owned trust test (the page itself calls
   the channel "a client-side control, not a security boundary"), so an org vetoing via the server
   channel must also deliver an endpoint `managed-settings.json` to veto lanes (the gate reads that
   file directly; Claude Code itself ignores endpoint sources when server keys arrive).
2. **The per-session arm record**, the `claude-ops` lane launcher arms a lane at launch: give the
   lane a `settings` object requesting the gate in its lanes-config entry (see that skill's
   `context/config.md`), and the launcher runs this plugin's `hooks/lane-stop-gate-arm.sh` (writing
   a record under the plugin's own install-derived data directory) and injects the random record id
   as `lane_stop_gate_arm_id` in the session's `--settings`. The id is a capability pointer, never
   authority: the gate validates it, honors only its own store, binds it to the first presenting
   session, and expires it after 7 days. The record is not consumed on a stop, a lane is one
   session across many `/loop` cycles, each of whose stops must stay gated, so it lives for the
   claiming session and is retired by TTL plus the launcher's relaunch sweep. To arm a hand-launched
   session, run the arm helper from the installed plugin the same way, then pass the id via
   `--settings '{"pluginConfigs":{"autonomy@<marketplace>":{"options":{"lane_stop_gate_arm_id":"<id>"}}}}'`.
3. **User `settings.json`**, located from the hook's own install path, a *persistent* enable that
   also gates interactive sessions, which defeats the default-OFF design; prefer the launcher.

A `--settings`-only `lane_stop_gate_enabled=true` is **not honored**; arm a lane through the
launcher instead. That value reaches the hook only as the forgeable env mirror. The gate says so with a visible
once-per-session notice instead of disengaging silently, which is also how a stale (pre-arming)
lane launcher surfaces. A `--plugin-dir` checkout install has no trusted user-settings or record
location, so only managed settings can enable the gate there.

It is fail-open (unreadable stdin / missing `jq` / a `SubagentStop` never trips it) and bounded
against runaway by the `stop_hook_active` one-nudge guard plus Claude Code's consecutive-block cap.
It catches a graceful self-stop only: a closed laptop, a killed process, or `/loop` expiry emit no
`Stop` event.

When the consuming repo sets `HOOK_TELEMETRY_SINK`, the gate emits one fire-and-forget envelope per
evaluated outcome (`hook: "lane-stop-gate"`; payload contract in the marketplace's hook-telemetry
convention, `data/lane-stop-gate.schema.json`), so premature lane stops are measurable fleet-wide.
The payload is a fixed vocabulary, never the sentinel token, marker path, cwd, or branch.

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

Setup writes tracked config to `.claude/autonomy/` in the consuming repo, named for the concern so
the config outlives any plugin restructure. Personal overlays follow the marketplace overlay
convention: `.claude/autonomy/**/*.local.*` stays gitignored; layers resolve per the
binding-seam ladder: user-global → org binding (when pointed) → project → local overlay, additively.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `lane_stop_gate_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ENABLED` | Opt an autonomous lane into the deterministic Stop-hook completion gate. Default OFF — a Stop-blocking hook must never engage for an interactive session. Honored from user or managed settings only (the gate reads those files itself); per-session lanes are armed by the claude-ops lane launcher instead. The env mirror is never authority (#1784). |
| `lane_stop_gate_sentinel` | string | `"LANE-STOP-OK"` | `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_SENTINEL` | The exact token the agent emits in its final message to declare the lane's goal met and authorize a stop. Matched only when alone on its own line. Honored from user/managed settings or the launcher's arm record, never the bare environment. |
| `lane_stop_gate_marker` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_MARKER` | Optional path to a completion-marker file whose existence also authorizes a stop (absolute, or relative to the session cwd). Empty disables the file signal. Honored from user/managed settings or the launcher's arm record, never the bare environment. |
| `lane_stop_gate_arm_id` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_ARM_ID` | Written by the lane launcher at launch: names this session's arm record in the plugin's own data directory (hooks/lane-stop-gate-arm.sh). A capability pointer, never authority by itself — the gate validates it, honors only a record in its install-derived store, and binds it to the first presenting session. Not set by hand. |
| `lane_notify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_ENABLED` | Master switch for the operator alert fired when a lane stops without signaling completion. |
| `lane_notify_os_toast_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_OS_TOAST_ENABLED` | OS-native desktop toast (macOS/Linux) for the lane-stop alert. |
| `lane_notify_terminal_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_LANE_NOTIFY_TERMINAL_ENABLED` | Audible bell + OSC 9 notification written to the controlling terminal for the lane-stop alert. |
| `verification_lens_pool` | string | `"specification,adversarial,contract,regression,evidence"` | `CLAUDE_PLUGIN_OPTION_VERIFICATION_LENS_POOL` | Ordered, comma-separated pool of verification lenses the model-adjudicated checker slots draw from — one distinct lens per slot, in pool order. Tokens come from the closed vocabulary in the verification-topology contract leaf; an unrecognized token is recorded as unresolved and draws no lens, and a pool shorter than a class's model-adjudicated slot count leaves the remaining slots unlensed rather than repeating a lens. The pool contributes to no count: how many checkers a class runs, how they must differ, and whether one must be cross-vendor are floors on the org's security binding, outside this setting's reach. |
| `visual_narration_enabled` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_VISUAL_NARRATION_ENABLED` | Run the advisory visual narration lane: strictly downstream of deterministic detection, it writes a plain-language account of a difference the deterministic layer already found and attaches it to the run record for the human gate. Advisory only — it emits no verdict, fills no checker slot, is counted by no floor, and never gates a transition; no cell anywhere names it as authority. Default OFF: it is inert without an upstream deterministic comparator, and each narrated artifact is a metered vision-model call. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure autonomy@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install autonomy@<marketplace> -s <scope> --config lane_stop_gate_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "autonomy@<marketplace>": {
         "options": {
           "lane_stop_gate_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->
