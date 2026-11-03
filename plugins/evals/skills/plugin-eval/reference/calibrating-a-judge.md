# Calibrating a judge

Trust an `llm` grader's scores only after its judge, the model the suite uses, agrees with labeled
answers on at least 90% of runs; a pass says nothing about another model. Before the first full
run, calibrate every LLM-judge grader the harness can reproduce (one with labeled samples, judging
text); the default judge is uncalibrated until it passes. Report any other judge grader as
uncalibrated, never trusted silently. Labels are the must-pass and must-fail answers in the case's
`samples/<grader>.json`, set by three agents independently with the user settling every
disagreement:

```bash
python3 "<skill-dir>/scripts/calibrate-judge.py" build --suite <eval-dir> --out <empty dir outside the repo>
claude plugin eval <out> --trust-plugin --ablation none --threshold 0 --runs 3 --judge-model <the suite's judge model> --keep-temp --no-publish --json <out>/results.json
python3 "<skill-dir>/scripts/calibrate-judge.py" score --manifest <out>/manifest.json <out>/results.json
```

`--threshold 0` keeps the CLI's exit code about errors, since must-fail cases are meant to score 0.

`score` prints a `FAIL grader` line for each grader under 90% and exits 1; fix that rubric, or move
the whole suite to a stronger judge, and calibrate again before reading its scores. Its false
positives and negatives name the samples to read first. A sample with no reproduced run is listed
`untested`, counts toward no agreement, and shows in the verdict line; raise `--runs` or tighten
the prompt before reading the grader's score. What `build` writes and skips, and which runs
`score` leaves out: [case-authoring.md, Calibration samples](case-authoring.md#calibration-samples).
