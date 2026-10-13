---
bump: patch
---

### Fixed

- **Native Windows Python no longer makes audits measure nothing ([#6794](https://github.com/melodic-software/claude-code-plugins/issues/6794)).** Its CRLF stdout left a trailing carriage return on every path, glob, exclusion and registry value the dispatcher read back, so files fell into the `other` lane and the run exited 0 having measured nothing, or a configured registry was reported missing. The Python resolver now detects a CRLF interpreter and strips the carriage return before bash reads a line.
