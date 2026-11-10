---
bump: patch
---

### Changed

- The burn-rate pacer (`limits.api github-token pace`) now also paces the scheduled ticks of work-unblock's sweep, the monitoring lane and pr-merge's merge and enable-auto-merge sweep jobs. pr-merge's post-merge check and cover dispatch still run on every tick, and no event other than the schedule is ever paced.
