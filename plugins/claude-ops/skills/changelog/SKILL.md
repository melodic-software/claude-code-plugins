---
name: changelog
description: "Ingest Claude Code changelog entries and integrate them into the current repo — fetch (read-only display), diff (impact analysis, no edits), status (applied versions), and apply (full integrate pipeline, explicit user intent only). Use when: 'new cc version', 'what changed in claude code', 'apply changelog', a new CC release is mentioned, or the user pastes changelog text."
argument-hint: "<action> [version|text] — actions: fetch (default on passive mention), diff, status, apply (explicit only)"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Scope

Ingests Claude Code changelog entries and integrates them into the repo. Covers the full arc: read upstream changes → orient on repo impact → research new features → triage with user → plan edits → implement → verify → close matching issues.

Distinct from:

- `/known-issues` — tracks CC bugs/workarounds. This skill integrates CC feature changes into repo config/docs
- Any release-triage automation the consumer runs (issue filing per release) — this skill IMPLEMENTS changes, holistically across a release

## Input modes

Three ways to provide changelog content (priority order):

1. **User pastes text** — skill parses inline changelog from conversation context
2. **Specific version** — `/changelog apply v2.1.152` fetches that version from `code.claude.com/docs/en/changelog`
3. **Auto-detect latest** — `/changelog apply` (no version) automatically fetches changelog, identifies latest version, and proceeds

## Version awareness

On every `apply` or `diff` invocation, check the active terminal's CC version:

```bash
claude --version 2>/dev/null
```

- If target version > installed version: **warn user** — "You're applying v2.1.152 changes but running v2.1.150. Update CC first (`claude update`) or changes may reference features not yet available in your session."
- If target version = installed version: proceed normally
- If target version < installed version: fine — catching up on older release

## Applied-version tracking

No persistent tracking file. Git history IS the tracker — commit messages cite CC versions per Conventional Commits (`chore: address Claude Code v2.1.152 changelog`). The `status` action derives applied versions via `git log --grep`. Avoids drift between tracker file and git state.

## Action Router

Parse `$ARGUMENTS` to extract the action (first token) and remaining arguments.

| Action | Description | Detail |
|--------|-------------|--------|
| `apply` | Full pipeline: ingest → explore → research → interview → plan → implement → verify → close issues | See "Action: apply" below |
| `fetch` | Fetch + display changelog for version(s). Read-only | See "Action: fetch" below |
| `diff` | Fetch + orient on repo impact. Read-only analysis table | See "Action: diff" below |
| `status` | Show applied versions, open issues, pending work | See "Action: status" below |
| `help` | Show action table | *(inline)* |

**Routing (model-invocable):**

- Empty args or passive CC version mention → **`fetch`** or **`diff`** (read-only). Never **`apply`**.
- Version-only token (`v2.1.152`) without explicit apply intent → **`fetch`** for that version.
- **`apply`** only when user explicitly requests integration (`apply`, `apply changelog`, `/changelog apply`, or unambiguous implement-this-release intent).

If action is unknown, show action table.

## Action: apply — user intent gate

**`apply` mutates the repo.** Run only on explicit user intent per routing above. When the model
detects a new CC release in conversation, default to `fetch` or `diff` and offer `apply` — do not
auto-start the pipeline.

The full pipeline runs explore → research → interview → plan → implement → verify as the phases below. If the consumer project ships its own stage skills for these, prefer them at each phase.

### Phase 0 — Ingest

Resolve changelog content and check version alignment:

1. **Check installed CC version:** `claude --version 2>/dev/null`. Compare against target version per "Version awareness" above
2. **Resolve content** (first match wins):
   - Changelog text already in conversation → parse it
   - Version arg provided (e.g., `apply v2.1.152`) → run `fetch` for that version
   - No text, no version → auto-fetch latest version from changelog URL
3. **Parse** into structured items. Each item gets: summary, category (feature / fix / UI / internal), affected surface (if identifiable)

### Phase 1 — Explore

Per `context/repo-surfaces.md`, orient on repo impact for EACH changelog item:

