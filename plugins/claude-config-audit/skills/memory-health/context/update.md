# Update Workflow

Refresh criteria and official-guidance files with current information from official Claude Code
documentation.

## Why this exists

Official Claude Code guidance evolves — new features ship, recommendations change, line-count targets
shift. Criteria in `reference/criteria.md` should reflect current official docs, not stale snapshots.
This workflow re-researches and updates the data files.

## Step 1: Research current official guidance

Research current official Claude Code CLAUDE.md best practices, memory management, rules files, and
auto-memory guidance — primary sources
[code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory) and
[code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices) (use the
consuming environment's research skill if it has one; otherwise WebFetch those pages directly).

Research must cover:

1. **Size/line-count guidance** — has the 200-line target changed?
2. **Include/exclude table** — any new items added?
3. **New memory mechanisms** — any new file types, loading behaviors, `@import` changes?
4. **Rules file changes** — path-scoping behavior, new frontmatter fields?
5. **Auto-memory changes** — has the 200-line/25KB limit changed? New features?
6. **Skills vs CLAUDE.md** — any new guidance on content placement?
7. **HTML comment behavior** — any changes to stripping behavior?

## Step 2: Diff against current guidance

Read [../reference/official-guidance.md](../reference/official-guidance.md) and compare against
research findings:

1. Identify changed guidance (quotes no longer matching)
2. Identify new guidance (topics not covered)
3. Identify removed/deprecated guidance

Present the diff to the user before making changes.

## Step 3: Update reference files

**Plugin-form caveat:** the bundled reference files live in the plugin's read-only install cache —
durable updates land through a plugin release, not a local edit. Present the Step 2 diff as findings
the user can act on: apply criteria adjustments for THIS audit run in-conversation, and surface the
diff as a contribution/issue against the plugin's repository so the shipped criteria catch up.

With that framing, the content updates are:

1. `reference/official-guidance.md` — new/changed quotes, dates, source URLs
2. `reference/criteria.md` — check thresholds or severity levels needing adjustment, version number,
   "Last updated" date

## Step 4: Ecosystem relevance check

Beyond criteria files, check if the instruction/memory ecosystem itself needs attention:

1. **New CC features to adopt** — e.g., `claudeMdExcludes`, `@import`, `InstructionsLoaded` hook
2. **Rules that became redundant** — a hook or analyzer now covers a rule?
3. **Memory entries that reference deprecated features** — CC features removed or renamed
4. **New official patterns** — any new recommended structures for CLAUDE.md or rules?

Present findings as actionable suggestions, not automatic changes.

## Step 5: Report

Output a summary of what changed:

- Guidance quotes: N updated, N added, N removed
- Ecosystem suggestions: N items
- Next action: suggest re-running the audit with updated criteria
