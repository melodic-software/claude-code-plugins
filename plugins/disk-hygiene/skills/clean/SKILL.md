{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "claude-ops",
  "version": "0.63.21",
  "description": "Claude Code operations toolkit. Twelve skills: audit-skill-visibility (audit whether each installed skill is actually VISIBLE to the model, and diagnose why most of a fleet never gets used: a skill is invisible when its description is dropped by Claude Code's skill-listing context budget, which sheds descriptions lowest-score-first so an unused skill loses the keywords that would let it be matched, from skills genuinely not wanted, from skills the run cannot observe at all; computes whether the listing overflows from documented settings, and withholds every cold verdict the data cannot support rather than reporting absence of data as absence of use), inventory (read-only enumeration of the complete invocable surface: every built-in CLI command with aliases and hidden/gated status, every bundled skill, and every component of every installed plugin across all marketplaces; reads the shipped binary because upstream publishes no built-in command list, and carries an integrity verdict so a drifted build reports counts as floors rather than silently short totals), audit-install-state (read-only audit of the machine-scope ~/.claude installation directory and ~/.claude.json: full inventory split into an authored surface and rolled-up bulk trees, product-managed retention vs genuinely unmanaged state, filename-scheme resolution before any process-liveness check, and deliberate/mid-experiment detection; reports, never deletes), audit-performance (read-only slowness-diagnostic capture run at the moment the machine or a session feels slow: CLI version, retention-sweep health including the silent unparsable-settings pause, a timed census walk of the install tree as a sweep-cost proxy, active-session and plugin-fleet counts, a process census, and the fan-out layer, which covers a load-labeled no-op spawn baseline, every hook that will fire bucketed per-tool-call versus per-turn with its invocation shape, the configured statusline, subagent concurrency and spawn-depth ceilings against documented defaults, whether running sessions predate the settings file they are judged by, and orphan attribution by parent liveness rather than age, plus on Windows a kernel-object census (Token objects against uptime, paged pool) that names a host-level leak beneath all four suspects; read against a bundled known-performance-issues reference that also records the causes tested and cleared; separates the four documented suspects of accumulated state, version regression, component bloat, and per-spawn fan-out cost, and routes remediation out; reports, never mutates, and never executes a discovered hook or statusline command), audit-native-overlap (map native Claude Code surfaces, namely built-in CLI commands, bundled skills, plugin-backed built-ins, and session-provided skills, against the current repo's plugin skills and agents, so a custom component never silently duplicates what Claude Code itself ships; bare invocation is a read-only overlap report carrying the extraction's integrity floors and a shared-listing-budget exposure section, verdicts are human-gated in a committed store rendered into a generated registry whose every row carries an observable recheck trigger, and only an explicit apply step bakes presence-gated native references into descriptions and Boundary sections), observability (read locally captured telemetry from the OTEL store, the collector, the per-session hook event log and hook-event JSONL, and ccusage, with trend reports, a per-session report of what fired, what was blocked and the event timeline, and store pruning), known-issues (search known Claude product GitHub bugs, check service health, maintain a persistent tracked-issue registry), changelog (ingest Claude Code changelog entries and integrate them into the current repo), plugins (bring a machine's plugin fleet current on demand: marketplace refresh, effective-scope updates including in-repo project/local installs, new-plugin install per policy, scope-divergence detection and explicit convergence), morning-brief (read-only gh-based operator morning view: queue-label counts, merge-ready PRs, parked decisions with their RECOMMENDED lines, and loop-lane telemetry freshness), lanes (start/restart/stop/status loop lanes as named background Claude Code sessions seeded from canonical prompt files, with per-lane model/effort, a repo-pull + marketplace-refresh launch step, and a consume-restarts action, an OS-schedulable reader that relaunches stopped lanes whose telemetry carries a restart_request), and a re-runnable setup action that settles where the known-issues registry, the skill-usage log and the hook log root live, places the root's self-ignoring guard, and detects retired conventions. Plus an opt-in, default-off per-session hook event log (one JSON line per hook event on every event the generated registry marks observable, written to <root>/sessions/<session_id>.jsonl, with SessionEnd retention by session count or age and an optional detached pre-prune command), a family of eight advisory *-audit hooks (API errors, config changes, instruction loads, permission denials, pre-compaction, skill usage, tool failures, and unsurfaced hook failures. The last also warns the user via systemMessage, since a hook that fails to launch enforces nothing and Claude Code surfaces the failure to nobody) that emit the shared hook-telemetry envelope, and a reference sink that routes envelopes under the same root: per session when the envelope carries a session id, else into the shared hook-events.jsonl the observability skill reads.",
  "author": {
    "name": "Melodic Software",
    "email": "info@melodicsoftware.com"
  },
  "license": "MIT",
  "keywords": [
    "claude-code",
    "operations",
    "observability",
    "otel",
    "troubleshooting",
    "changelog",
    "monitoring",
    "hooks",
    "telemetry",
    "audit",
    "plugins",
    "marketplace",
    "dashboard",
    "performance",
    "diagnostics"
  ],
  "userConfig": {
    "registry_dir": {
      "type": "string",
      "title": "Registry directory (project-relative)",
      "description": "Optional contained project-relative directory holding the known-issues registry (registry.json). Absolute, drive, UNC, traversal, and escaping-symlink paths are invalid. Leave unset to use ${CLAUDE_PLUGIN_DATA}."
    },
    "skill_usage_dir": {
      "type": "string",
      "title": "Skill-usage log directory (relative subpath under the scope root)",
      "description": "Optional contained relative directory where the skill-usage-audit hooks write skill-usage.jsonl, resolved under the skill_usage_scope root (repo scope: the project root; user scope: $HOME). Absolute, drive, UNC, traversal, and escaping-symlink paths are invalid in every scope. Ignored by the data-dir scope (plugin-owned layout). Leave unset to use .claude/observability."
    },
    "skill_usage_scope": {
      "type": "string",
      "title": "Skill-usage log scope",
      "description": "Where the skill-usage store lives. Valid values: \"repo\" (the default, a project tree under the repo root, kept out of git status via a machine-local .git/info/exclude entry), \"user\" (the skill_usage_dir subpath under $HOME, one cross-repo store; rows carry a project field), \"data-dir\" (${CLAUDE_PLUGIN_DATA}/skill-usage/<repo-slug>, plugin-owned and update-safe). The manifest schema has no enum type, so this validates in prose; any other value is treated as \"repo\" with a one-time advisory.",
      "default": "repo"
    },
    "skill_usage_git_exclude": {
      "type": "boolean",
      "title": "Machine-local git exclude for the repo-scope store",
      "description": "When the repo-scope store sits inside a git work tree, idempotently add its directory to .git/info/exclude (machine-local; never touches .gitignore or tracked files) so git status stays clean. Set false if your team deliberately commits the telemetry.",
      "default": true
    },
    "install_new": {
      "type": "string",
      "title": "New-plugin install policy for the plugins skill's sync action",
      "description": "Controls what `sync` does with catalog plugins that aren't installed yet. Valid values: \"ask\" (the default, which offers them in one batched multi-select prompt), \"all\" (install every one automatically), \"none\" (report only, never install). The manifest schema has no enum type, so this validates in prose, not JSON Schema; any other value is treated as \"ask\".",
      "default": "ask"
    },
    "api_error_audit_enabled": {
      "type": "boolean",
      "title": "api-error-audit hook",
      "description": "Emit turn-failure telemetry on API errors",
      "default": true
    },
    "config_change_audit_enabled": {
      "type": "boolean",
      "title": "config-change-audit hook",
      "description": "Emit telemetry on config-source mutations",
      "default": true
    },
    "instructions_loaded_audit_enabled": {
      "type": "boolean",
      "title": "instructions-loaded-audit hook",
      "description": "Emit telemetry on rule/instruction file loads",
      "default": true
    },
    "permission_denied_audit_enabled": {
      "type": "boolean",
      "title": "permission-denied-audit hook",
      "description": "Emit telemetry on permission denials",
      "default": true
    },
    "pre_compact_audit_enabled": {
      "type": "boolean",
      "title": "pre-compact-audit hook",
      "description": "Emit telemetry on context-compaction events",
      "default": true
    },
    "skill_usage_audit_enabled": {
      "type": "boolean",
      "title": "skill-usage-audit hook",
      "description": "Emit telemetry on skill usage; shared by both skill-usage audit hooks (the Skill-tool and slash-command expansion paths) and also gates the shared skill-usage.jsonl store",
      "default": true
    },
    "tool_failure_audit_enabled": {
      "type": "boolean",
      "title": "tool-failure-audit hook",
      "description": "Emit telemetry on Write/Edit/Bash tool failures",
      "default": true
    },
    "hook_failure_audit_enabled": {
      "type": "boolean",
      "title": "hook-failure-audit hook",
      "description": "Warn once per session per hook when the transcript records hook launch/exec failures Claude Code never surfaced",
      "default": true
    },
    "instructions_loaded_audit_log_session_start": {
      "type": "boolean",
      "title": "instructions-loaded-audit session_start logging",
      "description": "Opt back into logging session_start instruction loads (dropped by default as deterministic and high-volume)",
      "default": false
    },
    "stdin_read_timeout": {
      "type": "number",
      "title": "Hook stdin read timeout (seconds)",
      "description": "Idle bound on reading the hook payload from stdin: how long the pipe may go silent before the hook gives up and fails open",
      "default": 2,
      "min": 1
    },
    "session_event_log_enabled": {
      "type": "boolean",
      "title": "session-event-log hook (per-session hook event log)",
      "description": "Append one JSON line per hook event to <session_event_log_dir>/sessions/<session_id>.jsonl, on every documented event the generated registry marks observable. Off by default: a consumer who has not turned it on pays the kill-switch read and nothing else. The same switch gates the SessionEnd retention hook.",
      "default": false
    },
    "session_event_log_dir": {
      "type": "string",
      "title": "Hook log root (project-relative)",
      "description": "Contained project-relative directory holding the per-session hook event log (sessions/) and the telemetry sink's hook-events.jsonl. Absolute, drive, UNC, traversal and escaping paths are invalid, and the project root itself is refused. Inside a checkout the directory carries a self-ignoring .gitignore, created on the first write. Leave unset to use .observability/claude.",
      "default": ".observability/claude"
    },
    "session_event_log_categories": {
      "type": "string",
      "title": "session-event-log categories",
      "description": "Comma-separated event categories to record (session, prompt, tool, permission, agent, task, turn, config, worktree, compaction, model, mcp, display, other). Empty records every category the registry marks observable.",
      "default": ""
    },
    "session_log_keep_sessions": {
      "type": "number",
      "title": "Retention: sessions to keep",
      "description": "At SessionEnd, keep the newest N session files regardless of age (a file is kept when it is among the newest N OR younger than session_log_keep_days).",
      "default": 30,
      "min": 1
    },
    "session_log_keep_days": {
      "type": "number",
      "title": "Retention: days to keep",
      "description": "At SessionEnd, keep every session file younger than N days regardless of count (a file is kept when it is younger than N days OR among the newest session_log_keep_sessions).",
      "default": 14,
      "min": 1
    },
    "session_log_pre_prune_command": {
      "type": "string",
      "title": "Retention: pre-prune command",
      "description": "Optional command run detached at SessionEnd with one argument, a directory the session files about to be pruned were moved into; the physical delete of that directory happens on the next retention run after 24 hours, so an archiver has a stable set to read. Executed through `bash -c`, so it is trusted configuration: on current releases project and local pluginConfigs are ignored and only the user's own settings supply it (recheck: the plugins reference's user-configuration section). Leave unset to delete directly.",
      "default": ""
    }
  }
}
or a large root (a home directory, anything whose recursive walk could exceed the engine's entry cap),
start with a bounded pass: add `--max-depth 1` to inventory the target's loose files and immediate children,
then fan out deeper scans per subtree that the evidence justifies. After that depth-1 pass, re-inventory
the directories the operator approved with `--root-children` and one `--root-child <name>` per approved
immediate child: one snapshot, paths relative to the original target, no whole-home walk. The engine backs this with a
deterministic gate: a scan whose target resolves to the user home directory or a non-OS volume root (a
Windows Dev Drive, an OS-managed root still cannot be walked as a whole, and reaches the engine only via
`--root-children`) and carries neither `--max-depth` nor `--confirmed-large-scan` returns
`large-target-confirmation-required` (after a cheap top-level probe, not a full walk) instead of the
unbounded traversal, so a forgotten bound never becomes an accidental whole-volume scan. `--max-depth` is
the preferred bounded response. When the target is an OS-managed volume root, first run with
`--root-children` alone, present the `admitted_children` list through the [confirmation
gate](#confirmation-gate)'s root-children row, then re-run with the same flag plus each chosen `--root-child
<name>`. One run directory, one snapshot, one report covers every selected subtree. Never invent the
selection. Reserve `--confirmed-large-scan` for a deliberate full walk the human has confirmed, pass the
[confirmation gate](#confirmation-gate)'s scan-scope row first, the same standing before an expensive step
that the apply lane demands before a destructive one; a general "clean my home directory" is not that
confirmation. Every directory whose descendants were not walked, cut off by `--max-depth`, a protected
root, or a VCS boundary, is recorded in `truncated_paths` (under `--quiet`, stdout carries only their count and
the snapshot the list); report them as coverage gaps, never as clean,
and never plan them for removal (the preview blocks them as `truncated-not-inventoried` and skips the live
re-verification checks a candidate with no live-I/O value left to give would otherwise still pay for). Each
fan-out worker receives a bounded subtree and returns evidence only. The parent owns classification, the
single report, every approval, preview, and all execution. Do not let workers delete or prepare approvals.

The bundled [baseline policy](reference/baseline-policy.json) contains cross-platform candidate hints
and protected names. Without `--policy`, the engine also layers standing policy files when present:
`~/.claude/disk-hygiene.json` (user-global), then `<project>/.claude/disk-hygiene.json` via
`--project-dir`. An explicit `--policy` is the invocation-specific choice and replaces both standing
layers. Every overlay can only disable/add hints and add protected globs; none can weaken hard guards.
The scan output names its `policy_sources`. Treat scan errors and unvisited protected roots as
coverage gaps, not clean results.

The scan output may also carry an `os_autoclean` advisory when the target overlaps a zone an OS
mechanism (Windows Storage Sense, systemd-tmpfiles) should own. Surface its recommendation in the
report; prefer enabling the OS mechanism over hand-cleaning that zone, mirroring the managed-state
rule below.

## 2. Establish evidence and ownership

A hint annotation is not the only trigger for triage: at a user-home target, treat any loose
root-level entry whose `protected_reasons` is empty and that does not belong to a recognizable
app/config convention as suspicious too, the snapshot already carries it (every walked entry is
recorded with a possibly-empty `hints` list), so nothing further needs discovering, only judging.
Read the entry's own `protected_reasons`, never one policy field: protection also comes from name
patterns and from live filesystem state, and an entry that names a single field as its filter will
step straight past a cloud-sync root whose name embeds a tenant.
This positional read is how session-state droppings that share no common name (a runner-controller
status snapshot, a one-off data export) surface for ownership triage even without a matching hint.

For each hinted or suspicious entry, inspect enough neighboring content and metadata to answer:

1. What created it? Prefer a manifest, log, documented naming contract, sibling structure, or owning
   tool over an age/name guess.
2. Is the owner active? Check current process/tool state without killing, pausing, or modifying it.
3. Does the owning system provide cleanup or retention? Its dry-run result is authoritative.
4. Could this be real work product, a resumable download, a backup, a dependency pinned by constraints,
   or a shell/cloud-sync folder? If uncertain, keep it.
5. Is the evidence current for this exact path? Re-resolve every sibling independently; never
   interpolate names from one batch member. Triage of the entry is done when each of the five
   questions has an evidence-backed answer or is recorded as unknown. An unknown answer to question
   2 or 4 rules out High in step 3; an unknown on question 4 keeps the entry at Low.

## 3. Classify and report

Safe tidiness leads; reclaimed space follows. Confidence is report priority, not permission, and
byte size is never a ranking key:

| Tier | Minimum evidence | Default outcome |
|---|---|---|
| High | Explicit disposable provenance plus a second independent signal; owner inactive; work-product question resolved | Offer exact-path approval |
| Medium | Likely disposable, but one ownership/provenance fact is indirect | Review, then optionally offer its own approval |
| Low | Name/age-only, conflicting signals, resumable or user-content possibility | Keep unless the human separately reviews and approves exact paths |

Report every finding with these fields, in this order, size last:

1. **Provenance**. Where it came from, resolved from evidence (a manifest, a config's own
   contents, an owning repository's source, a documented naming contract), never guessed from the
   name alone.
2. **What it is**. Intent / role of the entry (`reason` in engine plans).
3. **Why removable**. Why it is not work product, plus owner / native-GC result.
4. **Risk**. What could go wrong if it is removed (and why that risk is acceptable at this tier).
5. Path, tier, evidence, disposition.
6. Logical / reclaimable bytes as a **secondary** signal only. A finding is complete only with
   all six fields; a finding with name-only provenance is Low.

Separately list protected, locked, needs-elevation, unverified, and coverage-gap entries.

**Empty directories are first-class findings.** They are not inherently junk, but zero-byte residue must
stay visible and rankable: never drop an empty directory from investigation or from the report because it
reclaims nothing. Prefer ranking by tier, location sensitivity (for example volume-root or home-root
orphans), and provenance strength over byte totals. The snapshot already distinguishes them for you: a
walked directory whose `logical_size` is `0` with an empty `size_qualifiers` is a genuinely empty directory,
while a `logical_size` of `null` carrying the `not-walked` qualifier is an uninventoried coverage gap. Never
fold the first into a byte-centric roll-up that drops it, and never read it as the second.

Those ranking preferences stay a model instruction. The engine does not grow a ranking signal on
the destructive surface.
**Claim:** ranking by tier, location sensitivity, and provenance strength is not an engine
primitive; the provenance mandate does not rest on a coded ranker. **Basis:** operator park
2026-09-27 on #3858 (keep attended, stay parked): ranking on a deletion-adjacent surface is a
design question, not a missing sort key. **As of:** 2026-09-28. **Recheck:** an operator unpark
of #3858, or a documented case where byte-size ranking caused a wrong deletion offer.

**Lead the frontier with `children_rollup`.** The snapshot carries one row per immediate child the run covered, whatever
that child's coverage, and `walked` is the single discriminator: `true` means every aggregate is exact; `false` means
they are all `null` with `unwalked_reasons` naming the cause, never `0`, never a partial subtree sum. Rank on
`reclaimable_local_bytes`, never on `logical_bytes`, a logical total that `size_qualifiers` flags as inflated by cloud
placeholders, hard links, or sparse extents. The block opens no directory the walk did not, so a `--max-depth 1` pass
returns `depth-cut`/`null` for every NON-EMPTY child: the frontier is complete, but a recursive total is bought only by
fanning a deeper scan out over that subtree, report those rows as coverage gaps, never as small or clean.
`scan-complete` also carries `unhinted_entries`, `entries` minus `hinted_entries`, every inventoried entry no hint
judged. So quote hint coverage as a rate: 7 hinted of 40,247 is 0.017 %, nothing like "7 findings". Fields, reasons
and the measurement: [the safety model](reference/safety-model.md). When a run needs the frontier ranked but not
the rows themselves in context, add `--quiet`: the rollup stays complete in the snapshot and stops being duplicated
onto stdout, where one row per immediate child dominates a wide target's payload.

**Relocation is out of scope.** This skill offers exactly two outcomes per finding, keep it, or approve its
exact path for deletion. There is no relocation lane and no move primitive in the engine, by design: a move
is not a containment-checkable, revalidatable, token-bound operation the way a delete is. So when the right
answer for a misplaced entry is "this belongs somewhere else", say so and report it as **keep**; the
operator performs and verifies the move themselves, outside this workflow. Never imply the report's
keep-or-delete choice is the complete set of dispositions, and never stage a move through the manual
handoff.

An entry's `logical_size` is reclaimable local bytes only when its `size_qualifiers` is empty. Exclude every qualified
entry from any reclaimable-bytes total and state the qualified bytes separately with their reasons, a
`cloud-placeholder` carries its REMOTE size while occupying roughly nothing locally; a `hardlinked` name shares one
object with other names; a `sparse` file's logical size overstates local allocation; and `not-walked` means the subtree
was never inventoried, so `logical_size` is `null` rather than `0`, except on the target's own record, which keeps its
partial walked sum alongside a `not-walked` qualifier, so read that number as a floor. Prefer the snapshot's
`target_reclaimable_local_bytes` (and preview/apply `reclaimable_local_bytes*`) over summing `logical_size` yourself.
Folding qualified or unknown sizes into a total claims space that deleting the path would never return. Never treat a
low or zero reclaimable-byte figure as a reason to skip a finding that otherwise clears the evidence bar.

## 4. Build one exact-tier plan

Only after an execution request (`--execute`, or the in-session request in
[Arguments and boundaries](#arguments-and-boundaries)), write `<run-dir>/plan-<tier>.json`; never
mix tiers:

```json
{
  "version": 1,
  "tier": "high",
  "candidates": [
    {
      "path": "relative/exact.tmp",
      "tier": "high",
      "provenance": "documented atomic-write staging name; owner process absent",
      "reason": "failed atomic-write staging file",
      "evidence": ["documented name shape", "owner process absent"],
      "why_not_work_product": "generated staging bytes with no durable consumer",
      "risk": "low: regenerable staging residue; no live consumer",
      "owner": "unmanaged"
    }
  ]
}
```

For managed state, report the documented native command and its current dry-run result, but do not add
the path to an engine plan. Paths in an engine plan are unmanaged, snapshot-relative, exact,
non-overlapping, and never globs.

## 5. Preview, then ask

Run the deterministic gate:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" preview \
  --snapshot "<run-dir>/snapshot.json" --plan "<run-dir>/plan-<tier>.json" \
  --data-root "${CLAUDE_PLUGIN_DATA}"
```

It rechecks containment, identity and full descendant set, hard protections, Git's index, and live
handles from current state rather than trusting snapshot annotations. It also proves Linux mount and
directory-descriptor prerequisites. Windows and macOS return `execution-platform-unsupported`. Any
blocker means no approval prompt and no deletion. Fix nothing behind the gate; rescan.

`outcome` names where the preview routes you, and the exit code follows it: `explicit-approval`
(status `ready-for-explicit-approval`, exit 0); `manual-handoff-lane` (status `blocked`, exit 0),
when every blocker on every candidate is `execution-platform-unsupported`, a fact about the host
rather than any path; and `blocked` (exit 3), when any other blocker is present, including beside
the platform one. Invalid input exits 2. `manual-handoff-lane` issues no approval token, and
`apply` still refuses it.

When status is `ready-for-explicit-approval`, show a table naming every path with provenance, what
it is, why removable, risk, whether it is an empty directory, the single tier, and only then logical
/ reclaimable bytes, plus the preview's approval token, then pass the
[confirmation gate](#confirmation-gate). The approval must name **exactly that tier and list**.
Process another tier only with a new plan, preview, and question.

## 6. Apply only the confirmed preview

After an affirmative answer in this interactive session, run only:

```text
"<hook-python>" "${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/hygiene.py" apply --execute \
  --snapshot "<run-dir>/snapshot.json" --plan "<run-dir>/plan-<tier>.json" \
  --confirm-tier "<tier>" --approval-token "<token>" --report "<run-dir>/report-<tier>.json" \
  --data-root "${CLAUDE_PLUGIN_DATA}"
```

Never use `rm`, `rmdir`, `Remove-Item`, `del`, `find -delete`, or an ad-hoc Python deletion call. The
skill-frontmatter belt blocks those bypasses and returns a hook-issued `ask`
(`permissionDecision: "ask"`) for the exact engine apply command, the same mechanism as the
PowerShell deletion lane below, including the `dontAsk` / `permissions.ask` caveats. Confirm that
prompt only when it matches the tier and paths just approved. If the plan, snapshot,
path identity, descendant set, VCS state, or handle state changed, re-scan and re-ask; never reuse a
token.

Summarize tidiness outcomes first: the paths removed (the report's `removed` list), how many of them
were empty directories, the coverage gaps that remain, and every skip grouped by `locked`,
`changed-or-link`, `protected`, `needs-elevation`, `handle-state-unverified`, or `delete-failed`.
Report `reclaimable_local_bytes_removed` and the observed free-space delta **after** those tidiness
figures, never as the headline. Do not claim the observed free-space delta is exact: concurrent disk
activity, sparse files, hard links, compression, and delayed allocation affect it.

### Unsupported-platform handoff (Windows, macOS)

Preview reports `execution-platform-unsupported` as a per-candidate blocker on Windows and macOS,
so the engine never deletes there and the default outcome is the report. When, and only when,
an execution request was made on one of those platforms and the human approved an exact single-tier
path list in this session, read
[reference/unsupported-platform-handoff.md](reference/unsupported-platform-handoff.md) and follow
it. It owns the approved-path forms (inline `--path`, or `handoff-paths.json`), the per-path
revalidation, and the hook belt that outlives the cleanup. Do not improvise a manual deletion
lane from the engine steps above.

## Gotchas

Harness mechanics live in one copy, in the safety model, so a fix there cannot leave a stale
restatement behind here. Load [the safety model](reference/safety-model.md) when you need
them: how the guard registers on two surfaces, how the kill switch is delivered and scoped, and
what the PowerShell lane flags → "Kill-switch enforcement"; how the hooks launch, what that bounds,
and what the guard does when no Python resolves → "Hook launch form".

- POSIX permits unlinking an open file, so successful deletion is not a live-handle check. Linux
  execution requires an authoritative `lsof` result and fails closed on diagnostics or missing access.
- Python 3.11 has no `os.path.isjunction`; the engine reads the Windows reparse attribute from `lstat`
  and treats every reparse point as protected. Windows execution remains disabled.
- `os.path.ismount` cannot reliably identify same-filesystem bind mounts. Linux execution therefore
  parses `/proc/self/mountinfo` and fails closed if that namespace view is unavailable.
- Apply opens every Linux parent with `O_NOFOLLOW` relative to the already-open target descriptor,
  verifies the descriptor identity, and removes only by descriptor-relative `unlink`/`rmdir`. A
  directory is reopened without following links, matched by device/inode/type, and proven empty after
  its captured children are removed.
- A directory's contents can change after preview. Apply revalidates each captured entry and removes
  bottom-up; it never follows a new link or recursively discovers new entries. The manual-handoff
  lane's container re-enumeration rule applies this same changed-since-scan discipline where no
  snapshot token exists.
- `allowed-tools` would pre-approve rather than restrict tools, so this destructive skill intentionally
  grants none. Consumer permission policy remains authoritative.
- The Bash lane is deny-by-default: only the literal-word bundled scan, preview, handoff-verify, and
  apply shapes (plus the argument-free kill-switch probe) pass, using the hook runtime's own absolute
  interpreter. Do supporting inspection with non-Bash read-only tools. Shell expansions, globs,
  splitting/escape forms, operators, redirections, aliases, and exported functions fail closed.
- The PowerShell lane is the inverse tradeoff: open for read-only support work, hard-denying engine
  invocations, and turning known deletion spellings into a hook-issued `ask`
  (`permissionDecision: "ask"`). The hooks reference says that value asks the user about the tool
  call, and the permission-modes page says auto mode still shows a prompt a hook forces, so the
  classifier can still deny but cannot silently approve. Verified 2026-09-06 against Claude Code
  2.1.263 at `https://code.claude.com/docs/en/hooks#pretooluse-decision-control` and
  `https://code.claude.com/docs/en/permission-modes`; recheck when either page stops carrying those
  statements, or when a release note names hook permission decisions.
  An explicit `permissions.ask` rule for those deletion
  spellings is what the same docs treat as forcing a prompt in `auto` and `bypassPermissions`;
  in `dontAsk` that rule is denied with no prompt, so leave `dontAsk` first if the per-path
  handoff confirm must appear. Add one if the manual handoff must not depend on hook-`ask`
  surfacing. The lane is a raised bar, not fail-closed; its flagged set is enumerated, so an
  unflagged mutation spelling passes it. The engine's own containment and the Bash lane remain
  the deletion authority.
- The guard rejects `~` anywhere in a Bash command as a shell-expansion character, which includes
  Windows 8.3 short names (`SOMEUS~1`). Always pass long-form paths; the guard's own disclosures
  are already long-form.
