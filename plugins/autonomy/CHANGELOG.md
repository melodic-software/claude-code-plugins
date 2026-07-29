# Changelog

All notable changes to the `autonomy` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

Versions 0.1.0–0.7.0 predate this file (introduced with 0.7.1); their history lives in the
merged work-package PRs (#333, #343, #356, #372, #377, #600, #676).

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
