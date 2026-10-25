---
bump: patch
---

### Fixed

- In the merge queue, `ci-status` now applies the trust hold to a queued pull request an automation opened. The step `Fail a queued pull request carrying a hold label` reads its linked issue: its closing issues here, or with none, the one plain `Refs:` issue. The step fails when that issue carries a label containing `untrusted` in any ASCII case, or had one removed by anyone other than a person on the base's trusted-actor list, or through an App. A lanes App pull request that does not link exactly one issue here fails too, so dropping the link after arming does not skip the check; another automation's that links none passes. A removal by a non-human stays in the issue's timeline, so no later label change lifts it; a new issue and a new pull request linking it do. report-outcome's `Hold:` line covers the exact label at PR open, and `enable-auto-merge` covers arm time, so the remaining gap was a label added after the pull request opened. A pull request armed before the label landed no longer merges on it. An unreadable link, label list, timeline or trusted-actor list, a bot author with no numeric id, or a jq error matching them, fails closed. This costs one GraphQL read per queued pull request, plus one timeline read per linked issue and a labels read for a `Refs:` issue when an automation opened it. A person's own pull request is not read.
