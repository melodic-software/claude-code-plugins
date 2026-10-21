# corrections

A Claude Code plugin that turns a recurring correction into a check that
enforces it. A check is only worth recording once it is proven to fail on the
mistake it targets and to pass on the current code.

This first slice ships the proof script. The `/corrections:codify` skill that
uses it is the next slice, so the plugin has no skill yet.

| Script | What it does |
|---|---|
| `scripts/prove-check.sh` | Runs a proposed check in temporary worktrees at two refs and exits 0 only when it fails at the old ref and passes at the new one |

## prove-check

```shell
plugins/corrections/scripts/prove-check.sh --check '<command>' --old <ref> [--new <ref>]
```

Run it from inside the repository the refs belong to. It runs `<command>`
through `bash -c` in a temporary worktree at `<old>`, which must exit
non-zero, and in one at `<new>` (default `HEAD`), which must exit 0. It prints
both exit codes, sends the check's own output to stderr, and removes both
worktrees on every exit path.

| Exit | Meaning |
|---|---|
| 0 | The proof holds: the check fails at `<old>` and passes at `<new>` |
| 1 | The proof fails: the check passes at `<old>`, or fails at `<new>` |
| 2 | Usage or environment error (bad argument, unknown ref, not a repository) |

A check that exits 126 or 127 at `<old>` counts as failing, as any non-zero
exit does, but the script warns on stderr: the command probably did not run.

Run `scripts/prove-check.test.sh` to exercise it against a fixture repository.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install corrections@melodic-software
```

## Configuration

No `userConfig`. No persistent state. No network.
