---
description: "Ingest Claude Code changelog entries and integrate them into the current repo. Fetch (read-only display), diff (impact analysis over a release range, no edits), status (read marker, default range, replay cap), and apply (component decisions handed to the session, explicit user intent only). Use when: 'new cc version', 'what changed in claude code', 'apply changelog', a new CC release is mentioned, or the user pastes changelog text."
argument-hint: "<action> [vA..vB|vX|text]. Actions: fetch (default on passive mention), diff, status, apply (explicit only)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Ingest a Claude Code release changelog and integrate its changes into the repo
---

## Pre-computed context

- Read marker (no fetch): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/changelog/scripts/changelog-status.sh" --no-fetch 2>/dev/null | head -4 || echo "(status script unavailable)"`

## Variables

Arguments: `$ARGUMENTS`

## Scope

Ingests Claude Code changelog entries and integrates them into the repo. Covers the full arc: read upstream changes → orient on repo impact → research new features → triage with user → plan edits → implement → verify → close matching issues.

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
| `apply` | Ingest → explore → research → interview → hand the decision list to the session. Does not plan, implement, verify, or close issues | See "Action: apply" below |
| `fetch` | Fetch + display changelog for a version or range. Read-only | See "Action: fetch" below |
| `diff` | Resolve the range, apply the cap, emit component decisions. Read-only | See "Action: diff" below |
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

The pipeline runs ingest → explore → research → interview → handoff as the phases below.

### Phase 0. Ingest

Resolve the range, check the cap, and check version alignment:

1. **Resolve the range** (first match wins):
   - Changelog text already in conversation → the releases its `<Update label>` blocks or version headings name ARE the range; pass them as `--range <lowest>..<highest>` so the cap is judged on the pasted releases and never on the repository's default feed. Pasted text with no version at all skips the cap
   - A range or version was given → `--range` as given
   - Otherwise → no `--range`; the default range from the read marker applies
2. **Run the status script** with that `--range`. If `cap` reads `exceeded`, stop and relay the `recommend` line; the pipeline does not run past the cap. Relay any `warn` line per "Version awareness" above
3. **Resolve content**: pasted text is parsed as-is; otherwise slice the releases the `releases` line names out of a local copy of the changelog per the fetch route in [context/read-actions.md](context/read-actions.md)
4. **Parse** into structured items. Each item gets: summary, category (feature / fix / UI / internal), affected surface (if identifiable)

### Phase 1. Explore

Run `scripts/discover-surfaces.sh` on the repo (marketplace or consumer) and orient on those surfaces. Classify with the five lenses in `context/classification-rubric.md`: `correct`, `replace`, `adopt`, `note`, `skip`. Group items that share one component effect into one decision. `skip` leaves no row.

Write the decisions as TSV and render them with `scripts/changelog-decisions.sh`. Each kept row carries its lens and the sentence that lens requires. A `replace` row is `nominated` until a human verdict. When the changelog and a docs page disagree, the `correct` sentence cites the changelog for behavior and the pair is listed under Docs lag.

### Phase 2. Research

For decisions needing enrichment (a `correct` row for a behavioral change, an `adopt` or `note` row with unclear scope):

1. Spawn **parallel research subagents**. One per feature cluster (use a Claude Code documentation-focused agent type when available)
2. Instruct each subagent to ground every claim in a primary source fetched during the task (official docs URL, changelog entry, or GitHub issue) and to return citations with each claim. Treat any uncited subagent claim as unverified and re-verify it against official docs before acting on it.

3. Research targets per item type:
   - New frontmatter field → exact syntax, interaction with existing fields, docs gap
   - New hook event → schema, sync/async, input/output shape
   - New CLI flag → syntax, settings.json equivalent (or lack thereof), valid values
   - Behavioral change → before/after, migration path, breaking implications
   - Bug fix → what was broken, what surfaces affected, historical data impact

4. Synthesize research into enriched analysis per item

### Phase 3. Interview

Present the decision list rendered by `scripts/changelog-decisions.sh` via `AskUserQuestion` or
structured markdown. User picks scope: every row, one lens, or specific rows by number.

Lock brief: confirmed scope becomes implementation contract.

### Phase 4. Handoff

`apply` does not plan, implement, verify, or close issues. It hands the rendered decisions to the
session:

1. A decision that fits this session's scope is edited in this session's PR, one owner plugin per PR, subject `chore(<plugin>): address Claude Code v<range> changelog`.
2. A decision too large for the session is filed through the work-items seam when that seam is installed, and printed for the user when it is not.
3. A `replace` row stays `nominated`. This skill does not write the native-surfaces verdict.
4. The ledger update is the last PR in the set. Its subject is the same form, so `status` can read it.

The marketplace's stage skills own planning, implementation, and verification. This skill stops at the decision list.

End the run with a report that leads with what waits on the user (a decision too large for this
session, a `replace` still nominated), then the decision list.

---

## Actions: fetch, diff, status (read-only)

The three read-only actions stop short of any edit. **Full steps in [context/read-actions.md](context/read-actions.md)**:

- **`fetch`**. Read the raw changelog by the upstream-drift fetch route (`curl` the `.md`, slice the release blocks locally) and display a version, a range, or the newest release. No edits
- **`diff`**. Run the status script; stop at an exceeded cap with its recommendation; otherwise Phase 0 (ingest) + Phase 1 (explore) + Phase 2 (research) over the releases in range, stopping before the interview. Emit the decision ledger from `scripts/changelog-decisions.sh`, not an item table. Answers "which component decisions does this range force?"
- **`status`**. Run the status script and relay: the read marker and its source (ledger line or commit subject, never a commit body), installed vs newest release, the default range, and the cap verdict with its recommendation

---

## Reference index. Load on demand

| File | Load when |
|---|---|
| `context/read-actions.md` | Running `fetch`, `diff`, or `status`; the read marker, range, cap, and fetch route are defined there. |
| `scripts/changelog-status.sh` | Every action's first step; `--help` lists its output lines and flags. Covered by `scripts/changelog-status.test.sh`. |
| `context/repo-surfaces.md` | Phase 1 explore, enumerating which surfaces a given changelog item can touch. |
| `context/classification-rubric.md` | Choosing a lens (`correct`, `replace`, `adopt`, `note`, `skip`) for a component effect. |
| `scripts/changelog-decisions.sh` | Rendering the decision TSV. Drops `skip`, rejects a kept row with no sentence, prints `nominated` for an open `replace`. |
| `scripts/discover-surfaces.sh` | Listing marketplace or consumer surfaces before explore. |
