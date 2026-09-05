# code-metrics module boundary

What lives where inside `plugins/code-metrics/`, which paths are the public entry surface, and
which repository registries the plugin touches on landing. Layout follows the two exemplars the
repository already carries: per-skill `scripts/` with co-located suites (`docs-hygiene`) and
plugin-level `scripts/` for code more than one skill runs (`skill-quality`).

## Tree

```text
plugins/code-metrics/
├── .claude-plugin/plugin.json          # name, version 0.1.0, description, author, license, keywords; no userConfig
├── README.md                           # lead, Works in any repo, Requirements (collectors), Install, Configuration, License
├── CHANGELOG.md                        # Keep a Changelog, ## [0.1.0]
├── reference/
│   ├── collectors.md                   # one stamped row per collector: version, output, as-of, recheck trigger
│   ├── config.md                       # the .claude/code-metrics.yaml keys, per-key override declared
│   └── report-schema.md                # code-metrics/v1 field reference
├── scripts/                            # shared, plugin-level, public entry surface for the skills
│   ├── dispatch.sh        + dispatch.test.sh          # resolve scope, lanes, collectors; assemble the report
│   ├── collector-ladder.tsv                           # lane, measure, tool, in ladder order; the whole T1 table from Phase 1
│   ├── pathglob.py        + test_pathglob.py          # gitignore-style glob matching at the 3.9 floor
│   ├── resolve-config.py  + test_resolve_config.py    # cascade: user-global, team, overlay; per-key override
│   ├── yaml_subset.py     + test_yaml_subset.py       # the YAML subset every surface the plugin reads is written in (T22)
│   ├── detect-lanes.sh    + detect-lanes.test.sh      # extension map, consumer ecosystems globs
│   ├── report.py          + test_report.py            # JSON assembly and markdown rendering
│   ├── collectors/
│   │   ├── lizard.sh, radon.sh, eslint-complexity.sh, sonarjs.sh, gocyclo.sh, gocognit.sh,
│   │   │   shellmetrics.sh, multimetric.sh, scc.sh, line-counter.sh, jscpd.sh, cpd.sh, dupl.sh,
│   │   │   type-coverage.sh, mypy-report.sh          # each with a co-located <tool>.test.sh
│   ├── parsers/
│   │   ├── lcov.py, cobertura.py, coverage_py_json.py, go_cover.py # each with test_<stem>.py
│   └── fixtures/                       # sample sources, captured tool outputs, coverage artifacts, config layers, a registry; no executables (stubs are generated at test time)
└── skills/
    ├── audit-complexity/  SKILL.md, scripts/run.sh + run.test.sh, evals/evals.json
    ├── audit-size/        SKILL.md, scripts/run.sh + run.test.sh, evals/evals.json
    ├── audit-duplication/ SKILL.md, scripts/run.sh + run.test.sh, evals/evals.json
    ├── audit-coverage/    SKILL.md, scripts/run.sh + run.test.sh, scripts/crap.py + test_crap.py, evals/evals.json
    ├── audit-type-debt/   SKILL.md, scripts/run.sh + run.test.sh, evals/evals.json
    ├── principles/        SKILL.md, reference/{measures.md,thresholds.md,crap.md,literature.md}, evals/evals.json
    └── setup/             SKILL.md, scripts/check.sh + check.test.sh, scripts/apply.py + test_apply.py, templates/config-template.yaml, evals/evals.json
```

`skills/<name>/scripts/run.sh` is a thin entry point: it parses the skill's arguments and calls
`${CLAUDE_PLUGIN_ROOT}/scripts/dispatch.sh` with the skill name and measure set. Nothing under a
skill's `scripts/` is duplicated across skills; the shared code is one copy under the plugin's
`scripts/`, which the encapsulation audit treats as an entry surface.

## Public and private

| Path | Visibility | Who may cite it |
|---|---|---|
| `skills/*/SKILL.md` | public | anything |
| `skills/*/scripts/run.sh` | public entry surface | other skills in this plugin, consumers |
| `scripts/dispatch.sh`, `scripts/collectors/*.sh`, `scripts/parsers/*.py` | plugin-internal entry surface | this plugin's skills only |
| `scripts/fixtures/**` | private | this plugin's tests only |
| `skills/*/reference/**`, `skills/*/evals/**`, `reference/**` | private supporting files | the owning SKILL.md, and the README for `reference/config.md` |
| `.claude/code-metrics.yaml` (consumer side) | consumer-owned contract | `reference/config.md` declares it |

## Seams

Inbound (what the plugin reads):

- Source files in scope, existing coverage artifacts, the consumer's `.claude/code-metrics.yaml`
  layers, the consumer's `.claude/ecosystems/<lane>.yaml` files when present, and any registry the
  config names.
