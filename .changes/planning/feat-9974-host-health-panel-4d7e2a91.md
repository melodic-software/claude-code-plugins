---
bump: minor
---

### Added

- The shared interview page gives the owner a Host Health panel, listed in Help and More, which no one else sees ([#9974](https://github.com/melodic-software/claude-code-plugins/issues/9974)). It shows what `share.sh logs --summary` reports for the whole kept log, in the same sections: top errors, refusals, network failures, action latency and rollbacks, reconnect gaps, layout anomalies, INP and LCP, and feature use, rage taps and dead taps by control. It loads when the panel opens and again on Refresh. The panel reads the new owner-only `GET /api/owner/health`, which answers `{summary, sections}`. `logs --summary` now prints its last line, about repeats whose first entry has left the log, after a blank line like the other sections.
