---
bump: patch
---

### Changed

- The burn-rate pacer (`limits.api github-token pace`) now also paces the scheduled ticks of work-unblock's sweep and pr-merge's merge and enable-auto-merge sweep jobs. pr-merge's post-merge check and cover dispatch still run on every tick, and no event other than the schedule is ever paced.
- The pacer paces a scheduled tick only when the previous scheduled run of the same workflow, by run id, marked a clean pass of its work (`Mark this tick's work done`), in place of even run numbers, which other events also advance. A held or red pass and a paced tick skip that step, so two scheduled ticks in a row are never both paced and a held pass is retried on the next tick.
- work-unblock's sweep after a paced run reads back from the clean sweep before it, up to six hours, so a tick dropped or started late after a paced run loses no close.
