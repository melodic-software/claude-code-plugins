# Design resolution — cross-repo-landscape

outcome: design-significant (Tier A) — a new skill (`architecture:map-landscape`) with a new
consumer-facing configuration surface, a new helper script contract, and a cross-plugin seam;
plus a light change to an existing gate (`planning:design-handoff`). Resolved in one planning
session (2026-09-06) against the actual plugin sources rather than a multi-round `/planning:design`
session: every thread had a single defensible answer once the collaborator's real contract was
read. Threads and rationale: `design-threads.md` beside this file (T1–T10, all RESOLVED).

## Contract surfaces introduced

| Surface | Owner | Shape |
|---|---|---|
| Skill argument grammar | `architecture:map-landscape` | `[--repos <path>[,<path>...]] [--root <dir>]...` (T1) |
| Fleet-hygiene seam | `architecture:map-landscape` (consumer) | invocation of `/repo-fleet-hygiene:audit` with `--plan-file`; reads `schema_version`, `repositories[].canonical`, `repositories[].remote` (T2) |
| Facts collector | `architecture:map-landscape` | `plugins/architecture/skills/map-landscape/scripts/portfolio-facts.sh`, one JSON object per repo on stdout (T3) |
| Consumer topic doc | the consuming repository | `<convention-home>/architecture/README.md`, keys `architecture_dir`, `landscape_dialect` (T5) |
| Vendored resolver | `claude-config` (canonical), `architecture` (carrier) | `plugins/architecture/lib/resolve-convention-home.sh`, enrolled in `scripts/sync-resolve-convention-home.sh` (T5) |
| Artifacts | the consuming repository | `<architecture_dir>/landscape.dsl` or `landscape.md`, `<architecture_dir>/portfolio.md` (T6, T7) |
| Gate output | `planning:design-handoff` | six-row advisory coverage table in the gate output and resume prompt (T8) |

## Dependency order

T5 (home and dialect resolution) and T2 (discovery) are independent; T3 feeds T4 and T7; T6
depends on T5's dialect key. T8 is independent of every other thread. Implementation order in
PLAN.md follows this.

## Not designed here, by exclusion

Baseline-versus-target comparison, container/component C4 views, capability maps, a standalone
design-document skill, and persistence of the convention-home pointer line (see PLAN.md deferred
questions).
