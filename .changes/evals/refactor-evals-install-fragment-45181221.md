---
bump: patch
---

### Added

- **`install_command` grader fragment.** The shared matchers now hold one list of package and tool install commands, with must-pass and must-fail samples, and every `no-install` grader in this repository builds from it instead of carrying its own copy.
