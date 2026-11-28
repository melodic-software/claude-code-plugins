---
description: "Inspect improvement config cascade and evidence sources read-only (check, default) or interview and write team improvement.yaml (apply)."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Verify and manage the consuming repo's tracked evidence-source config at
`<home>/improvement.yaml`, so `/improvement:find` resolves Tier 2 telemetry sources and churn
tuning from a declared contract instead of having nothing to consult.

The config is optional in every layer: with none, the finder runs fully on Tier 0 repo-native
evidence with the default churn settings, and Tier 2 is a recorded evidence gap, so total
absence is a reported INFO, never a FAIL. The key contract, layer paths, and merge semantics
live in `${CLAUDE_PLUGIN_ROOT}/reference/config.md` (the single home. This skill implements
that contract and does not restate it).

## Actions

Two actions only. No argument or `check` runs the read-only check; `apply` runs the check first,
then the interview-and-write flow. Any other argument is an error naming these two actions.

## The config cascade

Four layers, resolved plugin default → `userConfig` → team (`<home>/improvement.yaml`, tracked) →
personal (`<home>/improvement.local.yaml`, gitignored), merged per the semantics declared in
`${CLAUDE_PLUGIN_ROOT}/reference/config.md`: per-key override for scalars, a ceiling personal
layers can only lower for `find_open_item_cap`, union for
`churn_exclude`, per-source-name merge for `evidence_sources` with an empty-body opt-out. That
file also owns `<home>` and the root rule. Anchor
every repo-relative read at the repo root (`git rev-parse --show-toplevel`), never at the CWD.

The `userConfig` layer, read from this text, where Claude Code substitutes it
([reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value));
empty, or a literal `${user_config.…}` placeholder, means unset:

| Option | Value |
|---|---|
| `churn_window` | `${user_config.churn_window}` |
| `churn_exclude` | `${user_config.churn_exclude}` |
| `churn_exclude_defaults` | `${user_config.churn_exclude_defaults}` |
| `find_open_item_cap` | `${user_config.find_open_item_cap}` |
| `find_run_item_cap` | `${user_config.find_run_item_cap}` |
| `find_run_item_cap_floor` | `${user_config.find_run_item_cap_floor}` |
| `find_run_item_cap_ceiling` | `${user_config.find_run_item_cap_ceiling}` |
| `find_size_band` | `${user_config.find_size_band}` |
| `find_scope` | `${user_config.find_scope}` |
| `find_suppress_dismissed` | `${user_config.find_suppress_dismissed}` |
| `evidence_sources_file` | `${user_config.evidence_sources_file}` |

This skill writes only the team file (`<home>/improvement.yaml`). It never writes
`userConfig`: an option is set through `/plugin configure improvement@<marketplace>`, and we
confirm a changed value in a fresh session; for when a saved value applies, read
[plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure).

## `check` (read-only)

Inspect the effective merged config and report a PASS/FAIL/WARN/INFO table with one remediation line
per FAIL. Modify nothing, and do not run a scan. That is `/improvement:find`.

1. **Layer presence.** Resolve `<home>` and classify the root as the config contract says, then
   report each layer: every `userConfig` option set in the table above, `<home>/improvement.yaml`,
   and `<home>/improvement.local.yaml`. All absent →
   INFO: the finder uses bundled defaults and records Tier 2 as an evidence gap; `apply` writes
   `<home>/improvement.yaml` to declare sources. When the `evidence_sources_file` cannot be read,
   WARN it was not considered rather than presenting the readable layers as the whole effective
   config.
2. **Retired conventions.** Run
   `bash "${CLAUDE_PLUGIN_ROOT}/lib/check-retirements.sh" --manifest "${CLAUDE_PLUGIN_ROOT}/retirements.yaml" --root "<root>"`,
   with `<root>` the path `git rev-parse --show-toplevel` printed (the root every other read in
   this skill anchors at). Never leave out `--root`: the helper otherwise checks
   `${CLAUDE_PROJECT_DIR}` first, a subdirectory when the session started in one. When the root
   does not resolve, the root rule already skips these layers: skip this step and say so.
   Exit 0 → PASS (any `report-only` TSV rows printed as INFO history; they are no longer read as
   config layers and cleanup is not offered). Exit 1 → one finding per active TSV row: `migrate` is
   FAIL, `delete`/`remove-line` WARN, `report-only` INFO; remediation is `apply`. Exit 2 → FAIL,
   never silent. Bash unavailable → report the step UNKNOWN with remediation, never green.
3. **Effective configuration.** Report the merged result and which layer supplied each value:
   the effective `churn_window`, whether exclusions resolved from the repository are on (`churn_exclude_defaults`), declared
   `churn_exclude` additions, the effective `find_open_item_cap` and unattended run controls (`find_run_item_cap`, its floor and ceiling, `find_size_band`, `find_scope`, `find_suppress_dismissed`), and every `evidence_sources` entry (name, `mcp_server`, `kind`,
   scope), including entries a later layer opted out, reported as removed, not broken. A
   malformed layer degrades soft: name it, resolve as if absent, report the parse error.
4. **Key validity.** Each `evidence_sources` entry names an `mcp_server`; an entry missing it is
   FAIL, naming the entry. A `find_open_item_cap` that is not a non-negative integer is FAIL,
   naming the layer, and a personal value above the team value or default is WARN: it is ignored.
   Any other `find_*` value outside its type in the key contract, or a run cap whose floor, start
   and ceiling do not ascend, is FAIL, naming the layer. Where the session can enumerate available MCP servers, note (INFO)
   any declared server not currently available. At find-time that source becomes an
   evidence-gap line, which may be expected on this machine.
