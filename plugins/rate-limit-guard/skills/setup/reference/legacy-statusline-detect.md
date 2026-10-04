<!-- GENERATED from lib/legacy-statusline-detect.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# Retired statusline tee: detection

The shared, plugin-name-free half of the two statusline guard plugins' check for a retired tee
still running beside the mod. The hub SKILL.md supplies `<guard>` (this plugin's name) and
`<plugin-root>` (the installed version directory this skill runs from). Every path below is machine
scope. `<config>` is `${CLAUDE_CONFIG_DIR:-~/.claude}`, and `<plugins>` is `<config>/plugins`
unless `CLAUDE_CODE_PLUGIN_CACHE_DIR` moves it. Cached plugin versions sit under
`<plugins>/cache/<marketplace>/<guard>/<version>/`.

- **Pointer**: when the plugins root, its override variable or the cache layout is in question, fetch <https://code.claude.com/docs/en/plugins/loading#find-plugins-on-disk> live.
- **As of**: 2026-10-03 (Claude Code 2.1.288)
- **Recheck trigger**: that section renames the override variable, changes the cache path layout,
  or moves.

The guard's mod now writes the snapshot files. Before the mod, a statusline tee wrote them, and a
tee that still runs is a second writer of the same files. The steps to remove one are in
`unwrap-before-compose.md` beside this file.

## 1. Is a tee still running?

The mod writes none of the tee's stamp files, so a stamp written after this version was installed
came from a tee. The stamps, per guard:

| Guard | Stamp files under `<config>/<guard>/` |
|---|---|
| rate-limit-guard | `.last-write`, `spool/.last-drain` |
| context-guard | `context/.<session-id>.json.last`, one per session |

Read the install record for this version: the entry under `<guard>@<marketplace>` in
`<plugins>/installed_plugins.json` whose `installPath` is `<plugin-root>`, and its `lastUpdated`.

- **A stamp newer than that `lastUpdated`.** FAIL: a tee is running. Quote the stamp's path and
  modification time beside the `lastUpdated` value. A stamp that advances again a minute later
  confirms it.
- **Stamps present, all older.** INFO: files the retired tee left behind. No tee runs; the unwire
  steps delete them.
- **No stamps.** PASS for this step.
- **No install record names `<plugin-root>`, or it has no `lastUpdated`.** INFO: the comparison
  cannot run. Report the stamps' modification times and continue with steps 2 and 3.

The record fields this step reads:

- `scope` and `installPath` are documented.
  - **Pointer**: when the install record's documented fields are in question, fetch <https://code.claude.com/docs/en/plugins/loading#check-which-stage-a-plugin-reached> live.
  - **As of**: 2026-10-03
  - **Recheck trigger**: that section changes the fields it lists, or moves.
- `lastUpdated` and `projectPath` are not documented. They were observed in
  `installed_plugins.json` on Claude Code 2.1.288 on 2026-10-03: `lastUpdated` is an ISO timestamp
  on every record, and `projectPath` names the project on a `project`-scope record.
  - **Pointer**: when either field is missing or renamed, read a live `installed_plugins.json` and
    re-derive the comparison; no docs page covers these fields as of 2026-10-03.
  - **As of**: 2026-10-03
  - **Recheck trigger**: a Claude Code release that changes `installed_plugins.json`, or a docs page
    starting to cover these fields.

## 2. Which cached versions still carry a tee?

List every version directory under `<plugins>/cache/<marketplace>/<guard>/*/` that holds
`scripts/statusline-tee.sh` and has no `.orphaned_at` marker. Each one is a tee a shim or a
wrapper script can still pick. For each, report:

- the version (the directory name);
- every install record whose `installPath` is that directory, with its `scope`, and its
  `projectPath` when the scope is `project`;
- "no install record" when none names it.

A `project`-scope record pinned to such a version keeps that version, and its tee, installed for
that project. Report it as the reason the tee is still on disk; updating or uninstalling that
project's install is the person's call.

A directory that carries `.orphaned_at` is skipped: Claude Code has marked it superseded and
removes it later.

- **Pointer**: when the orphan marker or its cleanup window is in question, fetch <https://code.claude.com/docs/en/plugins/loading#cleanup-of-previous-versions> live.
- **As of**: 2026-10-03 (Claude Code 2.1.288)
- **Recheck trigger**: that section renames the marker, changes the cleanup, or moves.

## 3. How is it wired?

A running tee is reached by one of three routes. Check all three, because each hides the tee from
the others' check:

1. **The `statusLine` string.** A `statusLine.command` in any settings scope that names
   `statusline-shim.sh` or `statusline-tee.sh`. Report the scope and file. The string may hold
   the shim inside one `sh -c` layer.
2. **A wrapper script.** The `statusLine` command runs a script (for example a dotfiles status line
   entrypoint) that globs `<plugins>/cache/*/<guard>/*/scripts/statusline-tee.sh` for the newest
   tee, or runs a shim. Read the script the command names and report the lines that name
   `statusline-tee` or `statusline-shim`. Such a script often skips no orphan marker, so it keeps
   picking an old cached tee. Report whether the script is managed by chezmoi or another dotfiles
   tool, because the edit belongs in its source.
3. **An installed shim copy.** `<config>/<guard>/bin/statusline-shim.sh` exists. Report it even
   when no route above names it: a later wiring edit can reach it again.

A FAIL in step 1 with no route found here still means a tee runs: say that no route was
identified, never that the stamps are stale.
