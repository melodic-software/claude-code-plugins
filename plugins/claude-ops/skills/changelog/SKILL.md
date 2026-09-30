---
description: "Ingest Claude Code changelog entries and integrate them into the current repo. Fetch (read-only display), diff (impact analysis over a release range, no edits), status (read marker, default range, replay cap), and apply (full integrate pipeline, explicit user intent only). Use when: 'new cc version', 'what changed in claude code', 'apply changelog', a new CC release is mentioned, or the user pastes changelog text."
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

Ingests Claude Code changelog entries and integrates them into the repo. Covers the full arc: read upstream changes → orient on repo impact → research new features → decide with user → plan edits → implement → verify → close matching issues. `diff` reports decisions about components, not a list of items.

Distinct from:

- `/claude-ops:known-issues`. Tracks CC bugs/workarounds. This skill integrates CC feature changes into repo config/docs
- Any release-triage automation the consumer runs (issue filing per release). This skill IMPLEMENTS changes, holistically across a release

## Input modes and range

Three ways to provide changelog content (priority order):

1. **User pastes text**. Skill parses inline changelog from conversation context; the releases the pasted text names are the range, so the cap and the version check apply to them and not to the repository's default feed
2. **Explicit range or version**. `/claude-ops:changelog diff v2.1.257..v2.1.263` covers both ends inclusive; `apply v2.1.263` covers that one release
3. **Default range**. `/claude-ops:changelog diff` (no range) runs from the read marker to the newest published release

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
`docs/upstream/claude-code.md`, override `CLAUDE_OPS_CHANGELOG_LEDGER`) records the newest release
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
| `apply` | Full pipeline: ingest → explore → research → interview → plan → implement → verify → native drift → close issues. Consumes the `diff` working set | See "Action: apply" below |
| `fetch` | Fetch + display changelog for a version or range. Read-only | See "Action: fetch" below |
| `diff` | Resolve the range, apply the cap, emit decision rows by owner surface plus a docs-lag section. Read-only | See "Action: diff" below |
| `status` | The read marker and its source, installed vs newest release, the default range, the cap verdict | See "Action: status" below |
| `help` | Show action table | *(inline)* |

**Routing (model-invocable):**

- Empty args or passive CC version mention → **`fetch`** or **`diff`** (read-only). Never **`apply`**.
- Version-only token (`v2.1.152`) or range-only token (`v2.1.150..v2.1.152`) without explicit apply intent → **`fetch`** for that version or range.
- **`apply`** only when user explicitly requests integration (`apply`, `apply changelog`, `/claude-ops:changelog apply`, or unambiguous implement-this-release intent).

If action is unknown, show action table.

## Action: apply. User intent gate

**`apply` mutates the repo.** Run only on explicit user intent per routing above. When the model
detects a new CC release in conversation, default to `fetch` or `diff` and offer `apply`. Do not
auto-start the pipeline.

The full pipeline runs explore → research → interview → plan → implement → verify as the phases below. If the consumer project ships its own stage skills for these, prefer them at each phase.

### Phase 0. Ingest

Resolve the range, check the cap, and check version alignment:

1. **Resolve the range** (first match wins):
   - Changelog text already in conversation → the releases its `<Update label>` blocks or version headings name ARE the range; pass them as `--range <lowest>..<highest>` so the cap is judged on the pasted releases and never on the repository's default feed. Pasted text with no version at all skips the cap
   - A range or version was given → `--range` as given
   - Otherwise → no `--range`; the default range from the read marker applies
2. **Run the status script** with that `--range`. If `cap` reads `exceeded`, stop and relay the `recommend` line; the pipeline does not run past the cap. Relay any `warn` line per "Version awareness" above
3. **Reuse the working set** when `diff` saved one for this range and it passes the checks under "Persistence" in [context/decisions.md](context/decisions.md): `apply` consumes it, resolves no content, and re-fetches only what a recheck trigger names. Otherwise continue
4. **Resolve content**: pasted text is parsed as-is; otherwise slice the releases the `releases` line names out of a local copy of the changelog per the fetch route in [context/read-actions.md](context/read-actions.md)
5. **Parse** into structured items. Each item gets: a stable id (`2.1.257-001`), summary, category (feature / fix / UI / internal), affected surface (if identifiable). Ids and the working-set directory are defined in [context/decisions.md](context/decisions.md)

### Phase 1. Explore

Per `context/repo-surfaces.md`, orient on repo impact for EACH changelog item:

1. Grep/Glob each feature name, setting name, hook event, CLI flag across ALL listed surfaces
2. Classify each item per `context/classification-rubric.md` into one action lens per owner surface it touches: **correct**, **replace**, **adopt**, **note**, or **skip**
3. Group by owner surface and write each correct, replace and adopt row with its required sentence. A skip item leaves no row

Output: decision rows grouped by owner surface, per [context/decisions.md](context/decisions.md). The
work fans out by release cluster with no Workflow script; see "Fan-out shape" there.

### Phase 2. Research

For rows needing enrichment (correct rows with behavioral changes, adopt rows with unclear scope):

1. Spawn **parallel research subagents**. One per feature cluster, each receiving the explorers' questions (use a Claude Code documentation-focused agent type when available)
2. Instruct each subagent to ground every claim by `curl` of the page (official docs URL, changelog entry, or GitHub issue) and to return citations with each claim. Treat any uncited subagent claim as unverified and re-verify it against official docs before acting on it. A local verifier then checks the repo-side facts