5. **Tracked, not ignored.** A present team file (`<home>/improvement.yaml`) must be committed to be team-shared, and
   "not ignored" is not "tracked". Probe both: `git check-ignore -v <team file>`
   (non-empty result is FAIL with the matching pattern) and
   `git ls-files --error-unmatch <team file>` (non-zero exit is FAIL: the file is
   present but untracked, the state immediately after `apply` writes it, so teammates will not
   receive it until it is committed; report "untracked, commit it" and, if it is staged but
   uncommitted, say that instead via `git diff --cached --name-only`). A personal file
   (`<home>/improvement.local.yaml`) is expected to be gitignored: one that is tracked or staged is
   FAIL (a personal deviation can reach team history); an ignored one is INFO.
6. **Other-layer divergence.** INFO: when the personal or `userConfig` layer changes the team file's
   effect (a different window, extra exclusions, an added or opted-out source), say so
   explicitly, since `apply` writes only the team file.

## `apply` (idempotent)

Run `check`, then interview and write the team file. Draft values from
the invocation and the repo without asking, but write nothing before the user answers: the first
interview question, with its recommendation, comes before any `Write` to
`<home>/improvement.yaml`, even when every value looks unambiguous. A value the invocation names
is a draft the interview confirms. When the invocation asks to see a proposal instead of a write,
showing the whole draft (the file, the verification of step 5 and the report) with its
recommendations is that question: present it in one reply and write nothing.

1. **Read the effective config first, across all layers**, and present the merged baseline with
   per-layer provenance. Exactly as `check` step 3 reports it. When a higher layer's opt-out or
   override shapes the effective result, warn that editing the team file alone will not change
   what this machine resolves, and point at the owning layer. Nothing is dropped without the
   user confirming.
2. **Draft defaults from the repo.** Before asking: propose `churn_exclude` additions from what
   actually exists (lockfiles, generated or build output trees, snapshots, tool-generated source
   files and vendored trees the repository holds, resolved as the hotspot recipe's Step 2 does in
   `${CLAUDE_PLUGIN_ROOT}/skills/find/context/hotspots.md` (one Read of that file, never Glob or
   Grep the plugin directory), each named with the file that shows it
   is mechanical; the plugin ships no list of them, and a persisted entry is a declared pattern
   that `churn_exclude_defaults: false` does not drop); keep `churn_window` at the bundled default unless the repo's history is
   young or the user says otherwise; keep `find_open_item_cap` and the other `find_*` keys at the bundled defaults unless the
   user names another; and draft `evidence_sources` candidates from the MCP
   servers the consumer has configured that plausibly carry telemetry, a candidate is a
   proposal for the user to confirm, never an assumption. No plausible source and none volunteered
   is a fine outcome: write the churn keys only, and say Tier 2 stays a declared gap. Resolving
   an exclusion from the repository only drafts it: every value this step drafts, a resolved
   exclusion or a source the invocation names included, goes to step 3's interview, and nothing
   is written before the user answers.
3. **Interview, one decision at a time**: window, exclusions, then each telemetry source (name,
   `mcp_server`, `kind`, scope, hints) with a recommendation the user accepts, edits, or
   declines.
4. **Write the team file** `<home>/improvement.yaml`, only after the interview's answers, in the
   file format defined by `${CLAUDE_PLUGIN_ROOT}/reference/config.md`: plain YAML holding only the
   keys the user confirmed. Never write a vendor-specific default the user did not declare.
5. **Verify after writing.** Re-run the `check` probes on the written file: both
   `git check-ignore -v <home>/improvement.yaml` (surface a matching pattern and offer a
   `.gitignore` fix) and `git ls-files --error-unmatch <home>/improvement.yaml` (non-zero exit
   means the file is un-ignored but still untracked, the guaranteed state right after this
   step writes it, so report "written but untracked: commit it to share with the team", never
   success). Then offer the personal convention: personal values go in
   `<home>/improvement.local.yaml`; recommend the consumer add the recursive `<home>/**/*.local.*`
   line (written with the bound home) to `.gitignore` if not already covered. But never edit
   their `.gitignore` yourself.

Re-running `apply` after everything passes changes nothing and reports "already configured".

## Output

`check`: the PASS/FAIL/WARN/INFO table plus the effective evidence-source configuration with
per-layer provenance. `apply`: a tracked
`<home>/improvement.yaml`, the re-run check result, and one paragraph on what was written and how
to re-run this setup to reconfigure.

## What this skill does not do

- Run an improvement scan. That is `/improvement:find`; `check` only inspects config.
- Install or configure MCP servers. It declares which configured server carries telemetry;
  provisioning the server is the consumer's own MCP setup.
- Write `userConfig`, user settings, `pluginConfigs`, the personal override, or the consumer's
  `.gitignore`.
- Write into the plugin directory or the plugin data directory. Configuration lives in the
  consumer's team and personal files and the user's own `evidence_sources_file`.

## Gotchas

- **All layers absent is healthy.** Tier 0 evidence needs no config; do not manufacture a FAIL
  (or a config file) for a repo that has not opted into Tier 2 or churn tuning.
- **CWD is not the repo root.** Invoked from a subdirectory, a CWD-relative read finds a
  nonexistent `<subdir>/<home>/improvement.yaml` and silently reports an absent config. Anchor
  at the root in every self-contained shell call.
- **The interview writes the team file only.** An effective value contributed by the
  personal or `userConfig` layer cannot be changed by it; say which layer owns it instead of
  writing a team value that the higher layer will keep overriding.
- **No git verdict outside the repository.** `git check-ignore` against an `evidence_sources_file`
  outside the worktree is meaningless (or confidently wrong when the home directory is itself a
  repo); the tracked/ignored probes apply to in-repo files only.
- **A same-session `check` can show an old `userConfig` value.** Confirm a changed option in a
  fresh session; when a saved value applies is in
  [plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure).
