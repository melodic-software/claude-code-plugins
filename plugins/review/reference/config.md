# review settings

The review plugin's keys, one row each, with the skill that reads each one. A key is set per
user through the plugin's `userConfig` option of the same name and per repository in
`docs/conventions/review.yaml`, validated by
[`schemas/review.schema.json`](../schemas/review.schema.json). No `~/.claude` file, `.claude/`
file or personal override sets these keys. `/review:setup apply` writes the repository file.

| Key | Values | Default | Reader |
|---|---|---|---|
| `downstream_probe` | `run`, `report` | `run` | `/review:quality-gate` downstream mode (Step 2): `run` writes the safety-fact probe in a temporary directory outside the tree and runs it; `report` states the probe without running it. Level rule: policy floor, `report` in any layer wins; the repository value is read from the default branch |
| `fanout_diversity` | `lens`, `model`, `codex` | `lens` | `/review:fanout` run-everything steps 3 and 5 and its fallback: `lens` runs one reviewer agent per concern; `model` sends one review prompt to each distinct fan-out model tier of the role map; `codex` runs the surfaces `lens` runs, with no model tiers, and reports the Codex reviewer as the model-diversity panel in a `panel:` line, `skipped` when Codex is absent. Level rule: later layer; the repository layer is skipped when the reviewed change set edits `docs/conventions/review.yaml` |
| `fanout_act_on_cap` | a whole number, at least `1` | `2` | `/review:fanout` Step 2, both review modes: the report's `## By axis` marks the first this many rows under `### Spec`, and separately the first this many under `### Standards`, `yes` in their `Act on` cell, and every later row `no`; a row listed under `## Dismissed` reads `no` and is not counted; no row is dropped. The default `2` is the smallest cap that kept both planted defects of the two-defect fixtures inside act on in 12 of 12 runs, where a cap of `1` left the second outside it in all 12 (#12505). A user option that is not a whole number of at least 1 is an invalid layer. Level rule: later layer; the repository layer is skipped when the reviewed change set edits `docs/conventions/review.yaml` |
| `smell_baseline` | `default`, `off`, or a repository-relative path to a `.md` file | `default` | the `code-reviewer` agent's design-smell check: `default` reads the "Baseline" section of [`design-smells.md`](design-smells.md); `off` checks no smells; a path reads the repository's own list, and a missing file, or one the reviewed change set edits, falls back to the shipped baseline, never to `off`. Level rule: later layer; the repository layer is skipped when the reviewed change set edits `docs/conventions/review.yaml` |
| `council_lanes` | `on`, `off` | `off` | `/review:council`: an unattended run stops with success unless this is `on`; an attended run never reads it. Repository layer only, no user option. Read as the council keys below are |
| `council_max_rounds` | a whole number, at least `1` | `1` | `/review:council` round loop: above `1`, `/review:fanout fix` runs between rounds. Level rule: later layer; council read rule below |
| `council_scores` | `on`, `off` | `off` | `/review:council` report: `on` adds a mark table by member and round; marks gate nothing. Level rule: later layer; council read rule below |
| `council_members` | a map of member id to `provider`, `model`, `brief`, `effort` | three `claude` members on `opus`, briefed `correctness`, `design`, `adversarial` | `/review:council` selection. The user option holds the same shape as JSON text. Level rule: later layer per key; council read rule below |
| `council_panel` | a list of member ids | every catalog member | `/review:council` when no rule matches. User option: JSON text. Level rule: later layer; council read rule below |
| `council_rules` | a list of `name`, `when` (`paths`, `size`, `risk`), `members` | none | `/review:council` selection, first match wins. User option: JSON text. Level rule: later layer; council read rule below |

**Council read rule.** When the reviewed change set edits `docs/conventions/review.yaml`
(committed, staged, unstaged or untracked), every council key is read from the base branch's
committed copy, never the working tree, through the same ladder as `downstream_probe`: fetch the
base, else read the last fetched copy and say so, else skip the repository layer and say why. A
change therefore never chooses its own reviewers or turns its own lane switch on. `/review:council`
checks the user layer's JSON text against the same schema; an invalid option is reported and
dropped for that key.

## Resolution

A skill resolves each key lowest layer first, and the later layer wins:

1. The default in the table above.
2. The user's option, rendered into the skill as `${user_config.<key>}`. A literal, unexpanded
   placeholder means the option is unset. A user value equal to the default reads as the default,
   since the two cannot be told apart.
3. The key in the repository's `docs/conventions/review.yaml`, read with
   `skills/setup/scripts/setup-apply.mjs --check`, which validates the whole file against the
   schema. A missing file or key leaves this layer unset; a key that is present but invalid (an
   empty value, `null`, an empty quoted string, a list such as `[]`) is an invalid layer, not an unset
   one. A WARN on one key's value (including a key set twice under names that differ only by
   surrounding spaces) makes this layer invalid for that key only: the reader exits 1 and still
   prints a PASS line for every other key, which this layer then sets. A key the schema does not
   list is one WARN and is ignored the same way, so a valid `downstream_probe` floor beside it
   still counts. Any whole-file problem prints no PASS line, and the layer is dropped for every
   key: a parse error (a key written the same way twice is one), an unknown key set twice or
   holding a map or list, or a refusal of the file itself (a symlink, a hard link, a path
   that resolves outside the repository, a target that is not a regular file, a file that cannot
   be read, or a committed entry that is not a regular file).

The skill reports one line naming the resolved value and the layer that supplied it, for example
`fanout_diversity: model (docs/conventions/review.yaml)`. A value outside the key's values in either
layer, or a repository file the reader cannot parse, is named with its file or option, the key and
the value, and that layer is dropped: a valid higher layer still wins, otherwise the key's default,
never a lower layer's value (ADR 0064 Decision 7). The run continues either way.

**Policy floor: `downstream_probe`.** This key does not take the later layer. `report` from any
valid layer wins over `run` from the other, so the user option can only tighten the repository
value and the repository file can only tighten the user value. An invalid layer is dropped and
counts as absent; the other layer still applies, and with neither saying `report` the key resolves
`run`. The repository value is read from the default branch's committed copy, never the working
tree: the skill checks the default branch name from `git ls-remote` against the reader's
`--ref` charset (letters, digits, `.`, `_`, `/`, `-`; no leading `-`, no `..`), skipping the layer
on any other name, runs `git fetch origin <default>`, then
`setup-apply.mjs --check --ref origin/<default>`, and reports the commit it read. A pull request
that adds or changes `docs/conventions/review.yaml` on its head therefore cannot switch its own
probe on. When the fetch fails, the last fetched `origin/<default>` is read and the report says so;
when no `origin/<default>` exists, the repository layer is skipped and the report says why.

**Root rule.** The repository file is read only when the repository root (`CLAUDE_PROJECT_DIR`,
else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an
ancestor of it. Otherwise the repository layer is skipped and the report line says why.

**Older releases.** A plugin release without a key has no option for it, and its schema does not
list the key, so its reader reports the repository key as unknown. A reader that ignores an
unknown key keeps the file's other keys; an older reader drops the whole repository layer, and
each key then resolves as it does for an invalid layer: `fanout_diversity` and
`fanout_act_on_cap` take their defaults,
never the lower userConfig value, and `downstream_probe` still takes `report` from userConfig. A
key holding a map or a list, as `council_members`, `council_panel` and `council_rules` do, makes an
older reader drop the whole repository layer, not just that key: every other key in the file falls
back too. A repository shared with users on an older release should add a key only once they have
updated.
