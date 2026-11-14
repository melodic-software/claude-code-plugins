---
bump: patch
---

### Changed

- The shipped copy of the plugin-reconfiguration convention, `reference/plugin-reconfiguration.md`, now opens its routes section by saying a reply prints the preferred `claude plugin configure` command in full first and the install `--config` fallback after it, whatever the working directory. Its scope caveat now says `claude plugin configure` has no scope flag and finds only an install visible from the working directory.

### Fixed

- The headless toggle-off eval's `scope-rule` criterion no longer asks the reply to say to run configure from the project the plugin is installed in, which conflicted with the case's home-directory prompt. It now asks the reply to say that configure has no scope flag and finds only an install visible from the working directory, and that the install rerun takes the scope `claude plugin list` reports, because a rerun at another scope adds an install record there. Its pass sample now meets that criterion, and a new fail sample drops the rerun's reason.
