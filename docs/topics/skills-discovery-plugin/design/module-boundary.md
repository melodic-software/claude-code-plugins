# Module boundary — audit-skill-visibility

Resolves T6, T8, T9 from [`design-threads.md`](design-threads.md).

## Ownership

Both this skill and `observability` touch `.claude/observability/`, so ownership is stated rather
than implied:

| Concern | Owner |
|---|---|
| Interpretation of skill-usage data (reach, observation, starvation) | **this skill** |
| Hook-event JSONL, OTEL infrastructure, collector/store health | `observability` |
| Retention harness (the single `clean.sh`) | `observability` — this work adds a target, not a second harness |
| Writing skill-usage events | the existing hooks — **unchanged** |
| Fleet enumeration | `inventory` — called, never reimplemented |
| Store path resolution across the three scopes | `hooks/claude-ops-paths.sh` — consumed by both |

The rule that keeps this honest: **one writer, many readers.** Nothing here writes a store; the
skill reads and reports, and the only mutation in the whole change is `clean.sh` gaining a pruning
target.

## Internal shape

```text
plugins/claude-ops/
  lib/state-key.sh                      # NEW — first lib/ in this plugin; report keying
  skills/audit-skill-visibility/
    SKILL.md                            # frontmatter + routing; ${user_config.*} substitution
    context/                            # progressive disclosure, read on demand
      classification.md                 #   the 15 causes + provenance rules
      budget-arithmetic.md              #   the certain-half computation
      output-format.md                  #   rendering + withheld section
    scripts/
      collect.sh                        # source ladder -> normalized events + horizons
      classify.<ext>                    # PURE: (denominator, events, config, clock) -> model
      render.sh                         # model -> markdown | json | html
    *.test.sh                           # repo convention
```

`collect` / `classify` / `render` split exists because **only `classify` needs to be pure**, and
purity is what makes the audit's failure modes testable. Collection touches the world; rendering is
presentation; the judgement in the middle takes data and a clock and returns a model.

## Dependency direction

```text
audit-skill-visibility
  ├── reads ──> inventory/scripts/inventory.py --out        (denominator)
  ├── reads ──> hooks/claude-ops-paths.sh                   (store resolution)
  ├── reads ──> ~/.claude.json, skill-usage.jsonl, OTEL     (sources)
  ├── uses  ──> lib/state-key.sh                            (report keying)
  └── cited by > observability/context/read-routing.md      (routing row only)
```

All arrows stay **inside** `claude-ops`. No sibling-plugin imports — `docs/PLUGIN-PHILOSOPHY.md`
treats a bare cross-plugin reference as a defect, and it is the reason a standalone plugin was
barred in the Brief.

## Test seams (T8)

One seam carries the design: the **pure classifier**. Fixtures target the failure modes the audit
actually found, so each test pins a defect that would otherwise ship:

| Fixture | Pins |
|---|---|
| horizon shorter than the tier windows | tiers clamp; nothing renders `dormant` on a 3-day install |
| empty store, populated native counters | `not-observable` rather than `never used` |
| `pluginUsage` install-seeded rows | never read as skill usage or as recency |
| same-second duplicate invocations | no dedupe collapse (id-less rows) |
| same event in native + JSONL | reconciled by rule, never summed |
| cross-marketplace same-leaf collision | `ambiguous-attribution`, not misattribution |
| bundled + `name-only` skills | excluded from demand sum and from ranking |
| demand just under / just over budget | overflow boundary arithmetic |
| below exposure floor | claim lands in `withheld` with a reason |

Injecting the clock is what makes horizon behavior testable at all — without it, every test drifts
with the calendar. Shell-level `*.test.sh` covers the CLI surface per repo convention.

## Design defaults (T9)

- **Configurability** — windows, exposure floor, and tier forcing arrive as **flags**, because
  `CLAUDE_PLUGIN_OPTION_*` does not reach a skill-spawned subprocess (proven by
  `docs/extensibility-contract-smoke-tests.md` Test B). `${user_config.*}` substitution into
  SKILL.md is the only other supported path.
- **Extension** — the source ladder is the extension axis: a new source implements
  `(events, horizon, capabilities)` and slots into tier resolution without touching the classifier.
- **Observability** — this skill emits **no** telemetry of its own. Adding a hook would spend from a
  budget the Brief already records as over the documented ceiling.
- **Testability** — flows from the pure classifier plus the injected clock, above.
