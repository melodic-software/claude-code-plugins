# Upstream source: Claude Code releases

What this repository decided about its own components in response to Claude Code releases, and
the problem each decision solves. Nothing here restates a changelog item: upstream owns that text
at `https://code.claude.com/docs/en/changelog.md`, and a copy only drifts.

**Last audited upstream state:** changelog through `2.1.260` (published 2026-09-03), read as raw
markdown on 2026-09-04. Git history of this file records *when*; this line records only *what was
read*. `/claude-ops:changelog status` reads this line; the default range for `diff` and `apply`
runs from it to the newest published release.

**Recheck trigger:** a new release block appears above the version on the line above.

## Corrected

| Decision | Items | Owner surface | Was stated / is true | Record |
|---|---|---|---|---|
| Read/Edit deny over Bash covers redirect targets | 257-052 | `required-permissions.md` | recognized readers only / also redirect targets from 2.1.257 | open |
