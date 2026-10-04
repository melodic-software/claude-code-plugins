# Retired statusline tee: unwire steps

The shared, plugin-name-free half of the two statusline guard plugins' steps for removing a retired
tee. The hub SKILL.md supplies `<guard>`; `<config>` is `${CLAUDE_CONFIG_DIR:-~/.claude}`. Run
these after `legacy-statusline-detect.md` beside this file found a tee running, a route still
wired, or files the tee left behind.

The skill prints these steps for the person to run. It never edits a settings file, a script or
the plugin cache itself.

## 1. The `statusLine` edit

Print the current `statusLine.command` and the value with every guard shim removed, and name the
settings file it lives in. The person's own renderer stays byte for byte.

- A **shim pair** is the word `bash` followed by one word, quoted or not, whose path ends in
  `/bin/statusline-shim.sh`. A **tee pair** is the word `bash` followed by one word, quoted or not, whose path ends in
  `/scripts/statusline-tee.sh`. Remove each pair and the one space after it, and nothing else.
- Look inside one `sh -c '<string>'` layer too: remove a pair at the start of the quoted string,
  and keep the layer, its quotes and its escapes as they are.
- Never remove an `sh -c` layer itself. An adapter an earlier setup generated and the person's own
  `sh -c` renderer have the same shape, so the value left behind is kept as it is. A leftover
  adapter still runs the renderer.
- Remove both guards' pairs. Both tees retired in the same release, so a sibling's shim is as stale
  as this plugin's.
- When nothing remains, the edit removes the `statusLine` key. Otherwise only `command` changes,
  and every other key in the object stays.

Examples, with `CG` for `bash ~/.claude/context-guard/bin/statusline-shim.sh` and `RLG` for
`bash ~/.claude/rate-limit-guard/bin/statusline-shim.sh`:

| Current `statusLine.command` | After the edit |
|---|---|
| `CG RLG ~/.claude/statusline/render.sh` | `~/.claude/statusline/render.sh` |
| `CG sh -c 'ulimit -n'` | `sh -c 'ulimit -n'` (the person's own `sh -c`, kept) |
| `CG sh -c 'RLG my-renderer --format '\''a b'\'''` | `sh -c 'my-renderer --format '\''a b'\'''` |
| `CG` | remove the `statusLine` key |

## 2. A wrapper script

When the detector found a script that runs a tee or a shim (for example a dotfiles status line
entrypoint), print the lines to remove and the file to edit. A file managed by chezmoi or another
dotfiles tool is edited at its source (for chezmoi, the file `chezmoi source-path <target>` names),
then applied; an edit to the target alone is overwritten at the next apply.

## 3. Files to delete

Print the delete commands for the guard's files the tee owned:

- the installed shim copy, `<config>/<guard>/bin/statusline-shim.sh`, and its `bin/` directory when
  empty;
- `<config>/<guard>/.statusline-tee-path`;
- rate-limit-guard: `<config>/rate-limit-guard/.last-write`, `.tee-disabled` and the `spool/`
  directory;
- context-guard: every `<config>/context-guard/context/.*.json.last`.

Never delete the snapshot files the mod writes (`rate-limits.json`, `context/<session-id>.json`).
Delete the stamps after the edits in steps 1 and 2, so a tee still running cannot write them again.

## 4. Restart

Sessions and lanes started before the update keep running what they loaded. Tell the person to
stop and restart them, then re-run the check: step 1 of the detector passes once no stamp is
written again.
