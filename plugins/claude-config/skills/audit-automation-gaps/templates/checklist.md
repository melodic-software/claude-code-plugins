# audit-automation-gaps Checklist

Copy into your working task notes. Tick as each phase completes.

## Phases

- [ ] Phase 1: Discover candidates (self-generated) — enumerate automation gaps across hooks + MCP + skills + agents + scheduled routines
- [ ] Phase 2: Deep-dive each candidate — evaluate against the enforcement hierarchy (compiler / analyzer / hook / CI / docs); cost-benefit analysis
- [ ] Phase 3: Present results — categorized recommendations with rationale + anti-noise doctrine compliance
- [ ] Phase 4: Implement (if `--implement` or user requests) — apply approved candidates with plan + incremental validation

## Anti-noise doctrine (applied throughout Phase 2)

- [ ] Each candidate cleared every quality gate in SKILL.md §2.3, with the required evidence cited

## Skip criteria

- Phase 4 SKIPPED in `--recommend-only` mode (default; explicit `--implement` opts in)
