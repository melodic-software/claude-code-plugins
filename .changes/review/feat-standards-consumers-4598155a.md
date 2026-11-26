---
bump: minor
---

### Added

- quality-gate's self mode resolves the standards the change's surfaces match through the standards contract's Resolution ladder, as criteria mode does, subscribed layers included, and hands them to its reviewer. `/review:code-review` and self mode follow the contract's new "Adopted shipped concepts" rule (standards contract 1.3.1), with `/engineering-concepts:lookup` (if enabled).

### Fixed

- The `architecture-guardian` and `security-reviewer` agents open a `REVIEW.md` citation only from `scripts/org-standards.sh citations`, never by splitting a citation and reading its path themselves, and read standards through the Resolution ladder, personal subscriptions included.
- `/review:code-review` opens a criteria citation only from the `ORG STANDARDS:` folder's `citations.tsv` when it has one, the organization's and the repository's citations alike, and reads its `docs/standards/README.md` as the printed index; a folder without `citations.tsv` is still read as the raw org checkout.
