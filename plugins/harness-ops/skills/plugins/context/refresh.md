# Refresh: re-fetch the user-scope fleet with its configuration unchanged

`<skill-dir>/scripts/reset-refresh.sh` is an operator-run script. The skill does not run it in a
session, because it refuses to run while a `claude` process is running. Run it yourself from a
terminal after every Claude Code session on the machine is closed:

```bash
bash "<skill-dir>/scripts/reset-refresh.sh" preview
bash "<skill-dir>/scripts/reset-refresh.sh" refresh [--journal-root <dir>]
```

## What each mode does

- **`preview`** makes no changes and calls no CLI. It prints the count and size of each known
  marketplace's clone under `~/.claude/plugins/marketplaces/`, the entry count, `temp_git_*` count
  and size of `~/.claude/plugins/cache/`, and how many user-scope ids `refresh` would reinstall. It
  also counts the ids with a project or local record, whose cache moves but which `refresh` does
  not reinstall.
- **`refresh`** moves those clones and `cache/` into a run directory, then runs
  `claude plugin marketplace update <name>` for each marketplace in `known_marketplaces.json`. It
  then runs `claude plugin install <id> --scope user` for each user-scope install record, one at a
  time. It keeps `installed_plugins.json`, `known_marketplaces.json`, `data/` and every settings
  file, and never writes any of them itself.

## Safeguards

- **Refusals.** `refresh` exits 2 before it touches anything in these cases:
  - `CLAUDE_CODE_REMOTE` is set.
  - `pgrep -x claude` finds a process named `claude`. A session started under a different process
    name (for example `node`) is not seen, so close every session first.
  - `pgrep` is missing or fails, since a session then cannot be ruled out.
  - `installed_plugins.json`, `known_marketplaces.json` or user `settings.json` is not valid JSON.
    An unreadable file would snapshot as empty before and after and compare equal.
- **Run directory outside the plugins tree.** The journal root defaults to
  `~/.claude/plugins-refresh` and is refused when it resolves inside `~/.claude/plugins`. The script
  copies itself into the run directory and runs the copy, because the installed script lives in
  the cache it moves aside.
- **Nothing is deleted.** The old cache and clones stay in `<run_dir>/moved/` until you remove the
  run directory yourself. When a run ends in exit 1, it prints how to go back: replace
  `~/.claude/plugins/cache` with `<run_dir>/moved/cache`, and each
  `~/.claude/plugins/marketplaces/<name>` with `<run_dir>/moved/marketplaces/<name>`.
- **User scope only.** Project and local records are not reinstalled, because a reinstall there
  would write another repository's settings. Their cache content moves aside with the rest, so such
  a plugin does not load until it is reinstalled from its project or its directory is moved back
  from `moved/cache/`. A record whose project path is gone is left in place, since the path may be
  an unmounted volume. `@builtin` ids are left out of the reinstall set.
- **Snapshot comparison.** Before moving anything, `refresh` saves three snapshots to the run
  directory:
  - each marketplace's name, full `source` and `autoUpdate`
  - the user-scope install records (id and scope)
  - user `enabledPlugins`

  After the reinstall it saves them again. Each is sorted JSON, so a key or marketplace the CLI
  reorders is not a difference. Any difference, or any CLI call that failed, exits 1.
  `<run_dir>/journal.log` holds every CLI call and its output.
- **What the snapshots leave out.** The marketplaces are refreshed before the installs, so a
  reinstall can land a newer version. The install snapshot holds id and scope only, so a newer
  version is not a difference.

## Enable state after a reinstall

On a recorded id, an install turns a `false` in user `enabledPlugins` into `true`. So after the
installs, `refresh` compares each reinstalled id's value with the snapshot. It runs
`claude plugin disable <id> --scope user` (or `enable`) only for an id the install changed. A key
the install added where the snapshot had none cannot be removed through the CLI, so it is reported
as a difference and not repaired.

The CLI exits 1 for a plugin already in the target state, with output that contains `already
enabled` or `already disabled`. `refresh` treats that output as success. The snapshot comparison is the check
that the state came back, never the exit of `enable`: `enable` also succeeds for an id that is not
installed.

## Probe record

The script's behavior rests on a probe run against an isolated `HOME`.

- **Ran**: Claude Code 2.1.314 by absolute path, under `env -i HOME=<empty dir>`. One HOME had a
  local-directory fixture marketplace. The other had a git-cloned public marketplace, since a
  directory marketplace has no clone to lose and a local `file://` git URL is refused as a source.
- **`install <id>` on a recorded, enabled id with the cache present**: prints `already installed
  (scope: user)`, exits 0, and leaves `settings.json` byte-identical.
- **`install <id>` on a recorded, disabled id**: succeeds and flips `enabledPlugins["<id>"]` from
  `false` to `true`.
- **`install <id>` after `rm -rf plugins/cache`**: exits 0 and recreates
  `cache/<marketplace>/<plugin>/<version>`. Install records and `enabledPlugins` are unchanged.
- **`marketplace update [<name>]` with the clone deleted**: re-clones it and exits 0.
  `known_marketplaces.json` changes only in `lastUpdated`, which the snapshot leaves out.
- **Key order**: after the cycle, `settings.json` was equal by sorted content, but the CLI had
  moved `enabledPlugins` ahead of `extraKnownMarketplaces`. A byte compare of a real settings file
  can therefore fail where the sorted compare passes. `reset-refresh.test.sh` uses a stub CLI that
  keeps the order, and asserts the fixture settings file byte-identical.
- **As of**: 2026-10-30.
- **Recheck trigger**: a Claude Code release that changes what `plugin install` writes to
  `enabledPlugins` for a recorded id, or how `marketplace update` treats a missing clone.

The documented CLI behavior the script relies on is in the
[Plugin commands reference](https://code.claude.com/docs/en/plugins/cli-reference.md): `install`
and `disable` take `--scope user`, an already-installed id prints `already installed` and exits 0,
`enable` and `disable` on a plugin already in that state exit 1, and `marketplace update [name]`
refreshes one marketplace or every one. Read 2026-10-30.
