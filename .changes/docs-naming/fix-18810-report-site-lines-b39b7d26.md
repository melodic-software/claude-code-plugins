---
bump: patch
---

### Fixed

- **`audit-file-names` lists each report site.** The emitter printed only the report-site total, so a reply could credit one file with every report site. It now prints one `report` line per report site (file, line, finding id), and the skill lists the sites from those lines and never attaches the total to one file.
