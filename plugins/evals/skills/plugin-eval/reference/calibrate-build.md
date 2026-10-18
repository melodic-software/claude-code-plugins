# What `calibrate-judge.py build` writes

`build` writes one case per sample into an empty plugin: the source case's prompt goes out
unchanged, and an appended system prompt presents the sample as fixed test material for the agent
to output byte for byte, even when wrong or incomplete, with no commentary, so the judge grades
that sample as the answer to that question. No generated file carries the label; a must-pass and a
must-fail case differ only in the sample text. `build` skips a grader that judges a file or mock
calls, and prints one line for each empty or whitespace-only sample it skips: Claude Code answers
an empty reply with an injected user turn, so it cannot be reproduced, and an empty answer is a
deterministic failure that needs no judge. The appended prompt does not reach a `focus: trace`
judge. `--threshold 0` keeps the CLI's exit code about errors, since must-fail cases are meant to
score 0.

# What `score` leaves out

Agreement leaves out a run whose reply was not the sample, and one with neither a kept trace nor
judge evidence (also reported unchecked). A sample with no reproduced run is listed `untested`,
counts toward no agreement, and shows in the verdict line.
