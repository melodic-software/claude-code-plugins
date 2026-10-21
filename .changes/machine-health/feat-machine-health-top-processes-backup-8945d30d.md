---
bump: minor
---

### Added

- Two new checks and a report appendix for list items: `top-processes` names what is using the CPU and memory over a sampled window (set by the orchestrator's new `-SampleSeconds`; disk latency is graded only on a sustained window), graded against Microsoft Learn's Windows Server bands and labeled as such; `backup-status` reports whether anything backs the machine up (system image, restore points, File History, Windows Backup, OneDrive Known Folder Move), with restore points and wbadmin read only elevated; and every list-style check's items now appear in the report appendix by title, severity and muted state, never showing a Defender exclusion's value.
