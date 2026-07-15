# Action: `status`

**Usage:** `/troubleshoot` (no args) or `/troubleshoot status`

Quick health snapshot for proactive auto-invocation. Combines registry stats with a lightweight quality check.

## Process

**Step 1: Registry summary** — read `registry.json` and compute:

- Total tracked issues
- Counts by category (blocking / degraded / cosmetic / fixed / feature-request / informational)
- Count of open blocking issues (need attention)
- Stale issues (not checked in >14 days)

Use the registry manager script for efficient stats (add `--data-dir` per the SKILL.md registry-location rule when a `registry_dir` is configured):

```bash
python "${CLAUDE_PLUGIN_ROOT}/skills/troubleshoot/scripts/registry_manager.py" stats
python "${CLAUDE_PLUGIN_ROOT}/skills/troubleshoot/scripts/registry_manager.py" list --stale 14
```

**Step 2: Lightweight quality check** — fetch service health (fast):

```bash
curl -s https://status.claude.com/ | head -100
```

Report overall status only (Operational / Degraded / Outage). Skip Marginlab for the quick check — that's the `quality` action's job.

**Step 3: Stale issue flag** — if any issues haven't been checked in >14 days, recommend running `check-all`.

## Output format

```markdown
## Claude Code Health (YYYY-MM-DD)

### Registry: N tracked issues
- **Blocking**: N open | **Degraded**: N open | **Fixed**: N (awaiting follow-up)
- **Stale** (>14d): N issues need re-check

### Service Status
- **status.claude.com**: Operational / Degraded / Outage

### Recommendations
- Run `/troubleshoot check-all` to refresh stale issues
- Run `/troubleshoot quality` for full quality analysis
- Run `/troubleshoot search <feature>` before building on a CC mechanism
```
