---
bump: patch
---

### Changed

- A reuse PR from `work-resolve-issue` no longer carries `Hold: a human merges this` on every PR. It holds on the same conditions as a `done` run's PR, through one `mustHold` check in `report-outcome.mjs` that both paths call, and now reads `merge: human` on a reuse too. It also holds when the compare failed, when the runner's checks for the tip are missing or did not all pass, or when the new reuse leak scan is missing or not clean. This supersedes the fixed hold from [#7831](https://github.com/melodic-software/claude-code-plugins/pull/7831).
- `run-checks` scans a reused branch before its checks run. It uses the read runner's own leak scan on the diff from the branch's merge base with the default branch tip and on every file that diff makes. The result goes into the checks record as `scan`.
- The read runner's leak-scan passes now live in `lib/publish-gate.mjs` (`scanLeak`, `deeperLeak`, `changedBytes`): per-line classification, the UTF-16LE pass, the split-line pass and the scan of the files a patch makes. The scan job calls them from the gate it already loads at the default branch tip, so both scans run one copy of the code. Behavior is unchanged.
