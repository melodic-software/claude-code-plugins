# Changelog for the ecosystem-resolution contract

Notable changes to the ecosystem-resolution contract (SemVer). A guardrail change is a major bump.
A new record row or detector signal is a minor bump. A wording change is a patch.

## [1.1.0] - 2026-11-16

The record table's writer for an ecosystem command record names `/toolchain:setup apply
<ecosystem>` as the one writer of `fix-cmd` and `lint-cmd`; a format or lint plugin's setup drafts
those values and sends the person there. python-format joins as a carrier, and the other format
and lint plugins carry the copy ahead of their own setup cuts.

## [1.0.0] - 2026-11-13

Initial contract: the two run kinds and their detector, the seven-step generic resolution text
carriers hold as a synced copy, the recording rule (a merged pull request counts as acceptance for
ecosystem records only), the record table, the carrier rule, and versioning. No plugin carries a
copy yet.
