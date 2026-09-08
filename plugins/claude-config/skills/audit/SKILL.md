---
description: "Audit Claude Code configuration files, including settings.json, settings.local.json, .mcp.json, hooks, plugins, permissions and environment variables, for correctness, security, and drift against current official docs. Use when: 'audit settings', 'check config', 'check for config drift', after a Claude Code update, or when permissions, hooks, plugins, or MCP servers may be misconfigured; pass --fix to apply auto-correctable findings with confirmation."
argument-hint: "[--fix] [scope]: permissions|mcp|hooks|plugins|issues|all (default: all)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Audit settings, hooks, permissions, and MCP config for drift against current official docs
---

## Pre-computed context

Claude Code version: !`claude --version 2>/dev/null || echo "unknown"`

## Purpose

Periodic audit of Claude Code configuration files against current official documentation and the
consuming project's own conventions. Answers: "Are our settings correct, secure, complete, and up to
date?"

## Adapting to your environment (graceful degrade)

This skill is self-contained. Where a phase names an adjacent capability, such as a Claude Code
issue-tracking skill or a hook plugin's coverage manifest, treat it as optional: if your setup
provides it, use it; otherwise follow the inline guidance here, which stands on its own.
Project-specific conventions (required permission patterns beyond the baseline, documented reasons for
disabled servers, launcher-script wrappers) come from the consuming repo's own `CLAUDE.md` and
`.claude/rules/`. Read them when present; this skill does not assume them.

Two adjacent skills cover neighboring questions: the sibling `audit-automation-gaps` skill asks whether the
configured automation SET is the right set (landscape gaps); the `audit` skill in the `claude-memory`
plugin audits the instruction layer (CLAUDE.md / rules / auto-memory). This skill asks whether the
configuration FILES are correct against upstream truth.

## Arguments

Parse `$ARGUMENTS` for:

- **`--fix`**: Apply corrections automatically (with user confirmation per fix). Without this flag, report-only mode
- **Scope filter**: Limit audit to a single category. If omitted, run all categories
  - `permissions`: deny/ask/allow rules, security gaps
  - `mcp`: MCP server definitions, commands, env vars, connectivity
  - `hooks`: hook scripts exist, timeouts, matchers
  - `plugins`: enabled/disabled status, marketplace availability
  - `issues`: recheck known GitHub issues only
  - `all`: run everything (default)

## Division of labor: the engine decides, the model judges

`scripts/audit-engine.sh` settles every row a script can decide without a reading and emits one
JSON document plus a findings file. The model never re-derives a row the engine settled; it reads
the document and does only what needs judgment:

