---
bump: patch
---

### Fixed

- `pr-unblock-dispatch.yml` releases a `review-dependency` head the usage limit stopped once that limit resets, as it does for `resolve-conflicts`, and stops re-dispatching the head after `limits.limit-stops-per-head` limit stops. Before, a limit stop held the head until the next push, and the dispatch record could store it as reviewed. The dispatcher now reads the base's resolved limits and its clock for `review-dependency` too ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382), [#9379](https://github.com/melodic-software/claude-code-plugins/pull/9379)).
- The dispatch record's version is now 3, so `pr-unblock-dispatch.yml` and `pr-feedback-dispatch.yml` read a record cached under the old rule as empty. Such a record could hold a limit-stopped `review-dependency` head as reviewed, past its reset. The cost is one pass of re-reads, never an extra dispatch ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382)).
- The lane catalog's trigger gate check covers `issue_comment`: a job that holds a Claude credential under it must show an author or same-repo gate, and `lane-funding.schema.json` requires a `gate` for a lane with that trigger ([#9382](https://github.com/melodic-software/claude-code-plugins/issues/9382), [#9380](https://github.com/melodic-software/claude-code-plugins/pull/9380)).
