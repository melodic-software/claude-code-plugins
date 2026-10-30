# DX eval scenario sources

The hand-rolled eval harness for the developer-experience skills: the source material each port to
`claude plugin eval` reads. Run results and judge run output are not kept here.

- `eval-scenarios-draft.md`: the spec (scenarios S1-S7, T1-T4, N1, stays-quiet, rubrics, run matrix).
  Its AC-n citations and `.work/devx/` paths refer to the planning workspace it was written in.
- `harness/build-fixtures.py` and `harness/build-agentic-overlay.py`: generate
  `fixtures/<tarnquill|brackenfold>/<state>/` (bare, conventions-only, converged; legacy for
  tarnquill) and `fixtures/brackenfold-agentic/` under `sources/`. Their output is not
  committed: run `python3 -I harness/build-fixtures.py`, then
  `python3 -I harness/build-agentic-overlay.py`.
  The output matches the original fixtures except the project GUIDs `dotnet new sln` writes.
  Converged managed blocks are written by the shipped `pointer-line.sh`; the legacy block names a
  `.claude/` path the helper refuses, so it is written literally. The `claude plugin eval` cases
  read the committed copy in `evals/fixtures/` instead, seeded by `evals/fixtures/seed.sh`, so a
  change to a file `build-fixtures.py` writes goes into its copy there too.
- `harness/scenarios.sh`: scenario id to fixture, per-arm state, prompts, tool allowlist.
- `harness/run-cell.sh`: one run, `--help` for flags and exit codes. `EVAL_RUNS_DIR` (required)
  holds the workspaces, outside the repository. Results land in
  `results/<scenario>/<arm>/<model>/run-<n>/`; cost fields are removed from saved stream-json.
- `harness/score-deterministic.py RESULT_DIR`: D and T items of S1 and the sentinel runs, into
  `score.json`. J items are listed as unscored. `harness/score-deterministic-check.sh RESULT_DIR`
  checks its item 8 on copies of a real run (`EVAL_TEST_DIR` required).
- `held-out/`: the H-audit and H-build held-out scenarios.
- `judge/items.json`: the J-item rubric checklist; `judge/judge.py`, `judge/build_inputs.py` and
  `judge/score_j.py` build judge inputs, run the judge and score it (`DX_JUDGE_SCRATCH` required).
- `labels/`: labeled judge calibration samples, described in `labels/README.md`. The samples are
  model output on the synthetic scenario prompts, with machine paths replaced by placeholders.
- `lists/`: the run lists `harness/run-batch.sh` read for each pass.

The forge variables are `TARNQUILL_FORGE_URL` and `TARNQUILL_FORGE_TOKEN`.
