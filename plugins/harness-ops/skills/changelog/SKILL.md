---
description: "Ingest Claude Code changelog entries and integrate them into the current repo. Fetch (read-only display), diff (impact analysis over a release range, no edits), status (read marker, default range, replay cap), and apply (executes the decisions in scope one PR per owner plugin and hands larger ones off as work items, explicit user intent only). Use when: 'new cc version', 'what changed in claude code', 'apply changelog', a new CC release is mentioned, or the user pastes changelog text."
argument-hint: "<fetch|diff|status|apply> [vA..vB|vX|text]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Ingest a Claude Code release changelog and integrate its changes into the repo
---

**Arguments.** `<fetch|diff|status|apply> [vA..vB|vX|text]`. Full form: <action> [vA..vB|vX|text]. Actions: fetch (default on passive mention), diff, status, apply (explicit only)

## Pre-computed context

- Read marker (no fetch): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/changelog/scripts/changelog-status.sh" --no-fetch 2>/dev/null | head -4 || echo "(status script unavailable)"`

## Variables

Arguments: `$ARGUMENTS`

## Scope

Ingests Claude Code changelog entries and hands their decisions to the repo's stage skills. Covers the arc: read upstream changes → orient on repo impact → research new features → scope with the user → run what fits the session through the marketplace stage skills, one PR per owner plugin → file the rest as work items → native drift. `diff` reports decisions about components, not a list of items.

Distinct from:

- `/harness-ops:known-issues`. Tracks CC bugs/workarounds. This skill integrates CC feature changes into repo config/docs
- Any release-triage automation the consumer runs (issue filing per release). This skill decides, holistically across a release, what changes in the repo, and hands each decision to the skill that plans, implements or verifies it; it re-implements none of them

## Input modes and range

Three ways to provide changelog content (priority order):

1. **User pastes text**. Skill parses inline changelog from conversation context; the releases the pasted text names are the range, so the cap and the version check apply to them and not to the repository's default feed
2. **Explicit range or version**. `/harness-ops:changelog diff v2.1.257..v2.1.263` covers both ends inclusive; `apply v2.1.263` covers that one release
3. **Default range**. `/harness-ops:changelog diff` (no range) runs from the read marker to the newest published release

The read marker, the default range, and the replay cap are defined in
[context/read-actions.md](context/read-actions.md) and computed by
`scripts/changelog-status.sh`; every action starts by running it.

## Version awareness

On every `apply` or `diff` invocation, compare the newest release in the range against the active terminal's CC version. The status script reports both as `latest` and `installed` and emits a `warn` line when the installed version is older:

- If the newest release in the range > installed version: **warn user**. "You're applying v2.1.263 changes but running v2.1.260. Update CC first (`claude update`) or changes may reference features not yet available in your session."
- If the newest release in the range = installed version: proceed normally
- If the newest release in the range < installed version: fine. Catching up on older releases

## Read marker and replay cap

One line in the repository's upstream ledger for Claude Code releases (default
`docs/upstream/claude-code.md`, override `HARNESS_OPS_CHANGELOG_LEDGER`) records the newest release
the repository has been read against. `status` reads that line; with no ledger it falls back to the
highest version named in a Conventional Commits SUBJECT of the form
`chore(<scope>): address Claude Code v<A>..<B> changelog`, and it never reads commit bodies, because
a body's "verified against Claude Code v<X>" is a doc's recency stamp, not an apply.

A range wider than ten releases or 300 core items exceeds the replay cap. `diff` and `apply` then
stop and recommend a docs-conformance recheck of the components against the current docs, followed
by a marker set at the newest published release: the docs carry the cumulative state, and replaying
items past the cap costs more than it returns.

## Action Router

Parse `$ARGUMENTS` to extract the action (first token) and remaining arguments.

| Action | Description | Detail |
|--------|-------------|--------|
| `apply` | Hand-off: ingest → explore → research → scope gate → stage skills per owner-plugin PR, larger decisions filed as issues → native drift. Consumes the `diff` working set | See "Action: apply" below |
| `fetch` | Fetch + display changelog for a version or range. Read-only | See "Action: fetch" below |
| `diff` | Resolve the range, apply the cap, emit decision rows by owner surface plus a docs-lag section. Read-only | See "Action: diff" below |
| `status` | The read marker and its source, installed vs newest release, the default range, the cap verdict | See "Action: status" below |
| `help` | Show action table | *(inline)* |

**Routing (model-invocable):**

- Empty args or passive CC version mention → **`fetch`** or **`diff`** (read-only). Never **`apply`**.
- Version-only token (`v2.1.152`) or range-only token (`v2.1.150..v2.1.152`) without explicit apply intent → **`fetch`** for that version or range.
- **`apply`** only when user explicitly requests integration (`apply`, `apply changelog`, `/harness-ops:changelog apply`, or unambiguous implement-this-release intent).

If action is unknown, show action table.

## Action: apply. User intent gate

**`apply` mutates the repo.** Run only on explicit user intent per routing above. When the model
detects a new CC release in conversation, default to `fetch` or `diff` and offer `apply`. Do not
auto-start the hand-off.

