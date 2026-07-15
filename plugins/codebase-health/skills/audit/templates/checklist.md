# codebase-health Checklist

Copy into wherever the consuming repo keeps working task notes. Tick as each phase completes.

## Phases

- [ ] Phase 0: Prime context — read the repo's conventions (`CLAUDE.md` / `AGENTS.md` / `.claude/rules/`); resolve the audit config and read its verification-sources
- [ ] Phase 1: Discover — per-file subagent fan-out over active dimensions' primary-sources (scope-gated)
- [ ] Phase 2: Validate & enrich — independent re-verification of each finding against source of truth; external research where a claim needs it
- [ ] Phase 3: Categorize & present — findings table with error/warning/info severity + verified non-issues, drift patterns, fix priority, enforcement escalation
- [ ] Phase 4: Implement / fix — apply fixes in priority order (respect `--review-only`)
- [ ] Phase 5: Verify — run the repo's own build/test/lint gates on each fix
- [ ] Phase 6: Review — self-review: fixes applied, no regressions, docs match code, refs valid
- [ ] Phase 7: Retrospective — summary, enforcement recommendations, config-gap observations

## Skip criteria

- Phases 4-7 SKIPPED in `--review-only` mode (audit produces findings; user/separate session implements)
- Phase 5 fix-verify pair may iterate per-fix vs batch — depends on blast radius
