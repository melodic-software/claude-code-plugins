---
bump: minor
---

### Added

- `/work-items:triage` claims each item through the seam with `--phase triage` right before its first write (a comment, label edit, dimension write, edge or close). After its last write it clears its own assignee and releases the claim, so two runs never post conflicting results on one item (#11878). A claim lost to another session (exit 7) skips the item, and the report names it. The attention view, the stale reporter-info listing and the sweep's count take no claim. An outcome that writes to several items, such as an umbrella fold, claims all of them first and writes none when one is lost. A provider with no leases (exit 6) writes unclaimed and says so. The claim's one-hour TTL frees the item soon on a provider with no `release`.

### Changed

- `/work-items:attend-queue` claims a row with `--phase triage`, tells the operator which row it skipped on exit 7, and leaves `[intake]` rows to triage's own claim, since a claim this lane took first would make triage back off from the item.
- The README's multi-agent claim protocol section lists every skill that claims, and says read-only listings never claim.
- New eval cases: `tr-claims-before-triage-write` expects the triage claim before the first item write, and `tr-attention-view-no-claim` expects no claim for the attention view.