1. Grep/Glob each feature name, setting name, hook event, CLI flag across ALL listed surfaces
2. Classify each item per `context/classification-rubric.md`:
   - **P1 (requires update)** — repo already uses this feature/surface and changelog changes behavior or adds capability we should document
   - **P2 (worth considering)** — new capability repo does NOT currently use but SHOULD evaluate for adoption
   - **P3 (no action)** — UI/cosmetic fix, internal change, or feature irrelevant to repo
3. For P2 items: do NOT skip. Flag as "New capability — evaluate for adoption" with brief rationale

Output: structured table with item, classification, affected files, rationale.

### Phase 2 — Research

For items needing enrichment (P1 items with behavioral changes, P2 items with unclear scope):

1. Spawn **parallel research subagents** — one per feature cluster (use a Claude Code documentation-focused agent type when available)
2. Instruct each subagent to ground every claim in a primary source fetched during the task (official docs URL, changelog entry, or GitHub issue) and to return citations with each claim — treat any uncited subagent claim as unverified and re-verify it against official docs before acting on it.

3. Research targets per item type:
   - New frontmatter field → exact syntax, interaction with existing fields, docs gap
   - New hook event → schema, sync/async, input/output shape
   - New CLI flag → syntax, settings.json equivalent (or lack thereof), valid values
   - Behavioral change → before/after, migration path, breaking implications
   - Bug fix → what was broken, what surfaces affected, historical data impact

4. Synthesize research into enriched analysis per item

### Phase 3 — Interview

Present triage table to user via `AskUserQuestion` or structured markdown:

```markdown
| # | Change | Classification | Affected files | Action needed |
|---|--------|---------------|----------------|---------------|
| 1 | <summary> | P1 | <files> | <specific update> |
| 2 | <summary> | P2 | — | <evaluation + recommendation> |
| N | <summary> | P3 | — | No action |
```

User picks scope: "all P1+P2", "just P1", or specific items by number.

Lock brief: confirmed scope becomes implementation contract.

### Phase 4 — Plan

Plan concrete edits with cross-cutting awareness:

1. Group changes by file (multiple items may touch same file)
2. Identify cross-cutting dependencies (e.g., a new hook event may need updates in every surface that documents hook events — rules, hook scripts, and reference docs alike)
3. Order edits to avoid conflicts
4. For each file: specific section to edit, old text to replace, new text

### Phase 5 — Implement

Execute plan:

1. Edit files per the approved plan
2. Run the consumer repo's markdown linter on every touched `.md` file (e.g. `npx markdownlint-cli2`), when one is configured
3. If hook scripts touched: run their tests with the consumer repo's test runner
4. If settings.json touched: `jq empty .claude/settings.json`

### Phase 6 — Verify

Run the consumer repo's verification workflow (build/test/lint) on affected ecosystems. At minimum: markdown lint on all touched files.

### Phase 7 — Close issues (optional)

If user approves:

1. If the consumer repo files CC-release tracking issues, search for matching open ones using
   that repo's own convention (label, title marker, or milestone) via `gh issue list --state open --search '...'`
2. For each issue whose title matches an implemented changelog item: close with comment citing this session's work

---

## Actions: fetch, diff, status (read-only)

The three read-only actions stop short of any edit — **full steps in [context/read-actions.md](context/read-actions.md)**:

- **`fetch`** — WebFetch + display a version (or latest, or a `v.X..v.Y` range) of `code.claude.com/docs/en/changelog`. No edits
- **`diff`** — dry run of `apply`: Phase 0 (ingest) + Phase 1 (explore) + Phase 2 (research), stops before interview. Emits the triage table only. Answers "is this release worth an `apply`?"
- **`status`** — applied versions (`git log --grep`), open routine-pipeline issues (`gh issue list`), current `claude --version`, and the gap if installed > last-applied

---

## Cross-references

- `context/repo-surfaces.md` — surface categories to check per changelog item
- `context/classification-rubric.md` — P1/P2/P3 classification criteria
- `context/read-actions.md` — full steps for the read-only actions
