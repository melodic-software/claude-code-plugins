# codebase-health Checklist

Copy into wherever the consuming repo keeps working task notes. Tick as each phase completes.

## Phases

- [ ] Phase 0: Prime context — read the repo's conventions (`CLAUDE.md` / `AGENTS.md` / `.claude/rules/`); resolve the audit config and read its verification-sources
- [ ] Phase 1: Discover — per-file subagent fan-out over active dimensions' primary-sources (scope-gated)
- [ ] Phase 2: Validate & enrich — independent re-verification of each finding against source of truth; external research where a claim needs it
- [ ] Phase 3: Categorize & present — findings table with error/warning/info severity + verified non-issues, drift patterns, fix priority, enforcement escalation, config-gap observations

## Remediation (delegated — not part of this checklist)

The audit stops at the Phase 3 report. Fixing, verifying, self-reviewing, and retrospecting are owned
by other plugins; with `--fix` the audit hands the findings off rather than running them here:

- Fix → `/implementation:implement` (when the `implementation` plugin is installed)
- Verify → `/verification:confirm` (when the `verification` plugin is installed)

When those plugins are absent, the Phase 3 findings table is the handoff — remediate manually in the
reported fix-priority order.
