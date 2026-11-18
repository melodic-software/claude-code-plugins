---
bump: patch
---

### Changed

- `/improvement:find`'s spoke-path rule no longer explains how Claude Code resolves `${…}` tokens. It says never to pass one from the `context/` files to the Bash tool, and links the plugins reference section on where each variable resolves.
- The CI-health recipe and its trap in the skill body no longer restate GitHub's behavior. They drop the claims that the `/timing` endpoint is being retired, that paging past the result cap returns nothing, and that `actions_list` has no `created` filter. In their place are the recipe's own rules: durations come from run timestamps, each query covers one `created` window, and date windows run only through the REST call. The existing pointers carry the upstream detail.
