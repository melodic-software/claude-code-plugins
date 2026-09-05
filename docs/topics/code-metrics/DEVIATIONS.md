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

## Wave B (2026-09-05)

- **plan-confirmed.** The plan says the report assembler grows every row shape before Wave B.
  Found: `report.py` counted `files`/`functions` only, so a clone-group row had no
  `summary.duplicated_lines` (the Phase 5 sanity check reads it) and a skill that drops rows
  after assembly had no way to recompute the summary. Added main-side before dispatch, in the
  orchestrator's territory: `summarize()` (clone-group rows add `duplicated_lines` and
  `clone_groups`; instance files count toward `files`), the `resummarize` verb, and instance
  rendering; `test_report.py` covers each. Commit: the one preceding the Wave B worker commits.
- **deviation.** Plan said (the dispatch skill's default): each worker provisions a worktree,
  commits, and pushes early. Found: the operator's "one branch, one PR" decision and the plan's
  fence ("FORBIDDEN: staging, commit, or push") put every worker on the shared checkout of
  `claude/code-quality-metrics-plugins-p99tkz`, file-disjoint by the scope-fencing table. Chose:
  workers edit in place and never touch git; the orchestrator verifies each return, runs the
  whole-plugin gate, and commits per return. Revisit: none; the plan's fence is the approved form.
- **discovery.** (Phase 7, worker A4) The Phase 4 sanity check asserted `crap.py --comp 5 --cov 0`
  prints `130`; under the Brief's own formula `comp^2 * (1 - cov/100)^3 + comp` the value is 30
  (25 + 5), and 130 would need a cubed term. PLAN.md line 377 now says `30`; the other two values
  (5 at full coverage, 930 for comp 30) were already right.
- **deviation.** Plan said: the Phase 7 gate counts `when the [a-z-]* plugin is installed`. Found:
  the fleet form (seam-phrasing, `audit-size/SKILL.md`) writes the plugin name in backticks, which
  that regex misses, so the worker dropped the backticks to satisfy it. Chose: restore the
  backticks in `principles/SKILL.md` and let the plan's grep accept both forms (`\`\?`). Revisit:
  none.
- **discovery.** (Phase 7) Corpus A2 verified the cognitive-complexity white paper at version 1.7
  (29 August 2023) and no earlier edition; `literature.md` cites that version rather than the
  brief's "Campbell 2018". Corpus A1 records the CRAP introduction as 17 July 2007 after its
  verifier corrected an October date in the sidecar.
- **discovery.** (Phase 6, worker A3) The dispatcher discards an adapter's `probe` stderr and
  builds the `unavailable` reason from `install_hint` alone, so a specific probe failure (the
  `type-coverage` binary present but no resolvable `typescript`) reads as the generic "not found".
  The worker kept its fence: `probe` prints the specific sentence, and the install hint names the
  `typescript` requirement so the run row still explains it. Relaying probe stderr into the reason
  is a one-line dispatcher change for every adapter; scheduled for Phase 8 (main session), with
  the dispatcher suite pinning it. Also verified live: `type-coverage --json-output` is a boolean
  flag (JSON to stdout), `details[]` needs `--detail`, and `typescript` 7.x crashes
  `type-coverage` 2.30.1 in the same way as an absent one (surfaces as exit 3 with stderr).
- **plan-confirmed.** (Phase 6) The `dotnet type_coverage` ladder rung shipped as `none`
  (`unavailable`) while design T9 and the Phase 6 sanity check want `not-applicable`; the
  orchestrator changed it to `n/a` in `9011b537` before dispatch, outside the phase's file list.
  Phase verifier: 13 of 13 PASS; its observation that the skill can never report `complete`
  (three lanes are permanently `not-applicable`) is a report-status rule for the main session.
- **deviation.** Plan said: Phase 3 and Phase 5 sanity pipelines feed the entry script's default
  output to `json.load`. Found: the default output is markdown (as for `audit-size`), so both
  pipelines fail by construction. Chose: the sanity lines gain `--json`, the form the Phase 1
  check already uses. Revisit: none.
- **plan-confirmed.** (main session, after Wave B returned) The frozen dispatcher and assembler
  needed four reconciliations, all in the orchestrator's territory and pinned by their suites:
  the dispatcher suite's "adapter not shipped" cases assumed no complexity adapter existed and
  its tool filter lacked `eslint` (five cases rewritten; the `--all` fixture scope now includes
  the duplication cluster's two bash copies, so counts are 7); a failed `probe`'s stderr is now
  relayed into the `unavailable` reason (Phase 6's finding; "not found" stays the fallback);
  `status: complete` no longer withheld by `not-applicable` rows (Phase 6's finding; `unavailable`
  and `deferred` still make a run `partial`; contracts.md §2 and report-schema.md updated); and
  `cpd` gained ladder rungs after `jscpd` for typescript, python, go, and dotnet so the
  documented collector override can reach it (Phase 5's finding; the override validates names
  against the ladder). Every plugin suite green afterwards (8 shell suites, 183 pytest cases).
- **plan-confirmed.** Phase 3 verifier 13 of 13 PASS; Phase 5 verifier 13 of 13 PASS, including
  the Brief's acceptance case against the live `hook-utils.sh` cluster with a cached `jscpd`
  5.1.2 (zero debt through `scripts/cross-plugin-source-registry.txt`, 44,256 duplicated lines
  without it). Observations carried forward, none a defect: `lizard`'s `function_lines` counts a
  nested function's lines inside its parent (the ISO §8.2.115 reading; the CRAP join subtracts
  nested ranges, per T7, and Phase 4's brief says so); `radon hal` rows carry neither line and
  the label `no-line-range` (a third null-range class beside `start-line-only` and
  `file-level`); `jscpd` reports pairs, so a 17-copy cluster is 16 excluded entries (documented
  in the skill's Gotchas); after a total registry exclusion `summary.files` counts surviving
  rows only, while the scope header still shows the file count (a Phase 8 wording check). The
  `cpd` docstring and SKILL.md were updated by the orchestrator after the verifier ran, because
  the rungs added in `e5fc309e` made their "no rung ships" wording stale; re-gated.
