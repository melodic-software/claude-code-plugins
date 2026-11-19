# One session per ready item (desktop app only)

Read this file only when this session has a tool that starts another session, which the Claude
desktop app's Code tab provides. Elsewhere the per-item route in SKILL.md Step 4 applies unchanged.

**When it applies.** The container's shape is `per-item PRs` and the frontier holds two or more
ready items with no blocker between them. Never in the `integration branch → single PR` shape: it
keeps one writer on the shared branch.

**What to offer.** One session per item, all offered together for the user to start, each in its
own worktree cut from the default branch. Never start them on your own. Each brief stands alone,
because the started session knows nothing of this conversation:

- the item's title linked to its absolute URL, and the container's;
- "claim this item first with `/work-items:track start <id>`, then work it under the project's
  workflow to its own PR"; the seam claim is what stops two sessions taking the same item;
- the shape line and its discipline as Step 3 stated them.

**After the start.** This session keeps the macro view: re-run `status` when a started session
reports back, and send it follow-ups as messages rather than starting another session for the same
item.

- **Pointer**: <https://code.claude.com/docs/en/desktop#start-a-task-that-claude-suggests>

**Fallback.** No such tool, or the user keeps the work here: route the frontier to
`/work-items:work` or `/work-items:ship run` as Step 4 says.
