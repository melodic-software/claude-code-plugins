# claude-code-changelog — read-only actions

The three read-only actions (`fetch`, `diff`, `status`). SKILL.md keeps the action-router table + the `apply` pipeline; these stop short of any edit and live here.

## Action: fetch

Read-only. Fetch and display changelog content.

**With version arg** (`/claude-code-changelog fetch v2.1.152`):

1. WebFetch `https://code.claude.com/docs/en/changelog`
2. Extract section matching version
3. Display formatted

**Without version arg** (`/claude-code-changelog fetch`):

1. WebFetch changelog URL
2. Extract most recent version section
3. Display formatted

**Multiple versions** (`/claude-code-changelog fetch v2.1.150..v2.1.152`):

1. Fetch and display all versions in range

## Action: diff

Read-only dry run of `apply`. Runs Phase 0 (ingest) + Phase 1 (explore) + Phase 2 (research) but stops before interview.

Output: the triage table showing what would need to change, with enriched research. No file edits.

Useful for: "should I bother running apply for this release?"

## Action: status

Show changelog integration status:

1. **Applied versions** — scan git log for commits mentioning "CC v2.1." or "Claude Code v2.1." or "changelog":

   ```bash
   git log --oneline --all --grep="CC v2\.1\." --grep="Claude Code v2\.1\." -20
   ```

2. **Open issues** — if the consumer repo files CC-release tracking issues, count the pending
   ones using that repo's own search convention (label, title marker, or milestone), e.g.:

   ```bash
   gh issue list --state open --search '<consumer's CC-tracking label or marker>' --json number,title --limit 50
   ```

   Skip this step when the repo has no such convention.

3. **Current CC version**:

   ```bash
   claude --version 2>/dev/null || echo "unknown"
   ```

4. **Gap analysis** — if current version > last applied version, flag the gap
