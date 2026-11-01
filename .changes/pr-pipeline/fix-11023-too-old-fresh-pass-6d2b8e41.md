---
bump: minor
---

### Changed

- `verify:too-old` now means a pull request created more than 80 days ago with no counted verdict at its head, and a fresh pass there clears it. The lost-run reconciler re-runs that head's passed `pr-require-checks` run once, recorded, inside GitHub's 30-day re-run window, so pr-verify judges the head. The pr-merge lane no longer closes such a pull request for a fresh attempt; `verify:repeated-fail` still does ([#11023](https://github.com/melodic-software/claude-code-plugins/issues/11023)).
- The convention's "Unsure" rule now says what the lane does: an adjudicator judges an unsure finding, and only a finding at the security tier a person decides, or a thread a person opened or directed, goes to that person.
