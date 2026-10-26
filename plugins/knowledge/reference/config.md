# knowledge: consumer configuration

The key contract for the repository layer of the `knowledge` plugin. Every key is optional: with
nothing set, each skill runs on the defaults below. The plugin's `userConfig` options (the README's
Options reference) are per-user only and are not keys here.

## Layers

Resolved lowest first; a later layer wins:

| Order | Layer | Where |
|---|---|---|
| 0 | default | the Default column below |
| 1 | team | `<home>/knowledge.yaml`, tracked, validated by [`schemas/knowledge.schema.json`](../schemas/knowledge.schema.json); `<home>` is the convention home bound in the pointer region of `AGENTS.md` or `CLAUDE.md`, else `docs/conventions` |
| 2 | argument | the reading skill's own argument for one run, named in the Keys table |

No `userConfig` option, `~/.claude` file or local overlay sets these keys: a key here places tracked
files, so its value is the repository's. A missing file or key leaves that layer unset, and the
team layer does not apply outside a git working tree or when the root (`CLAUDE_PROJECT_DIR`, else
`git rev-parse --show-toplevel`) is `$HOME` or an ancestor of it. Every run that reads a key
reports the value and the layer that supplied it.

A value outside the key's values in any layer is reported, naming the layer's file (or the
argument), the key and the value, and that layer is dropped: a valid higher layer still wins, and
with none the key resolves to its default; a lower layer's value is never used in its place. The
run never stops on an invalid value.

## Keys

| Key | Values | Default | Argument | Reader and effect |
|---|---|---|---|---|
| `upstream_records_dir` | a repository-relative directory: not absolute, no leading `~`, no `..` segment, inside the working tree | `docs/upstream` | `--out <dir>` | `/knowledge:absorb-upstream` writes its record in this directory. |
