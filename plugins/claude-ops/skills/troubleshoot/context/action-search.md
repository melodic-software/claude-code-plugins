# Action: `search`

**Usage:** `/troubleshoot search <feature-name> [--repo <repo>] [--status] [--all]`
**Also:** `/troubleshoot <feature-name>` (search is the default when args look like a feature name)

## Flags

- **`--repo <repo>`**: search specific repo instead of `anthropics/claude-code`
- **`--status`**: also check https://status.claude.com/ for outages/degradation
- **`--all`**: search across all Anthropic repos (`org:anthropics`)

## Process

**Step 1: Search GitHub Issues** using `gh` CLI (authenticated via `GH_TOKEN` — never use global `gh auth`):

```bash
# Open issues
gh search issues "<feature-name>" --repo anthropics/claude-code --state open --sort updated --order desc --limit 20 --json number,title,state,url,labels,updatedAt,createdAt

# Recently closed (may be fixed)
gh search issues "<feature-name>" --repo anthropics/claude-code --state closed --sort updated --order desc --limit 10 --json number,title,state,url,labels,updatedAt,createdAt
```

**Step 2: Triage** — read top 5-10 most relevant issues via `gh issue view` and categorize:

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

**Step 4: Cross-reference with registry and local docs** — check if issue is already tracked in `registry.json`, or documented in the consumer project's Claude Code quirks/workarounds docs (when present).

**Step 5: Update registry** — add newly discovered relevant issues to `registry.json` with full metadata.

## Output format

Present Bug Report table (blocking, degraded, recently fixed, local doc status), recommendation (SAFE / CAUTION / DO NOT USE), and suggested actions. See `context/output-templates.md`.
