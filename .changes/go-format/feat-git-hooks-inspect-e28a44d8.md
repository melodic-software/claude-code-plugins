---
bump: minor
---

### Added

- `setup check inspect` lists what runs at each git hook stage in the repository, under whichever hook manager it uses (plain hooks, husky, Husky.Net, lefthook, git config hooks, or a hook no manager owns), and times this plugin's own entries that change no files, from their installed copies, on the staged set, a message file or the branch against its upstream. Every other hook is listed as not run, with the reason. The installer's new `inspect` action is read-only.
- The git-hook installer detects Husky.Net (`.husky/task-runner.json`) as husky with `variant: "husky.net"`, so it installs as husky does, and `inspect` lists the Husky.Net tasks a `husky run --group` or `--name` line selects.
- Setup's `husky-config` decision says how to create a new `.husky/<event>` under Husky.Net: with `#!/bin/sh`, executable and staged at mode 100755, since git runs that file directly there and skips one that is not executable.
