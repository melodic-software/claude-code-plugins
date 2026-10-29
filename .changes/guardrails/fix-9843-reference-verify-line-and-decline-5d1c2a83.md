---
bump: patch
---

### Fixed

- The `reference-verify` pre-push entry reports each finding at the line that holds the flag, path or skill reference it names. Before, every finding in a file carried the file's first added line, which for a new file was line 1. When no line the push adds holds that text, the finding falls back to the first added line.
- A declined `reference-verify` entry (`checks.guardrails.reference-verify.declined`, else `checks.git-hooks.declined`, read the way `install.mjs` reads them) now exits 0 without checking, including when the plugin's lefthook remote runs it from the fetched copy. Before, declining removed only the registrations the installer wrote, so a lefthook-remote consumer kept running the check.
