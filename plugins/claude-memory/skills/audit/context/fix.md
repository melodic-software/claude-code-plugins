# Fix Workflow

Apply fixes for audit findings. Requires a prior audit — reads findings from **the path SKILL.md
resolves in "Report location"**, `audit/<state-key>/last-audit.md` under the plugin data directory.
Derive the key there; do not restate a path here.

## Prerequisites

Read the last-audit report **from this project's derived path**. If it is absent, say that no audit
has been run for this project and suggest running one.

**This mode proposes edits to real instruction files, so an unattributable report is not usable
input.** Do not fall back to an unkeyed location: a machine-global `audit/last-audit.md` or a
pre-rename `health/last-audit.md` carries no project segment, so findings in it may describe a
different repository's memory layer entirely. Name such a file to the user as a leftover and run a
fresh audit instead of acting on it.

## Fix strategy

Process findings by severity: FAIL first, then WARN (only if user opts in). INFO findings are not
actionable — skip.

For each finding, present:

1. The finding and its evidence
2. The proposed fix
3. Ask for approval before applying

**Never batch-apply fixes without approval.** Each fix is a judgment call — criteria flag issues; the
user decides resolution.

## Common fix patterns

### C1 (Line Budget) fixes

Options to reduce CLAUDE.md line count:

1. **Move to rules** — language/framework-specific content → `.claude/rules/`
2. **Move to skills** — reference material, workflows → `.claude/skills/*/`
3. **Wrap in HTML comments** — human-only reference info (stripped from context)
4. **Delete** — content failing the deletion test (C2)
5. **Compress** — merge redundant sections, tighten wording

Present specific sections that are candidates for each approach.

### C2 (Deletion Test) fixes

For lines flagged as potentially removable:

1. Present the flagged lines, grouped by section
2. Explain why flagged (Claude can infer from code, standard practice, etc.)
3. Suggest: delete, move to rules/skills, or keep with justification
4. If kept, document justification in an HTML comment

### C3 (Content Placement) fixes

For content in the wrong layer:

1. Identify the correct layer
2. Draft content for the new location
3. Remove from current location
4. Verify no cross-references break

### C5 (Non-obvious Only) fixes

For flagged codebase-description content, in preference order:

1. **Delete** — a file-by-file inventory Claude can rebuild with `ls`/Glob goes first.
2. **Curate into a navigation pointer** — when the section exists to route to something
   genuinely non-obvious and load-bearing, compress it to the pointer form C5's KEEP branch
   describes: where to look, and when to look there.
3. **Restructure before pointing** — a pointer that exists because changes must be mirrored
   across distant folders can mask low cohesion; consider restructuring so the things that
   change together live together, and keep a pointer only for what remains genuinely distant.
   (Write-side doctrine for authoring the pointer itself: `docs-hygiene:write-for-agents`, if
   that plugin is installed.)

### C6 (Consistency) fixes

For contradictions:

1. Show both contradicting instructions with file paths
2. Ask which one is correct
3. Update or remove the incorrect one

### C7 (Currency) fixes

For stale references:

1. Check if referenced file was renamed (use `git log --diff-filter=R`)
2. If renamed: update the reference
3. If deleted: remove the reference or note it's planned

### M2 (Stale Memory) fixes

For stale memory entries:

1. Read the topic file
2. Verify referenced files/features still exist
3. If stale: update memory content, or suggest deletion
4. Update MEMORY.md index if topic files removed

**Inbound `[[wikilink]]` sweep on any entry deletion** — memory entries cross-link via `[[name]]`:

```bash
# Current repo's memory dir only — a `~/.claude/projects/*/memory/` glob would
# sweep every project on a multi-project machine.
MEMORY_DIR=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/resolve-memory-dir.sh")
grep -rl '\[\[<deleted-entry-name>\]\]' "$MEMORY_DIR/" 2>/dev/null
```

For each sibling carrying the link: remove the `[[...]]` reference (or convert to plain text if the
prose still reads). Don't leave a dangling link for the next audit's M2 to catch.

## After fixes

1. Re-run the audit to verify fixes resolved the findings
2. Present before/after comparison (finding count reduction)
3. If CLAUDE.md line count changed, report old → new with percentage
