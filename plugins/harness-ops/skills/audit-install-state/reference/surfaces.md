# What lives in a Claude Code installation directory, and who owns it

This file holds our classification of the paths under `~/.claude`; the engine's runtime copy of it
is `SURFACE_TABLE` in [`scripts/install_state.py`](../scripts/install_state.py). Neither restates
what upstream says each path contains or how long it lives: read that live.

- **Pointer**: when classifying a path, or checking whether a path is swept, kept, or listed at
  all, fetch [claude directory: application data](https://code.claude.com/docs/en/claude-directory#application-data)
  live through the raw markdown endpoint (`.../claude-directory.md`), never a summarizing fetch.
- **As of**: 2026-10-11
- **Recheck trigger**: a release note or docs change naming `cleanupPeriodDays` or a swept or kept
  path, or a path in a real install that the engine reports as `unclassified` while that section
  lists it.

The distinction this file exists to make: **a path Claude Code already manages is not a cleanup
candidate, however old its contents look.** Hand-pruning a swept path fights the product's own
retention sweep and produces churn, not space.

## The retention sweep

`cleanupPeriodDays` governs it. The engine reports the configured value, or the documented default
when the setting is absent, and treats a value the product would reject as a configuration error.

- **Pointer**: when reporting the window, its default or its accepted range, fetch
  [settings reference: cleanupPeriodDays](https://code.claude.com/docs/en/settings-reference#cleanupperioddays)
  live. **As of**: 2026-10-11. **Recheck trigger**: that entry changes its default, minimum, or
  validation.

Four facts about it that change how a finding should be read:

- **A managed source that cannot be parsed is a startup failure, not a silent lack of
  enforcement.** `audit-install-state` reports it as
  `managed-settings-unparsable-refuses-start`.
  - **Pointer**: when a managed source is present but does not parse, fetch
    [managed settings: find entries Claude Code dropped](https://code.claude.com/docs/en/managed-settings#find-entries-claude-code-dropped)
    live for which sources count and what the product does. **As of**: 2026-10-11. **Recheck
    trigger**: that section stops describing a refused start for an unparsable managed source.
- **A user settings file that cannot be parsed can pause the retention sweep.** We treat a JSON
  syntax error in user settings as a retention outage, not only a config error. The engine reports
  it as `error`. It is not the managed-source refusal above.
  - **Pointer**: when a settings error coincides with old swept files, fetch
    [claude directory: cleaned up automatically](https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically)
    live and read its paused-sweep bullet for the pause causes and where the warning shows.
    **As of**: 2026-10-11. **Recheck trigger**: that bullet stops naming an unparsable settings
    file as a pause cause.
- **Managed settings can supply the value**, from a machine-scope path that varies by OS.
  - **Pointer**: when locating the managed file on a host, fetch
    [managed settings: where each mechanism stores the policy](https://code.claude.com/docs/en/managed-settings#where-each-mechanism-stores-the-policy)
    live; that section names each delivery mechanism's location. **As of**: 2026-10-11.
    **Recheck trigger**: that section moves or renames the managed file locations.
- **`.last-cleanup` is an undocumented sentinel the engine reads.** It carries an ISO timestamp
  observed to advance when the sweep runs, and the engine reports its age. No upstream page names
  the file (claude-directory.md, settings-reference.md, monitoring-usage.md, and the CHANGELOG
  through 2.1.268, checked 2026-09-11), so its role carries `observed-undocumented` and its cadence
  is unknown; recheck when claude-directory.md gains a row or the CHANGELOG names it. An advance
  *during* an audit still tells you the tree is not quiesced. `plugins/.last_inuse_sweep` is the
  same kind of sentinel beside the plugin cache.

## Cleaned up automatically (age-swept)

The engine classifies these top-level names under `~/.claude/` as `product-managed-swept`:
`projects`, `file-history`, `plans`, `debug`, `paste-cache`, `image-cache`, `uploads`, `dev-mods`,
`session-env`, `tasks`, `shell-snapshots`, `backups`, `feedback-bundles`, `usage-data`, and the
legacy `todos`, `statsig`, `logs`. The engine keys on the top-level name only, so a swept path
nested under another name takes its parent's classification, and a swept subpath whose parent has
no row (such as `feedback/drafts/`) leaves that parent `unclassified`. Read which nested paths are
swept, and what each path holds, from the pointer at the top of this file.

One firing rule of ours rides on a row: **`image-cache/` sweeps other sessions' directories
whatever their age**, so an old `image-cache/<session>/` disappearing immediately is expected,
never an `age-exceeds-window` signal.

### The unit of retention is not always the file

This is the row most likely to generate a wrong finding, so it gets its own heading.

`older_than_retention` counts files whose **mtime** exceeds the window. That count is a measurement.
The step from it to "the sweep is failing" is an inference, and for several of these paths it is a
wrong one:

- **`file-history/`** retains by checkpoint count, not by age, and keeps some snapshots regardless
  of age. Old mtimes here are the documented behavior, never evidence of a stalled sweep.
- **`projects/<session>/subagents/` and `tool-results/`** are removed *with their parent transcript*.
  A contained file's own mtime is not the unit.
- **`session-env/`, `tasks/`, `debug/`** are per-session. The session directory ages out, not each
  file independently.

For every other swept path the granularity is simply not documented per-file. The engine therefore
emits `age-exceeds-window` with `evidence: inferred` and the sweep unit inline, never a verdict that
reads as a deletion authorization.

- **Pointer**: when stating what `file-history/` retains, fetch its row in
  [claude directory: cleaned up automatically](https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically)
  live. **As of**: 2026-10-11. **Recheck trigger**: that row changes its retention unit.

Absence is evidence only for the legacy directories: `todos/`, `statsig/` and `logs/` missing on an
install old enough to have written them shows the sweep completed, including its
remove-the-empty-directory step. Do not read the absence of any other swept path that way,
`image-cache/` and `feedback-bundles/` included: whether current versions write a path at all is
read from its row, so absence proves nothing about the sweep.

- **Pointer**: when judging whether a swept path's absence means anything, fetch its row in
  [claude directory: cleaned up automatically](https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically)
  live. **As of**: 2026-10-11. **Recheck trigger**: a row there gains or loses a condition on
  when the path is written, or a path joins or leaves the legacy set.

## Kept until you delete them

The engine classifies `history.jsonl`, `stats-cache.json`, `remote-settings.json`,
`policy-limits.json` and `cache/` as `product-managed-kept`: not removed by the age sweep. One of
them has a conditional exception (`history.jsonl` under one configuration), so never state as fact
that a kept path grows forever; read its row first.

- **Pointer**: when judging whether a kept path is ever trimmed, fetch
  [claude directory: kept until you delete them](https://code.claude.com/docs/en/claude-directory#kept-until-you-delete-them)
  live. **As of**: 2026-10-11. **Recheck trigger**: a row gains or loses a trimming exception.

Upstream also lists state files to keep that no table names, and the engine classifies them:
`.credentials.json` and `daemon/` as `secret`, `agent-memory/` as `authored`, and `jobs/` as
`product-managed-kept`. Any other file the tables do not name is `unclassified`, never a license to
delete. See "unclassified" below.

- **Pointer**: when deciding whether an unlisted file is safe to remove, fetch
  [claude directory: state files to keep](https://code.claude.com/docs/en/claude-directory#state-files-to-keep)
  live. **As of**: 2026-10-11. **Recheck trigger**: that list gains or drops an entry.

## Session-scoped, explicitly not age-swept

`sessions/` holds one small file per running session, which Claude Code manages itself.
**Hand-deleting these confuses concurrent-session detection.**

They also churn during an audit. A file present in one listing and gone in the next is the
documented behavior, not a discrepancy, and it means any orphan count keyed on sessions carries a
margin of error, because a session whose record vanished mid-run is *unknown*, not *dead*.

- **Pointer**: when explaining `sessions/` lifetime, fetch its bullet under
  [claude directory: cleaned up automatically](https://code.claude.com/docs/en/claude-directory#cleaned-up-automatically)
  live. **As of**: 2026-10-11. **Recheck trigger**: `sessions/` joins the age sweep.

## Never delete

We never route `~/.claude.json`, `~/.claude/settings.json`, or `~/.claude/plugins/` to deletion.

- **Pointer**: when a user asks whether one of these may go, fetch
  [claude directory: clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data)
  live; its closing paragraph names the files never to delete. **As of**: 2026-10-11. **Recheck
  trigger**: that paragraph adds or drops a file.

## Home-root state, outside the swept tree

`~/.claude.json` lives in the home directory, **not** under `~/.claude`, and is not touched by the
retention sweep at any value of `cleanupPeriodDays`. We route its growth to `claude purge <path>`
everywhere, never to its old name `claude project purge`; what it removes and how it confirms are
in the pointer below.

- **Pointer**: when routing a user to the purge command or checking its flags, fetch
  [CLI reference: CLI commands](https://code.claude.com/docs/en/cli-reference#cli-commands) and
  [claude directory: clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: the cli-reference stops listing `claude purge`, or the claude-directory
  section changes what it says about the old name.
- **Docs lag**: whether the old name still works, between the
  [changelog 2.1.288](https://code.claude.com/docs/en/changelog#2-1-288) and
  [claude directory: clear local data](https://code.claude.com/docs/en/claude-directory#clear-local-data).

`.claude.json.tmp.<n>.<hash>` siblings are failed atomic-write remnants. The leading number *looks*
like a PID; that has not been verified, so the engine attempts no liveness lookup on it.

## Stale sandbox mask files

A killed session can leave sandbox mask files, and `/doctor` is the surface that warns about
them. The location is not documented, so this inventory does not add a path pattern for them. The
class is nominated to the `doctor` / `audit-install-state` overlap candidate. No store row is
written here.

- **Pointer**: when relaying what `/doctor` checks for here, fetch
  [changelog 2.1.257](https://code.claude.com/docs/en/changelog#2-1-257) live.
- **As of**: 2026-10-11
- **Recheck trigger**: a doc page names the mask-file directory, or `/doctor` stops warning about
  them.

## Unclassified: everything the tables do not name

The largest population in a real install is state deposited by **plugins**, including sibling
plugins from the same marketplace. The engine inventories these by name, size, and mtime and stops
there:

- it never parses their contents, since a plugin owns its own state;
- it never attributes an owner from a directory name;
- it never infers that "not product-managed" means "disposable."

`unclassified-report-only` is a statement about the *evidence*, not about the file. There is no
upstream row, so no retention claim can be made in either direction.

## Secret-bearing paths: never opened

`.credentials.json`, `daemon/control.key`, `daemon/pipe.key`, `ide/*.lock` (the body carries an
`authToken`), and the values inside `~/.claude.json` (MCP server configs can carry tokens). These
appear in the inventory as name/size/mtime line-items only. The rule is enforced in the reader, not
at each call site, so a future check cannot reach one by forgetting to consult the list.