| Engine (deterministic, emitted once) | Model (judgment, on the engine's output) |
| --- | --- |
| A: `$schema` presence and URL, misplaced `mcpServers`, personal `hooks` in the local file | A: nothing |
| B: presence of each baseline pattern, deny rules in the local file, blanket `Bash(git *)`, the allow-completeness rows at `info`, narrowing 3 where a hook plugin ships a coverage manifest, suppression-record matching | B: narrowings 1 and 2 (a documented exemption, a documented hook convention), narrowing 3 for hooks with no manifest, the consuming repo's extra required patterns |
| C: command resolution, `${VAR}` syntax, URL shape, `enableAllProjectMcpServers`, enabled/disabled coverage and name validity | C: documented reasons for disabled servers, launcher-wrapper conventions |
| D: path resolution and readability, millisecond-shaped timeouts, matcher class and anchoring, placeholder quoting in shell form, duplicates, lever state, cache-versus-loaded divergence | D: whether a timeout is reasonable for its tool, exec-form resolution on a Windows-targeting repo, event validity against the live hooks page |
| E: marketplace membership, explicit `false` entries, ORPHAN / NEW / RENAME drift against the merged scopes, `strict` versus `plugin.json` | E: whether an opt-out is intentional, orphan-`true` review, rename confirmation |
| F: token-shaped values, backslash paths, documentation status against a fetched `env-vars.md` | F: whether an undocumented custom variable is justified |
| G: the measurement, read from an existing debug log | G: the levers, scoped to the roster's composition |
| H and I: every value check | H and I: nothing, once the Phase 3 fetch confirms the behavior the row rests on |

A row the engine marks `skip` or `not-inspectable` is exactly that in the report: never clean.

## Config Files

| File | How to read | Notes |
| --- | --- | --- |
| `.claude/settings.json` | the engine, or `jq` | Project-level, checked in |
| `.claude/settings.local.json` | the engine (structure and the four model and effort keys only) | Commonly deny-listed for the Read tool because it holds tokens. **Never echo secret values** |
| `.mcp.json` | the engine, or `jq` | Project-level MCP server definitions |
| `~/.claude/settings.json` | the engine, or the Read tool | User-level defaults (optional; checked when it exists) |
| start-directory `.claude/settings.local.json` | `check-structure.sh` (structure only) | Only when the session's start directory is not the repository root AND a copy is there. A pre-v2.1.211 Claude Code wrote the file to the start directory and the current one still reads what it left; the repository-root copy wins on a shared key, but **permission rules from both files stay in effect**. The dated record for that boundary is `audit-permission-state/reference/criteria.md` §Scopes |
| `managed-settings.json` + `managed-settings.d/` | `check-structure.sh` (structure only) | Machine-scope managed policy, the highest-precedence layer. OS-specific path resolved by the script (macOS `/Library/Application Support/ClaudeCode/`, Linux/WSL `/etc/claude-code/`, Windows `%ProgramFiles%\ClaudeCode\`). Findings on it are report-only routing; managed policy is the administrator's, never edited by `--fix` |
| managed policy outside the filesystem | not read | The Windows `HKLM`/`HKCU\SOFTWARE\Policies\ClaudeCode` policy keys and the macOS `com.anthropic.claudecode` managed-preferences domain. `check-structure.sh` names them so an absent `managed-settings.json` is never read as "no managed policy deployed", but it does not read them |
| `.claude/audit-pass.md` (three cascade layers) | the engine | The consumer's suppression record, keyed by `finding_id`. A finding it carries is reported as suppressed with its reason; only the team layer suppresses, a personal-only entry is reported as not applied, and a malformed entry is reported and never suppresses |

### Reading settings.local.json safely

Treat `settings.local.json` as secret-bearing regardless of deny rules: the engine and
`check-structure.sh` report key counts, validity, and the four model and effort values by value,
and never dump its contents. Supplemental jq recipes: [context/procedures.md](context/procedures.md)
"Reading settings.local.json safely".

The counts are not guaranteed. Where the project's configuration blocks the read, whether a sandbox
`denyRead` merged from the baseline `Read` deny or filesystem permissions, the engine reports the
scope as `unreadable` and its rows as `not-inspectable` instead of failing. Record the file as not
inspectable, carry that into the report, and do not reach for another reader to get the counts anyway.

---

## Track progress

For any full audit run (Phases 1-5), keep a phase checklist and tick each phase as it completes,
either in-response or by copying `${CLAUDE_PLUGIN_ROOT}/skills/audit/templates/checklist.md`
into wherever the consuming repo keeps working task notes. Phase 5 is SKIPPED in default report-only
mode.

---

## Phase 1: Run the engine

Record the installed Claude Code version (`claude --version`); Phase 3.2 compares issue-fix versions
against it. Then run the engine once, with the findings file in the topic's memory slice (the
`memory_dir` the consuming repo binds, default `.work/`):

```bash
mkdir -p .work/claude-config-audit
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/audit-engine.sh" --table \
  --out .work/claude-config-audit/findings.json \
  [--docs-dir <dir of pages fetched in Phase 3>] [--debug-log <file>]
```

Run it with `--json` instead when you want the whole document; `--table` prints the findings, each
with its paste-ready `suppress:` line, then the suppressed, skipped, and not-inspectable rows, then
the skill-listing measurement. Exit `0` means no error-severity finding, `1` at least one, `2` a
fatal condition (no project settings, `jq` missing). Read the document, not the exit code alone.

Pass `--docs-dir` when Phase 3 has already fetched pages this run: the engine then decides the
environment-variable documentation rows against `env-vars.md` on disk. Pass `--debug-log` when you
know where this session's debug log is; otherwise the engine looks in the documented locations
(`CLAUDE_CODE_DEBUG_LOGS_DIR`, then the newest file under `<user dir>/debug/`).

### 1.0 Hook inventory

The engine runs `scripts/check-hook-coverage.sh` itself and carries its result in
`hook_inventory`. That script enumerates settings-declared hooks **and** the hooks shipped by every
enabled plugin, read from the directory the session actually loads (a `directory` marketplace's
checkout first, the installed-plugin registry otherwise), plus the levers (`disableAllHooks`,
`allowManagedHooksOnly`, `strictPluginOnlyCustomization`) that switch hooks off wholesale, and any
divergence between the loaded directory and the registry's cache snapshot.

**Read the inventory state, not just the rows.** `complete` means every enabled plugin resolved.
`partial` means some plugin did not resolve or a hook config did not parse, and `unreadable` names
which; for anything a partial inventory could not see, keep the conditional posture in
[required-permissions.md](reference/required-permissions.md) "Fail open where the inventory is
incomplete". `none` means no inventory was taken; treat it as partial for every family.

The inventory never runs a hook. Whether a hook *covers* a family is decided by the engine only
where the hook's plugin ships a coverage manifest (`hooks/coverage.json`); every other hook stays
the model's judgment, against the three preconditions in "Narrowing the baseline".

### 1.1 JSON validity

A scope in state `invalid` blocks every other row about that file; the engine reports the invalid
file as an error and nothing else about it.

### 1.2 Structure inventory

Fill the summary table from the engine's `scopes` and `rows`, or from `check-structure.sh` when a
managed layer or a start-directory copy is in play (the engine does not read those):

| File | Valid JSON | Keys | Deny | Ask | Allow | Hooks | MCP Servers | Plugins |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |

### 1.3 Baseline snapshot

Record the engine's `summary` for before/after comparison if `--fix` is used: findings by severity,
permission rule counts, MCP server count, hook count, plugin count.

---

## Phase 2: Validate

Load the audit checklist: [audit-checklist.md](reference/audit-checklist.md)

The engine's rows are settled. Work the judgment column of the division-of-labor table, category by
category; **full per-check criteria in
[context/validation-categories.md](context/validation-categories.md)** (read it when running Phase 2).

- **A, Schema & Structure**: engine-decided
- **B, Permissions**: for each baseline row the engine left at full severity, check narrowing 1 (a documented exemption in the consuming repo's rules) and narrowing 2 (a documented project hook convention); for a hook with no coverage manifest, take narrowing 3 by hand against the three preconditions in [reference/required-permissions.md](reference/required-permissions.md); add any patterns the consuming repo's own rules declare as required
- **C, MCP Servers**: documented reasons for disabled servers; launcher conventions
- **D, Hooks**: timeout reasonableness, exec-form resolution on Windows-targeting repos, event validity against the live hooks page
- **E, Plugins**: whether each explicit `false` is intentional and recorded; orphan-`true` and rename review
- **F, Environment Variables**: whether a variable the engine reports as not on the env-vars page is documented elsewhere or justified by the repo
- **G, Skill-listing budget**: the levers, scoped to the roster's composition (`skillOverrides` reaches project and user skills; plugin skills are managed through `/plugin`); when the engine reports `not measured`, name the routes (`/doctor` interactively, a `--debug` relaunch headless) and never report clean
- **H, Model and effort settings** and **I, Deep-link registration**: engine-decided; Phase 3 confirms the behavior each finding rests on before it is reported

---

## Phase 3: Research & Recheck

External verification against current documentation.

**Read every page in this phase verbatim, not through a summarizer.** These pages are long, with
`settings-reference` and `env-vars` running to hundreds of KB, and a summarizing fetch truncates,
then reports the rows past the cutoff as *absent*. So for each page,
`curl https://code.claude.com/docs/en/<page>.md` to one directory and grep the files, per the
[fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis--the-fetch-route).
**A truncated read supports NO finding.** Say so and move on, in either direction: neither "the key is
gone" nor "the key is unchanged" is reportable from a read that may have been cut.

Then run the citation check over that directory:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/check-doc-citations.sh" --docs-dir <dir>
```

It greps every key and sentence this skill's references cite
([reference/doc-citations.tsv](reference/doc-citations.tsv)) in the fetched pages. A `MISS` means a
checklist row cites text the page no longer carries, and that row is re-derived before it is used;
a `SKIP` means the page could not be read and its rows stay unverified this run.

### 3.1 Official docs check

Keys live on [settings-reference](https://code.claude.com/docs/en/settings-reference); the
[settings](https://code.claude.com/docs/en/settings) page carries file locations, precedence, and
the `$schema` guidance. Compare against both:

- Are there new settings the project should consider adopting?
- Have any settings in use been deprecated or renamed?
- Has permission rule syntax changed?

### 3.2 GitHub issue recheck

For each issue in [known-issues.md](reference/known-issues.md), check live status by the first
route that works, and never let a route that does not work block the run:

1. The REST endpoint, `gh api repos/anthropics/claude-code/issues/<number>`, which some sessions
   serve where GraphQL is refused.
2. The consuming environment's own issue-tracking skill when one is installed
   (`/claude-ops:known-issues` in this marketplace).
3. Neither reachable: report the issue as **unverified since its last-verified date**, taken from
   that column of the table, so the report states how old the recorded state is instead of an
   unqualified "unverified".

For any issue whose upstream fix has shipped at or below the installed Claude Code version, confirm
the settings-specific workaround is still needed and recommend retiring it if not.

### 3.3 Model configuration verification

**MANDATORY** for any category H finding: fetch
[code.claude.com/docs/en/model-config](https://code.claude.com/docs/en/model-config) and confirm the
behavior the finding rests on. Do NOT report a category H finding from this checklist's wording
alone: the accepted `effortLevel` values, the fallback-chain cap, and the allowlist wildcard rule
are all upstream-owned and move with the harness.

### 3.4 Permission syntax verification

Fetch [code.claude.com/docs/en/permissions](https://code.claude.com/docs/en/permissions) and verify:

- The project's permission patterns match current documented syntax
- No new permission types added (e.g., new tool types)
- Wildcard behavior unchanged

---

## Phase 4: Report

Present all findings as a severity-rated GFM table:

| # | Category | Severity | Finding | Current | Recommended |
| --- | --- | --- | --- | --- | --- |
| 1 | B, Permissions | error | Deny rule placed in `settings.local.json`, where bug #8961 leaves it inert | `settings.local.json` → `permissions.deny: ["Bash(rm -rf:*)"]` | Move the rule into `settings.json`; keep `settings.local.json` deny empty |

Then three short sections the engine's document already carries:

- **Suppressed**: each finding the consumer's record retired, with its reason, layer and date, plus
  every `personal-only, not applied` and `malformed` entry by name.
- **Not decided**: every `skip` and `not-inspectable` row, with the reason. An unmeasured skill
  listing, an unreadable local file, and an unfetched page all land here, never in the clean count.
- **Findings artifact**: the path passed to `--out`. Its rows carry audit-pass's identity tuple, so
  `audit-pass` appends them unchanged and a later run diffs against them. When the model adds a
  judgment finding of its own, derive its identity with the engine (`audit-engine.sh anchor` and
  `audit-engine.sh finding-id`) and append the row in the same shape with `"tier": "judged"`.

For any finding the operator decides to keep, print its `suppress:` line as a stanza they can paste
into `.claude/audit-pass.md` (team layer): `check`, `claim`, `sites` with `surface` and
`anchor/v1`, a non-empty `reason`, and today's `date`, keyed by the `finding_id` the engine printed.
That is the declared route for session posture; the skill never infers posture from the
environment.

### Severity guide

| Severity | Criteria |
| --- | --- |
| error | Security gap, broken config, or enforcement bypass |
| warning | Deprecated syntax, missing best practice, stale issue status |
| info | Enhancement opportunity, new feature available |

### Interactive checkpoint

**If `--fix` flag is set:** Present findings table, then ask user which items to fix. Do NOT proceed without their response.

**If report-only (no `--fix`):** Present findings table and summary. Note which items could be auto-fixed.

> "Which findings would you like me to fix? Reply with numbers, 'all', or 'skip'."

---

## Phase 5: Fix (only with `--fix` flag)

For each user-approved fix:

1. Make the edit. Done when the target file carries the change and nothing else in it moved.
2. Validate with `jq . <file> >/dev/null` after each edit. Done when jq exits 0; on a parse error,
   revert that edit before touching the next one.
3. Report what changed, as the file, the key, and the before and after values. Done when every
   applied fix has a line in the report.

After all fixes:

- Re-run the engine and present the before/after `summary` (findings by severity, rule counts,
  server counts)
- Verify all config files are still valid JSON

### Fixes the skill can apply

Auto-fixable (add `$schema`, **move** deny rules from local to project, plugin orphan-removal +
new-as-`false` via `scripts/fix-plugin-drift.sh --yes`) vs judgment-required (**adding** a baseline deny
rule, new settings from docs, permission restructure, MCP config, orphan-`true` removal, heuristic
rename), with the full matrix in [context/procedures.md](context/procedures.md) "Phase 5, fixes the skill can
apply". Adding and moving a deny rule are graded apart on purpose: moving one is #8961 placement, while
adding one has to be checked against hook coverage that may already hold and against an ask-gate the
addition would suppress.

---

## Required permission patterns

Category B (Phase 2) checks that the project's `.claude/settings.json` contains a security baseline of
deny/ask patterns: secret-file Read denies, destructive-git Bash denies, and a `git push` ask-gate. The
concrete list is in [reference/required-permissions.md](reference/required-permissions.md), which the
engine reads directly, so the list is never transcribed anywhere else. Projects with a stricter
posture declare their additional required patterns in their own rules files. When the consuming repo
documents such a list, include it in the Category B check.

A hook plugin can declare which baseline patterns its guards block in `hooks/coverage.json`. The
engine takes narrowing 3 from that manifest mechanically: the pattern drops to `info` with the plugin,
hook, and opt-out levers named, and only while the hook is live (no suppression lever set, plugin
resolved). Without a manifest the narrowing stays the model's reading of the guard's source.

Report the secret-file Read denies with their scope, not as protection: a `Read(...)` deny covers the
built-in file tools and the Bash file commands Claude Code recognizes, but not a subprocess that opens
the path itself. "Scope of a Read deny" in
[reference/required-permissions.md](reference/required-permissions.md) carries the covered /
not-covered split, the ranked remedies, and the platform limit. Carry it into the finding rather than
implying the file is unreachable.

CC settings schema, MCP server shape, hook event names, and permission glob syntax are upstream
invariants resolved against their own official pages when a check needs them, rather than asserted
as fixed patterns here.

## Next

- A finding is a permission grant that auto mode drops or a hardcoded path:
  `/claude-config:audit-permission-grants`.
- The configuration is correct and the question is now what automation is missing:
  `/claude-config:audit-automation-gaps`.
- Several audit skills need one reconciled, resumable pass: `/claude-config:audit-pass`.

## Post-Audit

### Consumer workaround inventory

When a settings-affecting upstream issue drives a project-specific workaround (or one becomes
obsolete), record that in the consuming repo's own conventions/rules files. The plugin's bundled
[known-issues.md](reference/known-issues.md) tracks only broadly-applicable upstream issues and is
refreshed via plugin updates, not per-consumer edits.

### Suggest frequency

Based on findings count:

- 0 findings: "Config is clean. Recheck after next Claude Code major update."
- 1-3 findings: "Minor drift. Monthly recheck recommended."
- 4+ findings: "Significant drift detected. Consider running after every CC update."
