---
bump: minor
---

### Added

- **`/performance:verify` names what limits the number before the verdict.** The report gains
  `Limiter:` (the resource or bound holding the result, from a profiled run that is not reported)
  and `Ruled out:` (at least one other explanation and the evidence that excludes it), plus a
  bound check that a saving cannot exceed the changed code's share of the run. A report that cannot
  fill one of the two lines is not `MET`. Two eval cases cover a result held by something other than the
  change and a saving past the changed code's share.

- **A profile-to-family table in `reference/techniques.md` section F.** Each row starts from what a
  profile or trace shows and names the change to try, its counter and the catalog rows that apply.
  Deletion candidates come from reading callers rather than from the profile, and a rescheduled
  change is judged by the wait it removes. `/performance:target` cites
  section F when it names a candidate's mechanism.
- **`/performance:climb`**: a keep-or-revert loop on a frozen harness. Each attempt is one
  hypothesis that names a mechanism, one commit in climb's own worktree on `climb/<goal-slug>`,
  and a fresh measurement of both arms through `ab.sh`. `climb_log.py decide` applies a keep rule
  written before the first attempt; a reverted attempt runs `git reset --keep` to the last kept
  commit, and every attempt is logged to a tab-separated file in the memory slice. The plugin now
  declares `python3` and `git` as required for climb in `prerequisites.json`, and its plugin-level
  eval suite gains three climb cases. The glossary's Hill climbing entry and techniques.md
  section I now point at climb for the loop inside one goal.

### Changed

- `/performance:protect` hands the verified counter to `/review:ratchet` when that skill is among the session's available skills, and skips its own ceilings-file, CI-check and tightening steps. Without it, protect runs those steps itself against `.performance/ratchets.json` as before. The Output block names the ceilings file and which path wrote the ceiling. The plugin declares no dependency on review.
- `/performance:target` hands a captured CPU profile, trace or heap snapshot to `/debugging:analyze-profile` when the debugging plugin is enabled, and counts its finding as measured evidence in the ranking.
- `/performance:goal` takes an optional `min_attempts` when the work will run as a loop.
  `/performance:snapshot` freezes a harness for a loop only after `discriminate.py` shows it sees a
  known change and the harness prints its failure and work-unit tallies, and its `## Next`
  names `/performance:climb`. `reference/harness-integrity.md` gains rule 8: a frozen harness
  prints its error and work counts.
