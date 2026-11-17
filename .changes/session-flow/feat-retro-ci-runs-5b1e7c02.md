---
bump: minor
---

### Added

- `/session-flow:retro ci-runs` runs a retrospective over chosen CI lane runs from their sealed transcripts, on the machine that holds the lane transcript sink: by run URL or id, by `--lane <stem> --last <n>`, or by a date window with `--outcome` and `--model`, with `quick` as a depth and an optional quoted view of the result treated as data. Each run resolves to its legs (key, subscription, fallback, and a review run's chunks) through the sink's `metrics.jsonl`. It reuses session mode's analysis, catalog, approval step and route to `/corrections:codify`, skips the feedback-memory regression check because a lane leg has no human turns, and keeps a score history per lane that `/session-flow:audit-sessions trends` shows beside the project's.
- The `lane_transcript_sink` option names the sink. It has no default: unset, each `ci-runs` run needs `--sink`.
- `scripts/lane_legs.py` resolves runs to legs, and `scripts/parse_transcript.py --legs` reads sealed legs. The shared transcript reader reads a gzipped (or plain) JSON array of stream-json messages, giving their fields the transcript's names and marking a subagent's inline messages as sidechain records.

### Changed

- The transcript parser moves to `scripts/parse_transcript.py`, with its invocation in `reference/transcript-parser.md`, so `/session-flow:running-retro` no longer reads retro's private files.
- The session collector (`collect.py`, `census.py`, `friction_scan.py`, `redact.py`), the vendored gitleaks rules and the drift canaries move to the plugin's `scripts/`, `vendor/` and `reference/`, so `/session-flow:audit-friction` no longer runs audit-sessions' private script. The collector's input list changed, so the next collect re-reads every session once.
