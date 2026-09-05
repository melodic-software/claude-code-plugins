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

## Phase 2 (2026-09-05)

- **deviation.** Plan said: `skills/setup/scripts/check.sh` and `apply.py`. Found: `check.sh`
  and `apply.py` are generic basenames that the affected-tests basename rule would select across
  the repository. Chose: `setup-check.sh` and `setup-apply.py` (same contract). Revisit: none.
- **deviation.** Plan said: `resolve-config.py` emits the resolved document. Found: the
  dispatcher, a bash script, cannot read JSON without a helper, and a caller passing a
  pre-resolved `--config` must get the same derived options. Chose: `--from-json` plus three
  line-oriented formats (`dispatch-args`, `ladder-overrides`, `excludes`) that the dispatcher
  consumes with `mapfile`. Revisit: none.
- **plan-confirmed.** `size.mode: iso-8.2.115` ships as a `function_lines` measure whose ladder
  rows point at the function-range collectors (`lizard`, `radon`); until Phase 3 lands those
  adapters the mode reports `adapter not shipped`, which is the ladder contract working, and Bash
  carries a `none` row because no Bash collector reports function end lines.
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
- **plan-confirmed.** The subset parser's named error carries the line before the construct
  (`<file>: line 4: flow mapping ({...}) is outside the subset`), the shape every layer-reading
  surface reports; the plan's sanity regex had the two in the other order and now matches the
  emitted form.
- **discovery.** The Phase 2 diff touches seven Phase 1 files the table did not list: the
  `size.mode` key needed `function_lines` ladder rows, a `function_lines_pct` threshold, and
  `--config` pass-through in `audit-size` (now a MODIFY row in the table), and
  `scripts/run-ruff.sh format` reflowed five Phase 1 Python files with no behaviour change (the
  repository's ruff-format hook is advisory; CI runs `ruff check`). Phase verifier: 14 of 14
  criteria PASS; its six observations (the table rows, a fixture comment, an alias test case, an
  EXIT-trap gap in `setup-check.sh`, a test name) were applied before the phase commit.