- Collector binaries on `PATH` or in the repository's `node_modules/.bin`, probed and never installed.

Outbound (what the plugin produces or points at):

- One `code-metrics/v1` JSON document per run on stdout, and a markdown report rendered from it.
- Presence-gated pointers to `verification:measure` (the consumer of the JSON), and from
  `principles` to the owners of the measures this plugin does not carry (`mutation-testing`,
  `testing:audit`, `code-tidying:audit-dead-code`, `coupling:reduce`, `toolchain:lint`).

No hooks, agents, MCP servers, `bin/`, or workflows. No writes outside stdout and, for `setup
apply`, the consumer's `.claude/code-metrics.yaml`.

## Repository registries and gates touched on landing

| Surface | Change | Enforcer |
|---|---|---|
| `.claude-plugin/marketplace.json` | add the `code-metrics` entry, `category: quality` | `scripts/validate-plugins.sh`, `check-plugin-manifest-presence.sh` |
| `.claude/settings.json` | add `"code-metrics@melodic-software": true` to `enabledPlugins` in byte order | `scripts/check-plugin-catalog-enablement.sh` |
| `docs/CATALOG.md` | regenerate with `node scripts/generate-catalog.mjs` | `generate-catalog.mjs --check` |
| `docs/SKILL-CHEAT-SHEET.md` | regenerate with `node scripts/generate-cheatsheet.mjs` | `generate-cheatsheet.mjs --check` |
| `scripts/skill-leaf-name-registry.txt` | add `code-metrics` to the `principles` owner set | `scripts/check-skill-leaf-names.sh --check` |
| `scripts/em-dash-purged-paths.txt` | add `plugins/code-metrics/**/*.md` once the tree is clean | `scripts/check-purged-em-dashes.sh --check` |
| every new `.sh` and `.py` | a co-located suite in the same commit | `scripts/affected-tests.sh --run` fails closed on an unmapped code file |
| `scripts/fixtures/**` (plugin) | consumed by a `.test.sh` or `test_*.py` | `scripts/check-orphaned-fixtures.sh` reaches only `evals/fixtures/`; script fixtures live outside it and are read by the suites |

Cross-plugin edits on the same branch, as separate commits after the plugin lands (Q22): a gated
pointer in `plugins/verification/skills/measure/context/metrics.md`, the missing gate and
fallback at `plugins/testing/skills/write/context/organize.md:63-66`, and a gated pointer from
`plugins/mutation-testing/skills/principles` to `code-metrics:principles` for the cross-metric
caveats. Each carries that plugin's version bump and changelog entry.

## Conventions the scripts follow

- Bash: `#!/usr/bin/env bash`, `set -uo pipefail` in suites and checkers, `set -euo pipefail` in
  entry points that should abort; `[[ ]]` per `.shellcheckrc`; no `which`; fixture git isolation
  (`unset GIT_DIR GIT_WORK_TREE GIT_CONFIG`) in every suite.
- Python: `#!/usr/bin/env python3`, standard library only, `MIN_PYTHON = (3, 9)` floor, linted
  through `scripts/run-ruff.sh check plugins/code-metrics`. Shell entry points resolve the
  interpreter with the repository's candidate loop (`python3`, `python`, `py -3`), never a bare
  hardcoded name.
- Fixtures: every fixture file's basename is spelled literally in at least one covering suite, so
  `scripts/affected-tests.sh` maps it (its rule R3); sample sources are lint-clean or carry a
  per-file `# ruff: noqa` or `# shellcheck disable=` header, because the repo's lint sweeps do not
  exclude `scripts/fixtures/`; no executable is committed under fixtures.
- Suites needing a real tool that is absent print a visible `SKIP <tool>` line and exit 0, the
  shape `scripts/run-plugin-tests.sh` expects; a silent pass is a defect.
- Every shebang script under `scripts/` and `skills/*/scripts/` is mode 755 (the exec-bit lane);
  every shell entry point resolves `PLUGIN_ROOT` with the `${CLAUDE_PLUGIN_ROOT:-...}` idiom so it
  runs outside a Claude session.
- Fixture sources use dictionary-word identifiers, because `_typos.toml` is synced verbatim from
  upstream and excludes no fixture path.
- Sanity-check pipes run under `set -o pipefail` (or capture to a file and test `$?`), so "exits 0"
  observes the script, not the Python one-liner after it.
- Every skill frontmatter states `disable-model-invocation` explicitly, carries `metadata.summary`
  under 100 codepoints, and quotes `Use when:` triggers in single quotes; SKILL.md stays under 200
  lines with a `## Gotchas` section.
