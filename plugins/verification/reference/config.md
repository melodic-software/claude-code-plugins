# verification settings

The one key the verification plugin's skills read. It is set per user through the plugin's
`userConfig` option of the same name and per repository in `docs/conventions/verification.yaml`,
validated by [`schemas/verification.schema.json`](../schemas/verification.schema.json). No
`~/.claude` file, `.claude/` file or local overlay sets it. `/verification:setup apply` writes the
repository file after validating it; `/verification:setup check` validates it.

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `proof_level` | `path`, `live`, `strict` | `path` | `/verification:confirm` (Stage 2 step 1) | stricter wins (`path` < `live` < `strict`); the repository value is read from the default branch |

## What each level requires

- **`path`**: the behavior before this setting existed. A live run is required only when a changed
  file matches a runtime-affecting path in `/verification:confirm`.
- **`live`**: any change with a runnable surface is driven in the live app when the app can be
  launched. When it cannot be launched, the change gets the non-UI check from the check-to-change
  table in `skills/confirm/context/outcome.md` (read the stored value back, replay a saved input,
  run the real command), and the report says the app could not be launched.
- **`strict`**: the three proof boxes (unit, live, performance) in
  `skills/confirm/context/outcome.md`, filled per plan phase, or per pull request when the plan has
  no phases. Each box holds evidence or a reasoned not-applicable line that the fresh-context
  verifier checks.

## Resolution

`/verification:confirm` resolves the level once per run, before Stage 2, and never asks the user:
every case below ends in a value, so a pipeline lane that calls the skill unattended gets the same
result as a person.

1. **Default:** `path`.
2. **User option:** `${user_config.proof_level}`, rendered into the skill. A literal, unexpanded
   placeholder means unset. A value other than `path`, `live` or `strict` is named with the option,
   the key and the value, and the layer is dropped.
3. **Repository file:** `proof_level` in `docs/conventions/verification.yaml` as committed on
   origin's default branch, never the working tree or the branch under verification. Root rule
   first: when the repository root (`CLAUDE_PROJECT_DIR`, else `git rev-parse --show-toplevel`) is
   not inside a git working tree, or is `$HOME` or an ancestor of it, skip this layer and say so.
   Otherwise take the default branch name from `git ls-remote --symref origin HEAD` (the part after
   `refs/heads/` on its `ref:` line) and accept it only when it holds letters, digits, `.`, `_`,
   `/` and `-`, has no leading `-` and no `..`; any other name skips the layer, and the report
   quotes the name as data. Then run `git fetch origin <default>`, and from the plugin root
   `node skills/setup/scripts/setup-apply.mjs --check --ref origin/<default> --root "<root>"`.
   Its first line names the commit read; the report carries that commit. When the fetch fails, the
   last fetched copy is read and the report says it may be stale. The reader's result:
   - exit 0 with `INFO ... absent` or `PASS proof_level: (unset)`: the layer is unset.
   - exit 0 with `PASS proof_level: <level>`: the layer sets that level.
   - exit 1: the committed value or the whole committed file is invalid. Each `WARN` line names
     the file, the key and the value (an unlisted word, a capitalized level, an empty value, a
     list, a key set twice, an unknown key, a parse error, a committed symlink). The layer is
     invalid.
   - exit 2 (no `origin/<default>`, a ref that does not resolve) or node not installed: the layer
     cannot be read; skip it and say why.

**Which value wins.** The stricter of the user option and the repository value wins, so either
layer can raise the level and neither can lower the other. A skipped or unset layer takes no part.
An invalid repository value is named and dropped, and the key resolves its default, `path`, not the
user's value (ADR 0054 Decision 7: no valid higher layer remains, and a lower layer's value is
never used). An invalid user option is dropped and the repository value, when valid, still applies.
An invalid value never stops the run.

**A branch cannot lower the level.** A change that adds or edits
`docs/conventions/verification.yaml` on its own branch does not change the level it is verified
at. When the working tree's copy, read with `setup-apply.mjs --check` (no `--ref`), sets a
different level from the default branch's copy, the report names both and says which one applied.

**Report line.** One line before Stage 2 names the level and the layer that supplied it, for example
`proof_level: strict (docs/conventions/verification.yaml at origin/main, commit <sha>)`,
`proof_level: live (userConfig; docs/conventions/verification.yaml at origin/main says path)` or
`proof_level: path (default)`. A dropped or skipped layer is named on the same line with its reason.

**Older releases.** A verification release from before this key has no reader for
`docs/conventions/verification.yaml`, so on that machine a repository's `live` or `strict` silently
weakens to the `path` rule. Upgrade every member before setting a repository level; the report line
lets a reviewer see a run that lacks it.
