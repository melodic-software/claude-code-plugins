# code-metrics deviations log

Append-only. Entries follow the implementation skill's contract: `plan-confirmed`, `discovery`,
`deviation` (plan said / found / chose / revisit), or `human-decision`.

## Phase 1 (2026-09-05)

- **deviation.** Plan said: a collector adapter is one file `scripts/collectors/<tool>.sh` with a
  co-located `<tool>.test.sh`. Found: every non-trivial adapter translates JSON or CSV tool output
  into rows, which design thread T20 puts in Python, and a bash adapter would shell out to a
  Python translator anyway. Chose: adapters are `scripts/collectors/<tool>.py` implementing the
  same four verbs (`probe`, `measures`, `collect`, `install_hint`) with a co-located
  `test_<tool>.py`; the dispatcher invokes them through the resolved interpreter. Revisit: none;
  the contract in `design/contracts.md` section 3 and the fences in the plan are updated to `.py`.
- **deviation.** Plan said: Phase 1's `detect-lanes.sh` reads the consumer's ecosystem `globs`.
  Found: those files are YAML, and the subset parser lands in Phase 2. Chose: `detect-lanes.sh`
  takes `--globs <lane>=<pattern,...>` and `--disable <lane>` from its caller (matching through
  `pathglob.py`, shipped now); Phase 2's config resolver reads the ecosystem files and passes
  them through. Revisit: none; Phase 2's file table gains the wiring.
- **plan-confirmed.** The all-lanes-unavailable guarantee holds (exit 0, `status: empty`, every
  `run[]` row non-ok with a reason naming both rungs and the install hint), but the plan's sanity
  command spelled it as `PATH=$(mktemp -d) ...`, which starves bash of the interpreter. The
  executable form is `CODE_METRICS_DISABLE_BUNDLED=1` with `scc` off `PATH`; the dispatcher suite
  builds a filtered `PATH` (every executable except the ladder's tools) for the same case.
- **discovery.** Fixture sources with a shebang need an exec bit under the repo's exec-bit lane,
  and a fixture must not be executable; `fixtures/sources/cm-sample.sh` therefore carries
  `# shellcheck shell=bash` instead of a shebang.
- **discovery.** A two-word launcher (`py -3`) cannot travel in a scalar; the interpreter resolver
  is one sourced file, `scripts/python-resolve.sh`, that sets the array `PY`, and every shell entry
  point uses it (the phase verifier caught the scalar form).
- **plan-confirmed.** `scripts/config-defaults.json` (the bundled defaults every threshold reads)
  ships in Phase 1 because the dispatcher needs a threshold source before Phase 2's resolver
  layers the consumer's YAML over it; the Phase 1 file table now lists it.
- **discovery.** `scripts/affected-tests.sh` rule R3 maps a fixture only when a suite spells its
  basename; the dispatcher suite now asserts the five lane fixtures by name for that reason.
- **discovery.** Generic basenames select unrelated suites through the same rule, so the plugin
  avoids them: the fixture sources are `cm-sample.*`, the per-skill entry script is
  `skills/<name>/scripts/<name>.sh` rather than `run.sh` (named by three repo scripts), and the
  bundled defaults file is `config-defaults.json`. One shared basename cannot be avoided:
  `evals/evals.json` alone selects roughly 155 suites because many repo scripts name it, which is
  the tool's documented safe over-selection and applies to every skill in the marketplace; the
  phase gate's `--run` therefore lists the phase's files without `evals.json` (a `*.json` path is
  on the no-suite allowlist and covered by the non-shell CI lanes).
