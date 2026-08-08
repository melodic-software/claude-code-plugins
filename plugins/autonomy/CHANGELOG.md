# Changelog

All notable changes to the `autonomy` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

Versions 0.1.0–0.7.0 predate this file (introduced with 0.7.1); their history lives in the
merged work-package PRs (#333, #343, #356, #372, #377, #600, #676).

## [0.12.3]

### Changed

- **Shared `hook-utils.sh`: a hook invocation spawns three fewer external processes (#1978).**
  Every hook that buffers its stdin paid an `awk` (one float division, to slice the read timeout), a
  `printf | tr -d '\r'` pipeline (a fork and an exec to delete one byte class from a string bash
  rewrites in place), and a `jq -e .` validity probe over a buffer the read loop had already parsed
  with jq. On Windows Git Bash, where process creation is `fork()` emulation, each spawn costs
  ~140 ms. Behavior is unchanged: the slice keeps the three-decimal form `read -t` is given, the
  buffer is CR-stripped as before, and the completeness verdict is reused only when jq itself
  produced it — so a host without jq still fails open exactly as it did. Also adds
  `hook::jq_fields`, which extracts several fields from one payload in a single jq process for
  hooks that read two or three of them. Synced from `lib/hook-utils.sh`.

## [0.12.2]

### Fixed

- **`reference/routines.md`: the `goal` glossary row no longer claims a budget cap ends the
  session.** The row read "until a separate grader judges the condition met or a budget cap trips";
  the official page documents a closed two-item set — "A goal keeps running until the condition is
  met or you run `/goal clear`" — and its own section on bounding a goal's duration offers a turn or
  time clause inside the condition, not a spend cap. The only dollar cap Claude Code's CLI documents
  is the `--max-budget-usd` flag, which is print-mode-only and invocation-scoped, whereas this row
  is `session-scoped`; a cap-stopped invocation also leaves the goal neither achieved nor cleared,
  so it is restored on `--resume`/`--continue` — the cap ends the process while the goal outlives
  it. The replacement clause names the second of the two events that actually change goal state.

## [0.12.1]

### Changed

- **`lane-stop-gate-lib.sh`: the server-managed settings channel's exclusion from the org-veto
  source list is documented as deliberate.** The gate reads only endpoint managed-settings paths
  plus `managed-settings.d/` drop-ins; [server-managed
  settings](https://code.claude.com/docs/en/server-managed-settings) surface on disk only as the
  user-writable cache `~/.claude/remote-settings.json`, which fails the root-owned trust test the
  veto relies on — the page itself calls the channel "a client-side control, not a security
  boundary". Comment at the exclusion site plus a README precedence-list note directing orgs on the
  server channel to also deliver an endpoint `managed-settings.json`; no behavior change.

## [0.12.0]

### Changed

- **`lane-stop-gate.sh`: gate config is honored from trusted sources only — the bare
  `CLAUDE_PLUGIN_OPTION_LANE_STOP_GATE_*` environment is never authority (#1784).** The enable
  flag (and the sentinel and marker path with it) was read straight off the environment — channel B
  of `docs/conventions/hook-config-delivery`, whose rule 3 requires channel F for a safety-critical
  optional-with-default toggle: for an unconfigured key, a watched repository's own
  `.claude/settings.json` `env` block populates the variable freely (fact 4), so the watched repo
  could decide whether the gate runs, weaken the sentinel to an incidentally-occurring line, or
  point the marker at a file of its choosing. Per-key resolution is now managed settings (fixed
  root-owned paths plus `managed-settings.d/` drop-ins) ▷ the per-session arm record (below) ▷ the
  user `settings.json` located only from the hook's own `plugins/cache` install anchor ▷ the
  in-script defaults. No file path any of these reads is env-derived — and the managed-settings
  platform is read from `uname -s`, not the repo-settable `$OSTYPE`, with the resolved primary
  asserted absolute so it can never become a cwd-relative (repo-plantable) path. An unreadable or
  malformed trusted source contributes no verdict and the default (off) applies — the gate keeps its
  fail-open, never-wedge posture. When the env channel *claims* enablement that no trusted source
  corroborates — a stale launcher still delivering over `--settings`/env, or a repo attempting the
  old attack — the gate emits a visible once-per-session notice instead of disengaging silently.
  **Behavior change:** a `--settings`-only `lane_stop_gate_enabled=true` no longer engages the gate;
  lanes are armed by the claude-ops lane launcher (0.26.0+) instead, and a `--plugin-dir` checkout
  install (no install anchor, hence no trusted user-settings or record location) can be enabled only
  via managed settings.

### Added

- **`hooks/lane-stop-gate-arm.sh` — operator-side per-session arming, and the
  `lane_stop_gate_arm_id` userConfig key that points at it (#1784).** A hook cannot observe
  `--settings` (the channel-F residual), so the per-session opt-in the launcher shipped over
  `--settings` needed a trusted replacement, not deletion. The launcher now generates a random arm
  id, runs this helper — which writes a record (sentinel/marker config, armed-at stamp) under the
  plugin's **own install-derived** data directory, refusing when unanchored or when managed settings
  veto with `lane_stop_gate_enabled: false` — and passes the id to the session through the new
  string option. The env-delivered id is a capability pointer, never authority: the gate
  shape-validates it (`^[A-Za-z0-9_-]{8,64}$` before any path use), looks it up only in the
  install-anchored store (the `CLAUDE_PLUGIN_DATA` fallback is used for the marker-consumption
  ledger only, never for records or enablement), and claims it for the first presenting session so a
  replayed id is refused, expires it after 7 days. The record is **not** consumed on a stop: a lane
  is one session across many `/loop` cycles, each ending in a Stop the gate must still guard, so the
  record lives for the claiming session (bound to it by the claim) and is retired by its TTL plus the
  launcher's relaunch sweep. A repo env block can neither mint a valid id nor clobber a configured
  one (harness injection wins for configured keys). Shared derivation helpers live in
  `hooks/lane-stop-gate-lib.sh`, sourced by both scripts.

### Fixed

- **Managed settings reach a `--plugin-dir` install (#1784).** Keying every settings read on the
  marketplace-qualified id meant the managed scope contributed no verdict without a
  `plugins/cache` anchor — silently disabling the org-mandate path on the one install class for
  which it is the *only* enable path, and on whose availability the arm helper's refusal to arm
  there is premised. An unanchored install now matches on the plugin name from the manifest beside
  the hook (the same `BASH_SOURCE`-derived trust anchor everything else uses), accepting a bare or
  any marketplace-qualified key; anchored installs keep their exact-id match, so another
  marketplace's entry still cannot mask this install's.
- **An empty configured sentinel falls back to `LANE-STOP-OK`.** Emptiness is not a documented way
  to disable the token channel, and honoring it silenced that channel while the block reason still
  instructed the agent to emit an empty token on its own line.

## [0.11.8]

### Fixed

- **`lane-stop-gate.sh`: a completion marker whose deletion fails no longer authorizes a later,
  unrelated lane run (#1784).** The marker's one-shot authorization was latched solely by deleting
  the file, and the marker lives in the watched checkout — a directory the hook is not guaranteed to
  be able to write. An `rm` the OS refused left a file that still satisfied `[[ -f "$MARKER" ]]` on
  the next run, which is exactly the cross-run bypass consuming the marker exists to close; the
  surrounding comment asserted "the next run must not rely on that stale file" while nothing enforced
  it. Consumption is now recorded in this plugin's own persistent data directory — path plus the
  consumed file's identity (mtime and size) — and the deletion is the tidy-up rather than the latch. A
  marker recorded as consumed is not a signal however long it survives on disk. Recreation recovery
  is BEST-EFFORT, not guaranteed: a marker recreated with a different mtime or size reads as a new
  file and authorizes normally, but one recreated at the same size within the same whole second — an
  empty `touch`-style marker being the realistic case — is indistinguishable under a one-second
  `stat`. It then stays latched for as long as it goes unwritten: an mtime does not advance on its
  own, so what clears the record is the marker's NEXT write landing in a different second, not the
  clock passing one. The cost is that single completion signal; the one after it authorizes. That is
  the deliberate direction for a gate: a stop delayed, never a second unearned one. A host where
  neither `stat` form reports an identity holds the record for the same reason. The
  data directory is derived from the hook's own install path (the `plugins/cache` anchor Claude Code
  documents), falling back to `CLAUDE_PLUGIN_DATA` only for a `--plugin-dir` install that carries no
  such anchor: the script's own location is not something a watched repository can redirect. When no
  data directory can be written the deletion remains the only latch, i.e. the behavior that predates
  this ledger.

## [0.11.7]

### Fixed

- **Shared `hook-utils.sh`: the OS temp tree is no longer treated as project content (#1769).**
  `hook::read_file_path` scoped a file to the project by prefix-matching `CLAUDE_PROJECT_DIR`, so a
  session whose project directory is the user's home admitted everything under the OS temp root —
  including Claude Code's own per-session scratchpad, which lives there. Hooks that lint, rewrite, or
  autocorrect then ran on throwaway files that are not project content and carry no project config to
  opt out with; the reported case was `typos-format` autocorrecting a shell variable in a scratch
  script and silently breaking it. The guard now rejects a file inside the OS temp tree when the
  project root is outside it. The exemption is deliberate and load-bearing: when the project root
  itself lives under temp — a `mktemp -d` fixture checkout, which is how this repository's own hook
  suites run — its files are still accepted. Temp roots come from `TMPDIR` / `TMP` / `TEMP` plus the
  POSIX defaults, canonicalized through the same pipeline the membership comparison already uses.
  Synced from `lib/hook-utils.sh`.

## [0.11.6]

### Fixed

- **Shared `hook-utils.sh`: a wrapper's working-directory change is no longer lost when a caller
  parses only git's own global options (#1503).** `hook::git_resolve_index` walks wrapper programs
  (`env`, `sudo`, …) to reach the real `git` token, and a caller that scopes its git-global parsing
  to the slice starting at that token cannot see a relocation the wrapper already performed — GNU env
  documents `-C, --chdir=DIR` as "change working directory to DIR". The resolver now reports those
  directories in a new `HOOK_GIT_RESOLVED_WRAPPER_DIRS` result global, in execution order, so a
  caller composes them ahead of git's own globals instead of dropping them. Five spellings are read
  (`-C DIR`, `-CDIR`, `--chdir DIR`, `--chdir=DIR`, and a clustered `-vC DIR`), a repeat within one
  `env` is last-wins as env itself resolves it, and sudo's `-D`/`--chdir` is read in its unclustered
  spellings. A chdir spelled inside `-S`/`--split-string` is NOT read; that path already fails open
  for any command on `main` and is tracked in #1814. This plugin does not consume the new global; the sync keeps its copy
  byte-identical with the source. Synced from `lib/hook-utils.sh`.

## [0.11.5]

### Fixed

- **`lane-notify.sh` no longer claims no remote/Slack/push transport exists (#1650).** The header
  stated "there is no remote/Slack/push transport here (none exists as a marketplace primitive
  yet)" — stale on both clauses, since first-party off-machine transports do exist today. The
  comment now says so and points at the loop-lane convention's out-of-band notification seam (§2),
  which owns that seam and its verified grounding, instead of restating the mechanisms and their
  citations here. The primitive's own local-only reach and its closed-laptop/dead-process caveat
  are unchanged. Comment-only — no hook behavior change.

### Changed

- **`reference/runner/escalation.md`: severity fan-out legs grounded in shipped transport surface
  classes (#1650).** The channel-notification and personal-push legs were unbuilt design with no
  named surface class. A new "Fan-out transport grounding" subsection assigns the channel leg to
  the deterministic hook-transport class and the personal-push leg to the model-discretionary
  push-notification surface class, records each class's dependency profile, and states that both
  classes have shipped mechanisms today — so neither leg waits on a primitive that has to be
  invented. Per this plugin's contract boundary the subsection names no vendor and no instance:
  concrete adapters are bound and re-verified at build, and the consuming-side wiring lives in the
  loop-lane convention's seam.

## [0.11.4]

### Fixed

- **Shared `hook-utils.sh`: an in-project file spelled as a Windows 8.3 short name is no longer
  silently skipped by the shared membership guard (#1636).** `hook::physical_path` canonicalized
  with GNU realpath, which under Git Bash resolves symlinks but leaves 8.3 short names
  (`KYLESE~1`) unexpanded, so a short-form `file_path` failed the `CLAUDE_PROJECT_DIR` prefix
  comparison in `hook::read_file_path`. The lib now expands short names on Windows/MSYS hosts
  (new `hook::expand_8dot3`, via `cygpath -l`) before the comparison, and only when the expanded
  form actually differs; a genuinely out-of-project file is still skipped. 8.3 generation is a
  per-volume property (`fsutil 8dot3name query`), so the defect was live only for checkouts on a
  volume that generates short names. Synced from `lib/hook-utils.sh`; this plugin's own hooks do
  not consume the membership guard, so their behavior is unchanged.

## [0.11.3]

### Fixed

- **Shared `hook-utils.sh`: a large tool payload no longer makes this plugin's hooks silently
  skip (#1563).** `hook::buffer_stdin` read the hook payload with `read -d ''`, which consumes a
  pipe one byte at a time (~32 KB/s on Git Bash), so the `stdin_read_timeout` bound was really a
  ~64 KB throughput ceiling rather than the stall detector it was written to be. Past that ceiling
  the read returned a truncated payload and rc 1, and this plugin's hooks took their `|| exit 0`
  branch — the hook did not run at all, with no diagnostic, on exactly the large writes it was
  most wanted for. The read is now chunked (`read -N`), which bash satisfies with block reads, and
  the bound became a true idle bound: `read -t` is a deadline for the whole requested read rather
  than an inactivity timer, so a timed-out read that nevertheless returned bytes is now treated as
  progress — its partial chunk is kept and a fresh window is armed. Only a window that delivers
  nothing at all is a stall. `read -N` is Bash 4.1+, and these hooks support Bash 3.2+ (macOS
  system bash), so the pre-4.1 path falls back to the delimiter read inside the same re-arming
  loop. Measured: 50 KB drops from ~2100 ms to ~20 ms, 200 KB from ~6800 ms to ~85 ms. Synced
  from `lib/hook-utils.sh`; this plugin's own hook behavior is otherwise unchanged.

## [0.11.2]

### Changed

- **Test scaffolding: migrated `mktemp -p` temp file/dir creation to the portable `mktemp "$DIR/template"` form.** BSD/macOS `mktemp` has no `-p` flag; the directory now rides in the positional TEMPLATE argument instead, which both GNU and BSD `mktemp` accept identically. Test-only — no hook behavior change. Part of #1527 (`lane-stop-gate.test.sh`).

## [0.11.1]

### Fixed

- **Shared `hook-utils.sh`: a bare or trailing unquoted `NAME=value` Bash
  command no longer leaks the assignment value into the privacy-safe
  telemetry/audit subject.** `hook::extract_bash_subject` stripped a leading
  `VAR=value` prefix only when a following command word consumed it, so a
  command whose LAST token was an unquoted assignment (e.g. `TOKEN=ghp_…`)
  survived to the subject and emitted `Bash:TOKEN=ghp_…` into
  `hook-events.jsonl` and any wired `HOOK_TELEMETRY_SINK`. A resolved token
  still shaped like a shell assignment now bails to the bare `Bash` subject,
  matching the existing quoted-value bail (`VAR=x cmd` still reduces to
  `Bash:cmd`). Synced from `lib/hook-utils.sh`; the subject is
  telemetry/audit-only, so no hook block/allow behavior changes.

## [0.11.0]

### Added

- **Deterministic lane-stop gate (`Stop` hook) — the plugin's first hook** (#535 member 3). "A lane
  that stops itself before its goal is met is a bug" was previously only a prompt admonition. The new
  `hooks/lane-stop-gate.sh` fires on every stop attempt of an opted-in lane and structurally
  intercepts it: unless completion is EXPLICITLY signaled, the first stop is blocked with a
  re-injected completion self-check (`decision:"block"` + reason), converting a silent premature stop
  into "keep going or declare done." It directly counters the fabricated-context-percentage
  premature-stop failure (#576/#577) — the reason states that a self-estimated "~50% context", a turn
  count, or a vague sense of "enough" is not a completion condition. Completion is signaled
  deterministically (a shell hook cannot re-run the `/goal` evaluator model): either the exact
  sentinel token (default `LANE-STOP-OK`, matched only when alone on its own line) in the agent's final message, or
  the existence of a configured marker file — the settings-scoped, cross-session sibling of `/goal`'s
  session-only condition (#481). The marker is consumed (deleted) when it authorizes a stop — one
  marker, one stop — so a file left in the checkout by a prior completed run never authorizes the
  stops of a later lane run. The shipped standing-lane launch flow wires the opt-in per lane: the
  `claude-ops` lane launcher's new per-lane `settings` passthrough (its changelog) carries the
  documented `--settings` override, so lanes get the gate from tracked lane config rather than
  persistent global configuration. **Default OFF**: a Stop-blocking hook must never engage for an
  interactive session, so it is inert unless a lane opts in via `lane_stop_gate_enabled=true`. It is
  **fail-open** on unreadable stdin, missing `jq`, or a non-`Stop` event (a `SubagentStop` never trips
  it), and bounded against runaway: the `stop_hook_active` guard makes the gate block a stop at most
  once before allowing it, with Claude Code's own consecutive-block cap as the ultimate backstop.
  Scope: it catches a graceful **self-stop** only — a closed laptop,
  a killed process, or `/loop` expiry emit no `Stop` event and are out of this member's scope.
- **Operator notification on a genuine lane stop** (#535 member 4, evidence #582). When a lane still
  stops after the one structural nudge, the gate treats it as a down/stuck lane, allows the stop (never
  wedges it), and alerts the operator via the new self-contained `hooks/lane-notify.sh` — an OS-native
  toast (macOS/Linux) plus a best-effort terminal bell + OSC 9. Reach is **local-machine only**: there
  is no remote/Slack/push transport (none exists as a marketplace primitive yet), so it does not cover
  an away operator. It reimplements rather than sources the `desktop-notification` plugin because a
  `Stop` hook's stdout is parsed for `decision`/`reason` and cannot use the `terminalSequence` field
  that plugin's `Notification` hook relies on — a genuinely different emission path (direct `/dev/tty`)
  — and because cache-isolated plugins cannot source each other at runtime. No separate
  repeated-failure counter was built: a lane that keeps stopping simply re-fires this notification each
  time (and API-error telemetry is already owned by `claude-ops`'s `StopFailure` hook).
- **Six `userConfig` options** gating the above: `lane_stop_gate_enabled` (default false),
  `lane_stop_gate_sentinel`, `lane_stop_gate_marker`, `lane_notify_enabled`,
  `lane_notify_os_toast_enabled`, `lane_notify_terminal_enabled`. The plugin now carries the shared
  `hooks/hook-utils.sh` copy (Win32-safe stdin buffering, prerequisite-visibility helpers).
- **Lane-stop telemetry** (hook-telemetry convention). The gate emits one fire-and-forget envelope
  per **evaluated** outcome when the consumer sets `HOOK_TELEMETRY_SINK` — `blocked`/`nudged` for the
  one structural nudge, `ok`/`completion-signaled` (with the signaling channel, `sentinel` or
  `marker`) for a legitimate stop, and `ok`/`stopped-after-nudge` for the down-lane path that fires
  the operator notification — so premature lane stops are measurable and the local alert is
  correlatable in the fleet's hook observability pipeline. Default-off and fail-open exits stay
  silent. The `data` payload is a closed fixed vocabulary (published at
  `docs/conventions/hook-telemetry/data/lane-stop-gate.schema.json`) and never carries the sentinel
  token value, marker path, cwd, or branch.

## [0.10.0]

Tier ratified as **minor**, which under this plugin's `0.x` scheme is the breaking/vocabulary slot —
not the lesser of the two readings. The determinism rule below is contract vocabulary an adopting
org classifies novel routine classes against, and both its wording and its named rule token change,
so it takes that slot. The narrower reading — a **patch** (`0.9.1`), on the grounds that the
classification's substance is unchanged and every derived guardrail row is byte-identical — was
considered and not taken.

### Changed

- **`routines.md`: the determinism rule now fixes a property, not a mechanism.** "Deterministic
  checks are never routines … run as plain cron" prescribed a substrate in a contract whose own
  §Hosting stance holds that hosting is a deployment-owned binding. The invariant is **no agent
  session, zero agent tokens**; the substrate carrying it binds per deployment like every other
  hosting choice. The categorical "never" also concealed the hybrid `DET`-detect / `AGT`-judgment
  split defined two paragraphs below — a split the catalog uses on nearly as many rows as it flags
  `not-a-routine` — so the rule now states that determinism is a per-PORTION verdict and rarely a
  reason to stop classifying. The mapping rules, the catalog status legend, every `routines/` leaf
  that echoed the mechanism, and the setup skill's reconciliation rule and its evals move with it.
  **Bump ambiguity:** the substance of the classification is unchanged and every derived guardrail
  row is identical, which reads as a clarification and a **minor**; but the rule is contract
  vocabulary an adopting org classifies novel routine classes against, and both its wording and its
  named rule token change, which reads as a vocabulary change and a **major**.
- **The one-entrypoint invariant has one canonical statement.** It was restated six ways across
  five documents, and the restatements had already drifted apart — each named a different subset of
  the paths it forbids a second of. `trigger-dispatch.md` §Dispatch now states it canonically, and
  the adapter obligation, the constraints list, `routines.md` §Hosting stance, `guardrails.md`
  §Escalation, `runner.md`, and `runner/seams.md` cite it. The **escalation** channel stays a
  separate, narrower invariant owned by `guardrails.md`, and the runner's single hand-back path
  stays a separate runner-new one — collapsing either into the dispatch invariant would have been a
  regression wearing deduplication's clothes.

### Added

- **The one-entrypoint invariant's scope boundary is written.** The invariant had no stated scope,
  so whether a surface that touches a repository without claiming a queued item fell under it was
  unanswerable from the contract. It now governs the governed-queue path — claiming a queued item,
  or dispatching autonomous execution against one — and the boundary keys on what a surface DOES,
  never on what it is called. The `source-control` babysit lane is outside it today because it
  claims no work items, which its own skill body states; the boundary becomes load-bearing the
  moment a second claiming surface exists, which is why it lands before the runner is built rather
  than after two surfaces disagree.

## [0.9.0]

### Changed

- **Credential-probe validation is now deny-by-default against a configured `--credential-roots`
  allowlist.** The security-binding checker no longer recognizes a probed host-credential path by
  static structural shape. A static checker cannot know an org's real credential locations, and for
  any open-ended structural recognizer an adversary can craft a plausible-but-invented path (an
  invented home user, a mount that need not exist) whose failing read proves nothing while real host
  credentials stay readable. A filesystem credential entry now counts as credential-absence evidence
  only when its recorded host-side expansion resolves — lexically, `..`-safe, filesystem-independent —
  under one of the operator-configured trusted roots passed via the new `--credential-roots
  <path,path,...>` flag, mirroring the `--egress-hosts` seam; with no roots configured, every
  filesystem credential entry is untrusted and the level fails closed. Membership under a configured
  root is the sole test, so the previously non-converging location enumeration is dissolved. A
  cloud-metadata-endpoint route and a well-known credential env token remain bounded closed sets that
  need no allowlist, and the expansion-coherence guard is retained. The egress-side seam is unchanged.

## [0.8.0]

### Added

- **Instruction-provenance clause added to the routines contract.** A new normative clause in
  `reference/routines.md` fixes that a routine's instruction content lives in a
  version-controlled, reviewable artifact and the stored prompt is a thin pointer to it;
  pasted-prose prompts are non-compliant, retaining no history and drifting invisibly against
  the repository state each run executes on. The clause is surface-agnostic — its rationale is
  that a scheduling surface holding the prompt centrally exposes no prompt history, diff, or
  rollback, so behavior change is auditable only where the pointed-to artifact is versioned.
  Surface-class mappings (a cloud scheduling surface → a skill committed to a selected
  repository's skills directory; a desktop scheduling surface → a per-task instruction
  file under the deployment's version-controlled dotfiles) appear only as illustrative
  deployment-owned bindings, consistent with the contract's Hosting stance.

## [0.7.4]

### Changed

- **Boris-intent attribution seams marked across the guardrail contract.** Three surgical
  attributions distinguish this contract's own instantiation from the source playbook's posture,
  closing UNMARKED-EXTENSION seams a Boris-intent audit found (zero violations, three seams). The
  guardrail hub now states that the step-4 sentence it quotes verbatim is the playbook's while the
  five-class taxonomy, blocking knobs, and promotion predicates are this contract's mechanism; the
  security-review leaf marks review-as-merge-gate (the `blocking` knob) as this contract's own
  layer over the playbook's advisory-review-feeding-a-human-merge posture; and the work-classes
  leaf attributes the numeric-predicate promotion/demotion apparatus as this contract's
  quantification of the playbook's qualitative "earned widespread trust" bar. Documentation only —
  no contract semantics change.

## [0.7.3]

### Added

- **Security-binding golden suite is graded (`#662`).** A table-driven runner
  (`check-security-binding.fixtures.test.mjs` + its co-located expectations manifest) runs
  every fixture under `evals/fixtures/security-binding/` through
  `check-security-binding.mjs` and asserts exit code + defect-naming findings: 109 fixtures
  (14 pass-expected, 95 reject-expected), zero quarantined, with the fixtures' 67 probe
  transcripts enumerated as suite inputs. Self-policing in both directions — an ungraded
  new fixture, an unlisted transcript, or a manifest entry whose file vanished all fail the
  suite, and the repo's orphaned-fixture gate no longer grandfathers the set.

## [0.7.2]

### Changed

- **Pillar 3 reconciled with the audited native-surface reality (`#351` audit).** The
  causal-tree contract now states explicitly that `traceparent` propagation binds
  CONTRACT-AUTHORED emissions, and that a native agent surface ignoring inbound context (a
  default surface may, honoring it only behind an opt-in) does not break the tree — its
  session emissions attach query-side through the Pillar 2 join attribute, and relying on
  direct native span joining is a recorded migration trigger, not an assumption. The CI
  OTLP template's trace-context-injection section carries the same surface-specific caveat
  plus the `OTEL_RESOURCE_ATTRIBUTES` injection the setup flow already wires. No emission
  or checker behavior changes.

## [0.7.1]

### Added

- **D1 deferral sweep — every out-of-package note from the WP1–WP7 design rounds now has a
  durable trigger record (`#353`).** The README roadmap gains the fleet guardrail
  materializations, fleet routine stand-up + existing-scheduler reconciliation,
  vendor-binding capability templates, and cost-enforcement rows; the trigger register gains
  the second-binding-consumer cross-repo drift check; `reference/return-accounting.md`
  records the per-work-class precision-graduation deferral beside its band-stability rule.
  Documentation only — no contract semantics change.
