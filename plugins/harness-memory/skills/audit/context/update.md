# Update Workflow

Refresh criteria and official-guidance files with current information from official Claude Code
documentation.

## Why this exists

Official Claude Code guidance evolves: new features ship, recommendations change, line-count targets
shift. Criteria in `reference/criteria.md` should reflect current official docs, not stale snapshots.
This workflow re-researches and updates the data files.

## Step 1: Research current official guidance

Research current official Claude Code CLAUDE.md best practices, memory management, rules files, and
auto-memory guidance. The primary sources are
[code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory) and
[code.claude.com/docs/en/best-practices](https://code.claude.com/docs/en/best-practices). Read both
pages through the docs lookup procedure, `<skill-dir>/../../reference/docs-lookup-procedure.md`:
read it before the first fetch and follow it, with `<scripts>` = `<skill-dir>/../../scripts` and
`<session>` = this session's id. Fetch with
`<skill-dir>/../../scripts/fetch-docs.sh --cache --max-age 0` and report each page's age.
Step 2 compares decisions against these pages, so read them raw (the procedure's verification
read, step 6). A research skill, if the environment has one, may still be used for anything
beyond those two pages.

Research must cover:

1. **Size/line-count guidance**: has the 200-line target changed?
2. **Include/exclude table**: any new items added?
3. **New memory mechanisms**: any new file types, loading behaviors, `@import` changes?
4. **Rules file changes**: path-scoping behavior, new frontmatter fields?
5. **Auto-memory changes**: has the 200-line/25KB limit changed? New features?
6. **Skills vs CLAUDE.md**: any new guidance on content placement?
7. **HTML comment behavior**: any changes to stripping behavior?

## Step 2: Diff against current guidance

Read [../reference/official-guidance.md](../reference/official-guidance.md) and compare against
research findings. Each section there holds the audit's decision and a pointer to a docs section,
never the docs' text, so compare each decision against the section its pointer names:

1. Identify changed guidance (a decision the pointed-at section no longer supports, or an
   anchor that moved)
2. Identify new guidance (topics not covered)
3. Identify removed/deprecated guidance

Present the diff to the user before making changes.

## Step 3: Update reference files

**Plugin-form caveat:** the bundled reference files live in the plugin's read-only install cache,
so durable updates land through a plugin release, not a local edit. Present the Step 2 diff as findings
the user can act on: apply criteria adjustments for THIS audit run in-conversation, and surface the
diff as a contribution/issue against the plugin's repository so the shipped criteria catch up.

With that framing, the content updates are:

1. `reference/official-guidance.md`: new or changed decisions in our words, pointers, as-of dates
   and recheck triggers. Never copy the page's text into the file, quoted or paraphrased.
2. `reference/criteria.md`: check thresholds or severity levels needing adjustment, version number,
   "Last updated" date

## Step 4: Ecosystem relevance check

Beyond criteria files, check if the instruction/memory ecosystem itself needs attention:

1. **New CC features to adopt**: e.g., `claudeMdExcludes`, `@import`, `InstructionsLoaded` hook
2. **Rules that became redundant**: a hook or analyzer now covers a rule?
3. **Memory entries that reference deprecated features**: CC features removed or renamed
4. **New official patterns**: any new recommended structures for CLAUDE.md or rules?

Present findings as actionable suggestions, not automatic changes.

## Step 5: Report

Output a summary of what changed:

- Guidance records: N updated, N added, N removed
- Ecosystem suggestions: N items
- Next action: suggest re-running the audit with updated criteria
