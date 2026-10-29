---
bump: patch
---

### Fixed

- `/harness-ops:plugins` sync: the report is easier to read. It opens with a one-line `Result:` verdict: `<N> item(s) under Action needed`, `changes applied, nothing under Action needed`, or `clean, nothing changed and nothing under Action needed`, and in audit `see the predictions below, nothing under Action needed` or `no change predicted, a lower bound against the unrefreshed catalog`. Each line now carries one fact. The `Divergences:` row, the `Timing:` rows, the cache-content tally and the source-checkout row put each part on its own indented line, and a list of more than three ids puts one id per line. Each remedy is a `remedy:` line under the fact it fixes instead of being joined to it with `;`.
- The render no longer prints the explanatory paragraphs under stale project records and user-home project records on every run, and no longer breaks sentences at fixed columns. The reasons stay in `context/stale-records-cache-content.md` and `context/scope-semantics.md`. Version moves and the `Catalog regression:` interval read `->` in plain ASCII.
- The messages the report quotes from the scripts no longer join two facts with `;`: `fleet-state.sh` labels a lagging linked-worktree record `update ineffective, uninstall clears it`, and the refresh-failure, cache-content fallback and divergence-split notes read as one sentence each.
