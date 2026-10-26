---
bump: patch
---

### Fixed

- The work-resolve-issue lane stops a run whose change needs a path `apply-issue-patch` refuses at its first write to that path, instead of after the whole run, when the push is refused. The run's file tools and shell redirects are denied `Edit` on each such path. `deny-rules.mjs` builds those rules from `protected-paths.mjs`'s `PATH_RULES` for the `issue` row in `patch-rules.json`, and they match no path that row would push, so a plugin's `settings.json` stays writable. The preamble names the patterns and tells the run to stop with `exit` `stopped` and a `reason` starting `patch-protected-path`. `report-outcome.mjs` then hands the issue back naming `patch-protected-path`, before the run's own words. `apply-issue-patch` still refuses every path itself, including writes the rules do not cover, such as a wrapper subprocess.
