---
bump: patch
---

### Changed

- `babysit-prs` merge gate: `--postmerge-result` now reuses the run's shared post-merge answer when the default branch moved or the pull request's base has an older pipeline config, as long as the facts the answer depends on still hold. The base must give the same post-merge floor (read from its own config history when its newest config commit differs), and no merge the check would judge may have landed since the floor beyond those in the answer. When the answer reports no demotion, one REST call lists the issues updated since it was computed, and any issue a demotion-record filer opened, or any known record, refuses it as `demotion-changed`; before this, a record filed during the run went unseen. A new lane merge, a different floor, or an unreadable merge history still makes the pull request read its own. The skip reasons `main-moved` and `config-differs` become `new-merge:#N`, `merged-unreadable`, `merged-history-truncated` and `floor-differs`.
