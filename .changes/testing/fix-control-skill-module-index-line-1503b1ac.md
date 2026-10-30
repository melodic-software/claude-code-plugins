---
bump: patch
---

### Changed

- `/testing:run-e2e` follows a control skill's module index one level down: when a changed file matches a hub line that names a module `README.md`, the run maps the file to the features under that module whose own `## Sub-features` lines match, drives their entry points and refreshes them by their `<module>/<feature>` ids.
