# bugs config

Team layer of the `bugs` plugin's config cascade, read by `/bugs:scan` for its rotation lanes and
its filing posture. Keys, layer order, and merge semantics are the plugin's
`reference/config.md`; this file only supplies this repository's values. Re-run `/bugs:setup` to
change them.

Lanes follow the bundled default order so a run that falls to the date floor lands on the same
lane it would on any repository. Globs are include-only; test suites the globs also match
(`*.test.sh`, `*.test.mjs`, `test_*.py`, `*.Tests.ps1`) are companions the hunters read for a
unit's contract and never hunt, which the scan skill's scope step applies.

Filing posture is `allowed` because this repository's triage lane consumes `needs-triage` raw
intake, and on a cloud session the tracker is the only output that survives the container. A bare
`/bugs:scan` still files nothing; `--track` is required.

```yaml
lanes:
  - name: entrypoints
    globs:
      - 'plugins/*/hooks/*.sh'
      - 'plugins/*/hooks/*.mjs'
      - 'plugins/*/hooks/*.py'
      - 'plugins/*/hooks/*.ps1'
      - '.claude/hooks/*.sh'
  - name: core-logic
    globs:
      - 'lib/*.sh'
      - 'plugins/*/lib/**/*.sh'
      - 'plugins/*/lib/**/*.py'
      - 'plugins/*/skills/*/scripts/**/*.sh'
      - 'plugins/*/skills/*/scripts/**/*.py'
      - 'plugins/*/skills/*/scripts/**/*.mjs'
  - name: data-access
    globs:
      - 'plugins/work-items/tools/work-item-tracker/*.sh'
      - 'plugins/work-items/tools/work-item-tracker/lib/**'
      - 'plugins/claude-ops/skills/observability/otel/**'
      - 'plugins/knowledge/skills/*/extraction/lib/**/*.js'
      - 'plugins/code-metrics/scripts/parsers/**'
      - 'plugins/code-metrics/scripts/collectors/**'
  - name: integration
    globs:
      - 'plugins/work-items/tools/work-item-tracker/adapters/**'
      - 'plugins/miro/server/src/**/*.ts'
      - 'plugins/knowledge/skills/*/extraction/adapters/**'
      - 'plugins/knowledge/skills/*/extraction/acquisition/**'
      - 'plugins/source-control/skills/babysit-prs/scripts/*.sh'
      - 'plugins/source-control/skills/pull-request/scripts/*.sh'
      - 'plugins/source-control/scripts/*.sh'
  - name: config-and-startup
    globs:
      - '.claude/cloud-bootstrap.sh'
      - 'scripts/*.sh'
      - 'scripts/*.py'
      - 'scripts/*.mjs'
      - 'scripts/lib/*.sh'
      - 'plugins/*/skills/setup/scripts/**'
      - 'plugins/*/lib/*config*'
      - 'plugins/context-guard/scripts/*.sh'
      - 'plugins/rate-limit-guard/scripts/*.sh'
filing_posture: allowed
```
