---
bump: patch
---

### Changed

- Eighteen native cases for `/work-items:triage` join the `evals/` case suite, covering legacy triage cases 1-14, 16 and 18-20 ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)): the unsolicited-PR intake, verification before interview, decompose output that is never re-triaged, the raw-marker transitions of the briefed and needs-info outcomes, the lane's standing rules as direction with the AI disclaimer, the direction gate's restatements, item text treated as data, lane-telemetry exclusion by title and by pinned config, a lane barred from class labels, the board page built only from escaped JSON, the repro count read from the repository file, runs that disagree, a rejected command-substitution `--config-ref`, and signal provenance. The triage `evals.json` file stays until the rest of its cases land.
