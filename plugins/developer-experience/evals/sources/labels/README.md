# Judge calibration labels

One directory per J item: `<scenario>/<item>/`.

- `samples/real-<arm>-run<n>.md`: the judge input built from a baseline run
  (`../judge/build_inputs.py`, arm markers stripped).
- `samples/var-<arm>-run<n>.md`: a constructed variant, a minimal edit of that real sample meant to
  flip the item (written by a Sonnet subagent from `../judge/briefs/variant-brief.md`, which saw
  the rubric item and context but not the judge instructions).
- `samples/extra-*.md`: further constructed samples added only where an item lacked balance.
- `labels.jsonl`: one row per sample: `label` (PASS/FAIL) and the labeler's `reasoning`.

**Labels are model-produced.** Each label comes from a separate `claude -p --model opus` call
(no tools, no session persistence, the run-cell.sh isolation flags) that saw only the rubric item,
its context (answer key or fixture facts) and the one sample; it wrote its reasoning, then
`LABEL: PASS|FAIL`. No human reviewed them. A human spot-check of the labels is the user's option;
until then, TPR/TNR measure the Sonnet judge's agreement with an Opus labeler, not with ground
truth. The samples never appear in a judge prompt.
