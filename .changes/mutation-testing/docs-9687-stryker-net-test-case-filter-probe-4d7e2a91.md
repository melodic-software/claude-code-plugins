---
bump: patch
---

### Changed

- **Stryker.NET's `test-case-filter` keeps NoCoverage under `perTest`** ([#9687](https://github.com/melodic-software/claude-code-plugins/issues/9687)). A probe of Stryker.NET 5.0.0 on the `dotnet-test-selection` fixture showed the filter applies in the initial coverage run, so a mutant reached only by excluded tests reports NoCoverage. The `audit/context/tool-test-restriction.md` row now reads `yes` with the version, probe date and recheck trigger, so `audit --exercised` may use Stryker.NET's own restriction. A new "Running Stryker.NET on a test set" section says how: `dotnet-test-selection.sh` output becomes `test-projects` and a `FullyQualifiedName~` `test-case-filter`, written to an untracked copy of the Stryker config beside the original and passed with `--config-file`, so the user's config file is never edited.
