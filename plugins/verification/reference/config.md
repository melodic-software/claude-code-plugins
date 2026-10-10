# verification settings

The keys the verification plugin's skills read. Each is set per user through the plugin's
`userConfig` option of the same name and per repository in `docs/conventions/verification.yaml`,
validated by [`schemas/verification.schema.json`](../schemas/verification.schema.json). No
`~/.claude` file, `.claude/` file or local overlay sets them. `/verification:setup apply` writes the
repository file after validating it; `/verification:setup check` validates it.

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `proof_level` | `path`, `live`, `strict` | `path` | `/verification:confirm` (Stage 2 step 1) | stricter wins (`path` < `live` < `strict`); the repository value is read from the default branch |
| `live_workers` | a whole number, at least `1` | `1` | `/verification:confirm` (Stage 2 step 1) | per user (`userConfig.live_workers`) and per repository (`docs/conventions/verification.yaml`); the later layer wins: repository file over user option over default; the repository value is read from the default branch ([Resolving `live_workers`](#resolving-live_workers)) |

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
   - exit 0 or 1 with `PASS proof_level: <level>`: the layer sets that level. On exit 1 the
     `WARN` lines name another key, such as a bad `live_workers`, and leave `proof_level` valid.
   - exit 1 with no `PASS proof_level` line: the committed `proof_level` or the whole committed
     file is invalid. Each `WARN` line names the file, the key and the value (an unlisted word, a
     capitalized level, an empty value, a list, a key set twice, an unknown key, a parse error, a
     committed symlink). The layer is invalid for `proof_level`.
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

## Resolving `live_workers`

`live_workers` is how many workers share the live drive Stage 2 step 1 runs, split by feature-map
entry point. It decides only how many workers run that drive; `proof_level` still decides whether a
live drive is required. `/verification:confirm` resolves it once per run, beside `proof_level`, and
never asks the user.

1. **Default:** `1`, a single drive, the behavior before this key existed.
2. **User option:** `${user_config.live_workers}`, rendered into the skill. A literal, unexpanded
   placeholder means unset.
3. **Repository file:** `live_workers` in `docs/conventions/verification.yaml`, read from origin's
   default branch by the same `setup-apply.mjs --check --ref origin/<default>` call, root rule and
   branch-name check that read `proof_level` (Resolution above). That call prints
   `PASS live_workers: <n>`, `PASS live_workers: (unset)`, or a `WARN` naming the key and value and
   no `PASS live_workers` line; the value it prints comes through the plugin's
   `lib/parse-concern-value.sh` copy. Exit 2, node missing or a skipped layer leaves this layer
   unread, and the report says why.

**Why the default branch.** The worker count starts processes and app instances on the host, so it
follows the policy the repository has merged, not the branch under verification, and the one
`--check --ref` call already made for `proof_level` reads both keys. A working-tree value takes
effect once it is merged.

**Which value wins.** The ordinary later-layer rule, not the stricter-wins rule of `proof_level`: the
repository value wins over the user option, which wins over the default. A value in either layer
that is not a whole number of at least 1 (`0`, `2.5`, `-1`, a quoted `"2"`, a word) is named with
its file or option, the key and the value, and that layer is dropped: a valid higher layer still
wins, otherwise the key resolves `1`. A lower layer's value is never used in its place, so an
invalid repository value resolves `1` even when the user option is valid (ADR 0054 Decision 7). An
invalid value never stops the run, and an invalid `live_workers` never changes `proof_level`: the
reader still prints `PASS proof_level` for a valid committed level.

**Report line.** The worker line names the count and the layer that supplied it, for example
`live_workers: 3 (docs/conventions/verification.yaml at origin/main, commit <sha>)` or
`live_workers: 1 (default)`, with any dropped layer and its reason.

**Older releases.** A verification release from before this key ignores it and runs one worker.
That is not a floor: nothing weakens, and the report's worker line shows which count ran.
