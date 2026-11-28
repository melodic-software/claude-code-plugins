---
bump: patch
---

### Fixed

- **An unattended `/architecture:improve deepening` run writes the candidate file once, `security-defect: withheld` lines included.** It no longer adds a placeholder afterwards with Edit or a shell command, and it reports the number of placeholder lines it actually wrote. In 2 of 10 eval runs the reply counted one withheld line that no Write of the file carried ([#17196](https://github.com/melodic-software/claude-code-plugins/issues/17196)).
