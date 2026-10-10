# user-experience

Front door for user experience on the app being built, at any stage: an idea with no code, a new
build, an existing app or a legacy one. It helps an agent, and the person driving it, work out who
uses the app and what they need. It uses the project's own research, personas and analytics first,
routes to the tools installed, and labels every deliverable evidence-based, assumption-based or
mixed.

## Skills

| Skill | What it does |
|---|---|
| `/user-experience:shape` | States the app's stage, audience and evidence, then chains the jobs below in order: research, synthesis, structure, evaluation |
| `/user-experience:plan-user-research` | Picks a research method and writes the instrument: discussion guide, screener, usability test script, survey, inclusive-research plan |
| `/user-experience:synthesize` | Codes research data into themes, insights, needs, personas or jobs to be done, with AI-suggested codes for a human analyst |
| `/user-experience:structure` | User flows with their states and exits, information architecture, journeys, the first-run flow, card-sort and tree-test plans |
| `/user-experience:evaluate` | Evaluation plans, expert review, fair-choice checks, UX-debt baselines and measure selection |
| `/user-experience:setup` | `check` the prerequisites and the team file; `apply` writes the team file. Run it by hand |

Every skill except `setup` is model-invoked.

The `evaluator` agent ([`agents/evaluator.md`](agents/evaluator.md)) reviews a flow, journey or
synthesis written earlier in the same session, in a fresh context that never sees the reasoning
behind it. It holds only Read, Grep and Glob. `/user-experience:evaluate` dispatches it; it is not
for direct use. A flow ready for screens goes to
`/user-interface:design` when that plugin is installed. The plugin writes research instruments but
never recruits or runs sessions, and selects measures but never instruments analytics.

Every deliverable follows [`reference/deliverable.md`](reference/deliverable.md): an evidence label,
a source or "assumption" per claim about users, an AI-use disclosure where the kind needs one,
`Basis:` per recommendation, and no participant data.

## Team file

A team sets its conventions in `<home>/user-experience.yaml`, where `<home>` is the repository's
convention home (default `docs/conventions`). All keys are optional:

```yaml
version: 1
routing:
  version: 1
  rows: []        # re-rank a bundled row or add one whose id is bundled or installed
  disable:
    - job: synthesis
      id: dovetail
  deny: []        # names never routed
jtbd_school: unset   # outcome-driven-innovation | jobs-to-be-done-theory | unset
research_paths: []
persona_paths: []
output_home: null
```

Write it in block style. A flow mapping such as `- {job: synthesis, id: dovetail}` is outside the
YAML subset the plugin reads, so the whole file is skipped. When the file is missing, malformed or
unreadable, the skills use the built-in routes, name the skipped file, say that team overrides and
the deny floor were not applied, and suggest `/user-experience:setup`. A path key that leaves the
project or points under `.claude/` or `.git/` is dropped with a warning. The schema is
[`reference/team.schema.json`](reference/team.schema.json).

## Prerequisites

Declared in [`prerequisites.json`](prerequisites.json), both optional:

- `node` runs [`scripts/detect.mjs`](scripts/detect.mjs). Without it the skills read the project's
  files directly and the team file is not applied.
- The `claude` CLI lists the installed plugins and MCP servers. Without it, routes are checked
  against the session's own skill listing.

`/user-experience:setup check` reports both, and `/harness-ops:prerequisites` reports them across
the enabled plugins.

## Routing

The plugin adopts the routing-as-data convention (`docs/conventions/routing-as-data/README.md` in
the marketplace repository). Routes live in [`reference/routing.json`](reference/routing.json),
grouped by `job` and validated by [`reference/routing.schema.json`](reference/routing.schema.json).
`scripts/detect.mjs` marks each row present or not and applies the team file's `routing` changes:
an added row's id must match a bundled row or an installed plugin or skill, a row with a bundled id
may not change that row's `kind`, `detect` or `account`, and a team file may not add a
`kind: tool` row. Untested account-free routes ship `unconfirmed`, and untested account-bound
ones `deferred`.
