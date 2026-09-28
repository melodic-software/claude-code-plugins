# Action: `search`

**Usage:** `/claude-ops:known-issues search <feature-name> [--repo <repo>] [--status] [--all]`
**Also:** `/claude-ops:known-issues <feature-name>` (search is the default when args look like a feature name)

## Flags

- **`--repo <repo>`**: search specific repo instead of `anthropics/claude-code`
- **`--status`**: also check https://status.claude.com/ for outages/degradation
- **`--all`**: search across all Anthropic repos (`org:anthropics`)

## Process

**Step 1: Search GitHub Issues** using the `gh` CLI, with whatever authentication the consumer's environment already provides:

```bash
# Open issues
gh search issues "<feature-name>" --repo anthropics/claude-code --state open --sort updated --order desc --limit 20 --json number,title,state,url,labels,updatedAt,createdAt

# Recently closed (may be fixed)
gh search issues "<feature-name>" --repo anthropics/claude-code --state closed --sort updated --order desc --limit 10 --json number,title,state,url,labels,updatedAt,createdAt
```

**Step 2: Triage.** Read top 5-10 most relevant issues via `gh issue view` and categorize:

| Category | Meaning | Action |
| --- | --- | --- |
| **blocking** | Feature unusable or dangerous | Do not use. Find alternative. |
| **degraded** | Partial failure, workaround exists | Use with workaround. |
| **cosmetic** | UX issue, not functional | Note for awareness. |
| **fixed** | Closed/fixed recently | Verify fix in your CC version. |
| **feature-request** | Not a bug | Note if relevant. |

**Step 3: Check status page** (if `--status` flag):

```bash
curl -s https://status.claude.com/ | head -200
```

**Step 4: Cross-reference with registry and local docs.** Check if issue is already tracked in `registry.json`, or documented in the consumer project's Claude Code quirks/workarounds docs (when present).

**Step 5: Update registry.** Add newly discovered relevant issues to `registry.json` with full metadata.

## Output format

Present Bug Report table (blocking, degraded, recently fixed, local doc status), recommendation (SAFE / CAUTION / DO NOT USE), and suggested actions. The recommendation carries a `Basis:`: `verified` with the issue URLs, status-page read, or `claude --version` output it rests on, or `judgment` when no issue settles it and the feature is not load-bearing. When the choice is consequential (cross-repo, shared infrastructure, irreversible, or security) and no issue settles it, withhold the verdict: report it as an open question naming the evidence that would settle it. Contract: [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../../context/recommendation-basis.md); full convention: [recommendation-basis](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/recommendation-basis/README.md#basis-label). See `context/output-templates.md`.
