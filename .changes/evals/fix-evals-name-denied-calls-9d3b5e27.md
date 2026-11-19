---
bump: patch
---

### Fixed

- `run-validity.py`'s INVALID verdict now names each permission denial it counted: the tool and its target (a path, a command or the denied hosts), redacted with the vendored gitleaks redactor, flattened to one line and cut to 120 characters. A call repeated across runs is named once with its count, and at most 10 calls are named. Without a loadable redactor it names only the tools. The eval workflows keep only the verdict line, so a hosted run's `validity.txt` and step summary now show which calls were denied. The plugin now carries a generated copy of `lib/redact.py` and the vendored gitleaks rules.
