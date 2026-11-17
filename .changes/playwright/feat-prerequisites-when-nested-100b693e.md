---
bump: patch
---

### Changed

- The bundled prerequisites checker's `when` also counts a config git tracks anywhere in the project directory's repository, from one `git ls-files` per run, so a repository whose only config sits in a subdirectory gets its probe line. A `config_any` item may now be a path from the repository root with `*`, `?` and `**` wildcards; `..`, `.` and absolute paths are rejected. When git is missing, fails or runs past two seconds, the entry counts as needed.