3. Research targets per item type:
   - New frontmatter field → exact syntax, interaction with existing fields, docs gap
   - New hook event → schema, sync/async, input/output shape
   - New CLI flag → syntax, settings.json equivalent (or lack thereof), valid values
   - Behavioral change → before/after, migration path, breaking implications
   - Bug fix → what was broken, what surfaces affected, historical data impact

4. Synthesize research into enriched rows

### Phase 3. Interview

Present the decision rows to the user via `AskUserQuestion` or structured markdown:

```markdown
| # | Owner surface | Lens | Items | Required sentence | Action needed |
|---|---------------|------|-------|-------------------|---------------|
| 1 | <component> | correct | <ids> | <false vs true> | <specific update> |
| 2 | <component> | adopt | <ids> | <problem solved> | <adopt, decline, or defer pending probe> |
```

User picks scope: "all rows", "just correct", or specific rows by number.

Lock brief: confirmed scope becomes implementation contract.

### Phase 4. Plan

Plan the concrete edits for the confirmed scope, down to the section and text each file changes. One
changelog item often touches several surfaces: a new hook event, for example, needs an update in
every surface that documents hook events, rules, hook scripts, and reference docs alike.

### Phase 5. Implement

Once the plan is approved, run Phases 5 and 6 without stopping between steps: done means every
confirmed item is edited and verification passes. Stop and ask only when a check fails for a reason
you cannot explain or an item needs a change outside the confirmed scope. Execute plan:

1. Edit files per the approved plan
2. Run the consumer repo's markdown linter on every touched `.md` file (e.g. `npx markdownlint-cli2`), when one is configured
3. If hook scripts touched: run their tests with the consumer repo's test runner
4. If settings.json touched: `jq empty .claude/settings.json`

### Phase 6. Verify

Run the consumer repo's verification workflow (build/test/lint) on affected ecosystems. At minimum: markdown lint on all touched files.

### Phase 7. Native-surface drift

Re-read what Claude Code ships and file what moved. Run the inventory self-check, a full
`--binary-only --docs` extraction, and overlap `detect` and `self-check`, then
`scripts/native_drift.py` to diff against the previous run's summary and evaluate the overlap
store's recheck triggers. Report surface changes (added, removed, renamed, reclassified),
invocability and marker changes, docs cross-check changes, and new overlap candidates. File one
work item per new candidate, fired trigger, and degraded or broken self-check through
`/work-items:track`, deduped by a `native-drift:<kind>:<surface>:<component>` key; a self-check
degraded only by a CLI version past the validated build proposes revalidation instead. Commands,
the summary's location, items, dedupe and approval: [context/native-drift.md](context/native-drift.md).
Its commands write this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`; put that
path in place of the placeholder before running one.

### Phase 8. Close issues (optional)

If user approves:

1. If the consumer repo files CC-release tracking issues, search for matching open ones using
   that repo's own convention (label, title marker, or milestone) via `gh issue list --state open --search '...'`
2. For each issue whose title matches an implemented changelog item: close with comment citing this session's work

The last commit of an `apply` moves the read marker to the top of the applied range, in a subject of
the form `chore(<scope>): address Claude Code v<A>..<B> changelog`, so `status` reports the new
marker from the ledger and, until the ledger exists, from that subject.

End the run with a report that leads with what waits on the user (the Phase 8 approval, any item
deferred or blocked), then what changed, what verification showed, and the Phase 7 drift report
with the items filed or skipped.

---

## Actions: fetch, diff, status (read-only)

The three read-only actions stop short of any edit. **Full steps in [context/read-actions.md](context/read-actions.md)**.
Its fetch command writes this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`; put
that path in place of the placeholder before running it.

- **`fetch`**. Read the raw changelog by the upstream-drift fetch route (the plugin's `fetch-docs.sh` writes the `.md` to a file; slice the release blocks locally) and display a version, a range, or the newest release. No edits
- **`diff`**. Run the status script; stop at an exceeded cap with its recommendation; otherwise Phase 0 (ingest) + Phase 1 (explore) + Phase 2 (research) over the releases in range, stopping before the interview. Emits decision rows grouped by owner surface, each with its lens and required sentence, plus a docs-lag section, and saves its working set for `apply`. Answers "is this range worth an `apply`?"
- **`status`**. Run the status script and relay: the read marker and its source (ledger line or commit subject, never a commit body), installed vs newest release, the default range, and the cap verdict with its recommendation

---

## Next

- Candidates and fired triggers filed by Phase 7: `/claude-ops:audit-native-overlap`.
- Items filed as raw intake: `/work-items:triage`.
- A revalidation item: `/claude-ops:inventory`.

## Reference index. Load on demand

| File | Load when |
|---|---|
| `context/read-actions.md` | Running `fetch`, `diff`, or `status`; the read marker, range, cap, and fetch route are defined there. |
| `scripts/changelog-status.sh` | Every action's first step; `--help` lists its output lines and flags. Covered by `scripts/changelog-status.test.sh`. |
| `context/decisions.md` | Writing or reading decision rows, choosing where a decision is recorded (plugin CHANGELOG, audit-native-overlap nomination, ledger), fanning out, or saving and reusing the working set. |
| `context/repo-surfaces.md` | Phase 1 explore, enumerating which surfaces a given changelog item can touch. |
| `context/classification-rubric.md` | Assigning a lens (correct, replace, adopt, note, skip) to an item, and defending a skip. |
| `context/native-drift.md` | Running `apply` Phase 7: the extraction commands, the previous-run summary, the drift report, and filing its items. |
| `scripts/native_drift.py` | Phase 7's summary, diff and trigger evaluation. Covered by `scripts/test_native_drift.py`. |
