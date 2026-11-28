---
bump: major
---

### Changed

- Standards contract 2.0.0: the concern file is `docs/conventions/standards.yaml` (keys `standards_dir`, `guidance_dir`, `standards_repositories`); a repository with only `.claude/standards.yaml` is told it moved, and the old file is not read.
- Subscription entries take `surfaces` in place of `topics`, which is reported and skipped.
- `scripts/org-standards.sh` gains a `guidance` command that prints the org layer's printed guidance index, and each `subscriptions` line gains a fourth field, the layer's printed guidance index or `-`. Team and repository source lists are read when their repository's owner is in `trusted_owners`, the repository list from its default branch only.
- Skills read guidance through the contract's "Guidance layer (every rung)" paragraph, as advice below every standard, in place of the engineering-concepts lookup.
