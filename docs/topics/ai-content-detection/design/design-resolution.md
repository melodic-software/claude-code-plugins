# Design resolution — ai-slop plugin

outcome: early-exit (Tier B — light design)

## Why early-exit

Every externally visible contract this plugin touches is owned by an existing convention, so
there is no new type or contract to design — the design work is conformance:

- **Findings output** — the findings-file shape is owned by
  `plugins/review/skills/fanout/context/default-mode.md` "Findings-file shape"; producer rules
  (four producer-owned fields, rule-id form, coexistence) by
  `docs/conventions/detector-findings/README.md`. This plugin conforms; it defines nothing.
- **Severity vocabulary** — owned by `plugins/review/context/severity.md`, with the crosswalk
  rows argued in the detector-findings convention's registry table.
- **Plugin layout and naming** — owned by `docs/PLUGIN-PHILOSOPHY.md` (skill = imperative verb;
  `audit` = read-only with mutation only behind an explicit override) and the marketplace/catalog
  registration surfaces.
- **Upstream sourcing** — the four-part record (claim, basis, as-of, recheck trigger) is owned by
  `docs/conventions/upstream-drift/README.md`.

## Type sketch (the only plugin-internal shapes)

```text
plugins/ai-slop/
├── .claude-plugin/plugin.json          # standard manifest (naming plugin as reference shape)
├── README.md / CHANGELOG.md
├── skills/setup/SKILL.md               # required: plugin has a consumer-config surface
└── skills/audit/
    ├── SKILL.md                        # /ai-slop:audit — read-only default; fix behind explicit arg
    ├── reference/catalog.md            # distilled tell catalog (schema below)
    └── scripts/
        ├── detect.sh                   # deterministic detector (audit-noise's detect.sh as shape)
        ├── detect.test.sh              # fixture-driven tests (shell-test-helpers convention)
        └── fixtures/                   # slop samples with known expected findings
```

Consumer-config surface (thresholds, word-lists, path exclusions, in-file opt-out marker) resolves
per `docs/conventions/config-cascade/README.md`. `rule-em-dash` is zero-tolerance by default with
per-document exemption only (user decision at plan approval). PLAN.md Phase 2 is the operative
spec where this sketch and the plan differ.

Catalog entry schema (internal, one row/section per wiki tell):

```text
id            rule-<slug> (crosswalk-qualified form: ai-slop/audit/rule-<slug>)
name          the wiki's tell name
description   one-to-two lines, our own words (CC BY-SA attribution page-level)
detectability mechanical | judgment
applicability general-prose | wikipedia-specific
v1            script | rubric | recorded-only (wikipedia-specific tells are recorded, not run)
```

Upstream-drift stamp: page-level four-part record in catalog.md front section (claim = catalog
derives from the cited revision; basis = page URL + revision id; as-of date; recheck trigger =
a recurring observable occasion — each ai-slop release and each fleet audit; per-revision was
rejected after measuring the page at 50+ edits/week).

## Threads directional, none open

- Detector output format for the human report is detect.sh's own (like audit-noise); the
  findings FILE is the conformance surface.
- Fix-path safety reuses the compress model (semantic-diff subagent) by pattern, not by import.
