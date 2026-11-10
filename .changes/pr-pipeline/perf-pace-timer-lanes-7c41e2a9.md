---
bump: patch
---

### Changed

- The burn-rate pacer (`limits.api github-token pace`) now also paces the scheduled ticks of work-unblock's sweep and pr-merge's merge and enable-auto-merge sweep jobs. pr-merge's post-merge check and cover dispatch still run on every tick, and no event other than the schedule is ever paced.
- The pacer paces a scheduled tick only when the previous scheduled run of the same workflow did its work, in place of even run numbers, which other events also advance. Two scheduled ticks in a row are never both paced, so work-unblock's full sweeps stay inside its three-hour close window.
