---
bump: minor
---

### Changed

- `round.sh supersede` and `resolve ... restore` now handle an answered register row with more than an answer (`answer:: ...; note:: ...`, or a row an earlier reconfirm wrote). The superseded row holds the displaced resolution whole in `was named::`, `restore` gives it back byte for byte, and `reconfirm` keeps the displaced answer as `was`, with its note (unless `--note` gives a new one) and its commitments. An earlier reconfirm's proposal and `was` are dropped: the reconfirmed row has room for one of each. Before, such a row was refused and had to be edited by hand.
