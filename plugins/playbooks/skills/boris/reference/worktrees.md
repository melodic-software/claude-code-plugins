# Worktrees (Section 28)

Built-in git worktree support — Part 4 (Feb 20, 2026).

---

## 28. Built-in Git Worktree Support

### Use `claude --worktree` for Isolation

Claude Code has built-in git worktree support. Each agent gets its own worktree, works independently, doesn't interfere with other sessions.

```bash
# Start Claude in its own worktree
claude --worktree my_worktree

# Optionally launch in its own Tmux session too
claude --worktree my_worktree --tmux
```

**Desktop app:** Head to the Code tab in the Claude Desktop app and check the **worktree** checkbox.

### Subagents Support Worktrees

Subagents can use worktree isolation for more parallel work. Especially powerful for large batched changes and code migrations. Available in CLI, Desktop, IDE extensions, web, mobile app.

**Example prompt:** "Migrate all sync io to async. Batch up the changes, and launch 10 parallel agents with worktree isolation. Make sure each agent tests its changes end to end, then have it put up a PR."

### Custom Agents with Worktree Isolation

Make subagents always run in their own worktree — add `isolation: worktree` to agent frontmatter:

```yaml
# .claude/agents/worktree-worker.md
---
name: worktree-worker
model: haiku
isolation: worktree
---
```

### Non-Git Source Control

Mercurial, Perforce, SVN users define `WorktreeCreate` and `WorktreeRemove` hooks in `settings.json` to get isolation without Git.