`apply` plans, edits and verifies nothing itself. It reads the release, asks the user which decisions
are in scope, and hands each one to the marketplace skill that owns that stage, as Phases 3 and 4 set out.

### Phase 0. Ingest

Resolve the range, check the cap, and check version alignment:

1. **Resolve the range** (first match wins):
   - Changelog text already in conversation → the releases its `<Update label>` blocks or version headings name ARE the range; pass them as `--range <lowest>..<highest>` so the cap is judged on the pasted releases and never on the repository's default feed. Pasted text with no version at all skips the cap
   - A range or version was given → `--range` as given
   - Otherwise → no `--range`; the default range from the read marker applies
2. **Run the status script** with that `--range`. If `cap` reads `exceeded`, stop and relay the `recommend` line; the hand-off does not run past the cap. Relay any `warn` line per "Version awareness" above
3. **Reuse the working set** when `diff` saved one for this range and it passes the checks under "Persistence" in [context/decisions.md](context/decisions.md): `apply` consumes it, resolves no content, and re-fetches only what a recheck trigger names. Otherwise continue
4. **Resolve content**: pasted text is parsed as-is; otherwise slice the releases the `releases` line names out of a local copy of the changelog per the fetch route in [context/read-actions.md](context/read-actions.md)
5. **Parse** into structured items. Each item gets: a stable id (`2.1.257-001`), summary, category (feature / fix / UI / internal), affected surface (if identifiable). Ids and the working-set directory are defined in [context/decisions.md](context/decisions.md)

### Phase 1. Explore

Orient on repo impact for EACH changelog item. Run `bash "${CLAUDE_SKILL_DIR}/scripts/discover-surfaces.sh"` first: its output is the surface list, and `context/repo-surfaces.md` gives per-class examples and scoped grep patterns:

1. Grep/Glob each feature name, setting name, hook event, CLI flag across ALL surface classes the script printed
2. Classify each item per `context/classification-rubric.md` into one action lens per owner surface it touches: **correct**, **replace**, **adopt**, **note**, or **skip**
3. Group by owner surface and write each correct, replace and adopt row with its required sentence. A skip item leaves no row

Output: decision rows grouped by owner surface, per [context/decisions.md](context/decisions.md). The
work fans out by release cluster with no Workflow script; see "Fan-out shape" there.

### Phase 2. Research

For rows needing enrichment (correct rows with behavioral changes, adopt rows with unclear scope):

1. Spawn **parallel research subagents**. One per feature cluster, each receiving the explorers' questions (use a Claude Code documentation-focused agent type when available)
2. Instruct each subagent to ground every claim in the page itself (a docs page through `bash "${CLAUDE_PLUGIN_ROOT}/scripts/fetch-docs.sh" --cache --out <dir> <slug>`, a changelog entry or GitHub issue by `curl`) and to return citations with each claim. Treat any uncited subagent claim as unverified and re-verify it against official docs before acting on it. A local verifier then checks the repo-side facts

3. Research targets per item type:
   - New frontmatter field → exact syntax, interaction with existing fields, docs gap
   - New hook event → schema, sync/async, input/output shape
   - New CLI flag → syntax, settings.json equivalent (or lack thereof), valid values
   - Behavioral change → before/after, migration path, breaking implications
   - Bug fix → what was broken, what surfaces affected, historical data impact

4. Synthesize research into enriched rows

### Phase 3. Scope gate

Present the decision rows to the user via `AskUserQuestion` or structured markdown:

```markdown
| # | Owner surface | Lens | Items | Required sentence | Action needed |
|---|---------------|------|-------|-------------------|---------------|
| 1 | <component> | correct | <ids> | <false vs true> | <specific update> |
| 2 | <component> | adopt | <ids> | <problem solved> | <adopt, decline, or defer pending probe> |
```

The user picks which rows are in scope: "all rows", "just correct", or specific rows by number. A
row left out is reported at the end and recorded only when the user declines it, with its reopen
condition in the ledger's Declined table.

Then sort each in-scope row by whether it fits this session. A row **fits** when its edits stay in
its owner plugin and one session can plan, make and verify them. A row is **too large** when it
redesigns a component, changes behavior across several plugins, or needs work this session cannot
finish and verify. Show the sort with the rows and let the user move a row across.

### Phase 4. Hand off

1. **Rows that fit**: work them in this session's branch, one branch and PR per owner plugin. Use
   `/planning:plan` for the edit plan (if the planning plugin is installed), `/implementation:implement`
   for the edits (if the implementation plugin is installed) and `/verification:confirm` for the
   check (if the verification plugin is installed). A stage whose plugin is missing is not done by
   hand here: report the rows that needed it as not executed, naming the missing plugin. A
   `replace` row is never edited: nominate it into `/harness-ops:audit-native-overlap`
2. **Rows too large**: file one issue per row through `/work-items:track` (if the work-items plugin
   is installed), carrying the owner surface, lens, required sentence, item ids and range. That
   issue is worked later in its own PR, behind an interview-style human gate before any edit. When
   `/work-items:track` is not installed, report the row and file nothing. List the rows to file and
   file them only after the user confirms that batch; a row the user does not confirm is reported, not
   filed
