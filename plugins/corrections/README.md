# corrections

A Claude Code plugin that turns a recurring correction into a check that
enforces it. A check is only worth recording once it is proven to fail on the
mistake it targets and to pass on the current code.

| Skill | What it does |
|---|---|
| `/corrections:codify "<description>" [#PR]` | Counts how often the mistake recurs, picks the strongest enforcement-ladder rung, places the lesson by scope, and proposes a check proven with `prove-check.sh` |

`codify` counts at `recurrence.min_occurrences` occurrences (default 2; set it in
`corrections.yaml` in the convention home, default `docs/conventions`, or `corrections.local.yaml`
there for yourself), or at once on a
person's direct "codify this". A person's
invocation writes the proposal; a model invocation only proposes. It asks before installing any
blocking check, and reports a check whose proof did not fail on the old ref and pass on the new one as
unproven.

| Script | What it does |
|---|---|
| `scripts/prove-check.sh` | Runs a proposed check in temporary worktrees at two refs and exits 0 only when it fails at the old ref and passes at the new one |
| `scripts/codify-settings.mjs` | Prints `recurrence.min_occurrences` and the layer that set it, resolved through the config cascade (schema `schemas/corrections.schema.json`) |

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