3. **Docs lag**: hand the docs-lag pairs to `/harness-ops:known-issues`. They are never a decision row
4. **Commit and PR shape**: one PR per owner plugin, each carrying that plugin's `CHANGELOG.md`
   entry. The upstream ledger update is the last PR and references the others. Every commit subject
   reads `chore(<plugin>): address Claude Code v<A>..<B> changelog`, the ledger's taking the
   ledger owner's scope. The ledger PR moves the read marker only once every row in the range is
   applied in a merged PR, nominated, recorded as declined or deferred, or filed, and stops below the first
   release that still has a row outside those states, so no unfinished row drops out of the next
   default range. `status` reports it from the ledger and, until the ledger exists, from that subject

### Phase 5. Native-surface drift

Re-read what Claude Code ships and file what moved. Run the inventory self-check, a full
`--binary-only --docs` extraction, and overlap `detect` and `self-check`, then
`scripts/native_drift.py` to diff against the previous run's summary and evaluate the overlap
store's recheck triggers. Report surface changes (added, removed, renamed, reclassified),
invocability and marker changes, docs cross-check changes, and new overlap candidates. File one
work item per new candidate, fired trigger, and degraded or broken self-check through
`/work-items:track`, deduped by a `native-drift:<kind>:<surface>:<component>` key; a self-check
degraded only by a CLI version past the validated build proposes revalidation instead. A repository
with no overlap store is report-only: report, file nothing, keep the baseline. Commands,
the summary's location, items, dedupe and approval: [context/native-drift.md](context/native-drift.md).
Its commands write this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`; put that
path in place of the placeholder before running one.

When the harness-config plugin is installed, also run its effort-pin drift check directly, with
that plugin's install directory in place of the placeholder:

```bash
bash <harness-config plugin root>/skills/audit/scripts/check-effort-pins.sh
```

Report its lines with the native-drift report. Exit 1 means model-config's effort tables or
per-model defaults moved, or a pin names a level the page does not list: each flagged pin waits on
a person to re-decide it and rebaseline, as the `/harness-config:audit` `effort-pins` scope
documents. Exit 3 means the page was unread or reshaped, so the check made no claim; say so.
Without the harness-config plugin, report that the effort-pin check was not run.

End the run with a report that leads with what waits on the user (rows left out of scope, rows
filed or reported unfiled, stages skipped for a missing plugin), then the PRs opened and what each
changed, what `/verification:confirm` showed, the docs-lag pairs handed off, and the Phase 5 drift
report with the items filed or skipped.

---

## Actions: fetch, diff, status (read-only)

The three read-only actions stop short of any edit. **Full steps in [context/read-actions.md](context/read-actions.md)**.
Its fetch command writes this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`; put
that path in place of the placeholder before running it.

- **`fetch`**. Read the raw changelog by the upstream-drift fetch route (the plugin's `fetch-docs.sh` writes the `.md` to a file; slice the release blocks locally) and display a version, a range, or the newest release. No edits
- **`diff`**. Run the status script; stop at an exceeded cap with its recommendation; otherwise Phase 0 (ingest) + Phase 1 (explore) + Phase 2 (research) over the releases in range, stopping before the scope gate. Emits decision rows grouped by owner surface, each with its lens and required sentence, plus a docs-lag section, and saves its working set for `apply`. Answers "is this range worth an `apply`?"
- **`status`**. Run the status script and relay: the read marker and its source (ledger line or commit subject, never a commit body), installed vs newest release, the default range, and the cap verdict with its recommendation

---

## Next

- Candidates and fired triggers filed by Phase 5: `/harness-ops:audit-native-overlap`.
- Items filed as raw intake, and rows filed by Phase 4: `/work-items:triage`.
- A revalidation item: `/harness-ops:inventory`.

## Reference index. Load on demand

| File | Load when |
|---|---|
| `context/read-actions.md` | Running `fetch`, `diff`, or `status`; the read marker, range, cap, and fetch route are defined there. |
| `scripts/changelog-status.sh` | Every action's first step; `--help` lists its output lines and flags. Covered by `scripts/changelog-status.test.sh`. |
| `context/decisions.md` | Writing or reading decision rows, choosing where a decision is recorded (plugin CHANGELOG, audit-native-overlap nomination, ledger, filed issue), fanning out, or saving and reusing the working set. |
| `context/repo-surfaces.md` | Phase 1 explore, after running `scripts/discover-surfaces.sh`: per-class examples of what an item changes, and scoped grep patterns. |
| `context/classification-rubric.md` | Assigning a lens (correct, replace, adopt, note, skip) to an item, and defending a skip. |
| `context/native-drift.md` | Running `apply` Phase 5: the extraction commands, the previous-run summary, the drift report, and filing its items. |
| `scripts/native_drift.py` | Phase 5's summary, diff and trigger evaluation. Covered by `scripts/test_native_drift.py`. |
