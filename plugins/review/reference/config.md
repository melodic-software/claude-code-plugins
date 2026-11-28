# review settings

The review plugin's keys, one row each, with the skill that reads each one. A key is set per
user through the plugin's `userConfig` option of the same name and per repository in
`docs/conventions/review.yaml`, validated by
[`schemas/review.schema.json`](../schemas/review.schema.json). No `~/.claude` file, `.claude/`
file or personal override sets these keys. `/review:setup apply` writes the repository file.

| Key | Values | Default | Reader |
|---|---|---|---|
| `downstream_probe` | `run`, `report` | `run` | `/review:quality-gate` downstream mode (Step 2): `run` writes the safety-fact probe in a temporary directory outside the tree and runs it; `report` states the probe without running it. Level rule: policy floor, `report` in any layer wins; the repository value is read from the default branch |
| `fanout_diversity` | `lens`, `model`, `codex` | `lens` | `/review:fanout` run-everything steps 3 and 5 and its fallback: `lens` runs one reviewer agent per concern; `model` sends one review prompt to each distinct fan-out model of the role map; `codex` runs the surfaces `lens` runs, with no fan-out models, and reports the Codex reviewer as the model-diversity panel in a `panel:` line, `skipped` when Codex is absent. Level rule: later layer; the repository layer is skipped when the reviewed change set edits `docs/conventions/review.yaml` |
| `fanout_act_on_cap` | a whole number, at least `1` | `2` | `/review:fanout` Step 2, both review modes: the report's `## By axis` marks the first this many rows under `### Spec`, and separately the first this many under `### Standards`, `yes` in their `Act on` cell, and every later row `no`; a row listed under `## Dismissed` reads `no` and is not counted; no row is dropped. The default `2` is the smallest cap that kept both planted defects of the two-defect fixtures inside act on in 12 of 12 runs, where a cap of `1` left the second outside it in all 12 (#12505). A user option that is not a whole number of at least 1 is an invalid layer. Level rule: later layer; the repository layer is skipped when the reviewed change set edits `docs/conventions/review.yaml` |
| `reproduce_findings` | `off`, `label`, `require` | `off` | the proof stage of [`findings-normalization.md`](findings-normalization.md) ("Stage 5: Proof"), run by `/review:fanout` (both review modes) and `/review:council`: `off` skips it and the report is unchanged; `label` sends each row at or above `reproduce_findings_floor` to a refute gate and labels every row `reproduced`, `verified-by-reading`, `refuted` or `not-attempted`; both `label` and `require` keep a `refuted` row in the findings at `low` confidence, not acted on, with a `## Dismissed` line, and `label` changes no other row; `require` does the same to every row at or above the floor that was not reproduced. No value makes reviewed code run without a person's yes to that exact command ([`run-reviewed-code.md`](run-reviewed-code.md)). Level rule: later layer; the repository layer is skipped when the reviewed change set edits `docs/conventions/review.yaml` |
| `reproduce_findings_floor` | `CRITICAL`, `IMPORTANT`, `SUGGESTION` | `IMPORTANT` | the same proof stage: rows at or above this tier go to the gate; rows below it are labeled `not-attempted`. Read only when `reproduce_findings` is not `off`. A layer naming a tier these three lack is reported on one line, `reproduce_findings_floor: <value> is not a tier (<layer>); every row attempted`, and when no later layer sets a valid tier, every row goes to the gate in place of the default floor. Level rule: later layer; the repository layer is skipped when the reviewed change set edits `docs/conventions/review.yaml` |
| `smell_baseline` | `default`, `off`, or a repository-relative path to a `.md` file | `default` | the `code-reviewer` agent's design-smell check: `default` reads the "Baseline" section of [`design-smells.md`](design-smells.md); `off` checks no smells; a path reads the repository's own list, and a missing file, or one the reviewed change set edits, falls back to the shipped baseline, never to `off`. Level rule: later layer; the repository layer is skipped when the reviewed change set edits `docs/conventions/review.yaml` |
| `loosened_check_verdict` | `fail`, `note` | `fail` | the bundled criterion [Fail a change that loosens a check](../skills/quality-gate/context/loosened-check.md), applied by `/review:quality-gate`'s diff modes, the `code-reviewer` agent, the `/review:code-review` CI lane (from its prompt's value lines, else `fail`), and `/review:fanout`'s `code-reviewer` leaf, criteria slices and model-diversity hunters: `fail` makes a loosening the spec does not allow a blocking finding; `note` reports it at the lowest tier. Level rule: policy floor, `fail` in any layer wins; the repository value is read from the default branch |
| `loosened_check_patterns` | a list of path globs, or `text:` and a regular expression | none | the same criterion: a changed file a glob matches counts as a check's own code or settings; a changed line a `text:` pattern matches is judged against the criterion's kinds. The user option holds the list as JSON text. Level rule: union, every valid layer's entries apply; the repository value is read from the default branch |
| `loosened_check_decision_record` | an https URL prefix ending in `/` | unset | the same criterion: set, a loosening, a removed check or a flaky-test quarantine the spec allows also needs the spec to cite the owner's decision, with a line link under this prefix and the owner's words after `verbatim:` in double quotes; a loosening the pull request body's `## Loosened checks` section allows needs no citation; unset, no citation is needed. Repository layer only, no user option, so a person's own settings cannot switch it off; the value is read from the default branch |
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
never a lower layer's value (ADR 0064 Decision 7). The run continues either way. The one
exception is a `reproduce_findings_floor` value that names no tier, which its row above resolves.

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

**Policy floor and union: the loosened-check keys.** `loosened_check_verdict` is a policy floor
the other way round: `fail` from any valid layer wins over `note`, and with no layer setting it the
key resolves `fail`. `loosened_check_patterns` takes the union of every valid layer's entries, so
no layer removes another's. Both read the repository value from the default branch's committed copy
as `downstream_probe` does, so a pull request that edits `docs/conventions/review.yaml` on its head
can neither relax the verdict nor drop a pattern to narrow its own detection. Unlike
`downstream_probe`, when the default branch cannot be read the verdict resolves `fail`, the user's
patterns still apply, and a WARN line says why. `loosened_check_decision_record` has only the
repository layer, read the same way. It prints `unset` only when the default branch's copy does not
have the key. It prints `unreadable`, with a WARN, when the value could not be known or is invalid:
no `--ref`, a default branch that cannot be read, a committed file that does not parse, or a key
present with an invalid value, an exception to the "Resolution" rule above, so a merged typo cannot
switch the citation off. The criterion then treats the citation as unmet, so no spec can allow the
loosening on that run.
`scripts/loosened-check-settings.mjs --root <root> --ref origin/<default>` resolves all three, with
`--verdict-option` and `--patterns-file` (a file holding the patterns option, never a shell
argument, written to `<memory_dir>/reviews/<branch-slug>/loosened-check-patterns.json`) for the
user options, and prints each value with the layers that set it. Given `--spec-issue <number>`, it
also prints `loosened_check_spec: counts` only when the issue's author is trusted. It reads the
trusted-actor list from the default branch it resolves itself (`refs/remotes/origin/HEAD`, else the
default branch `gh api` reports), and a `--ref` naming another commit prints `no reason`,
so a run pointed at a head branch never reads a list that branch edited. Where the default
branch's `docs/conventions/source-control.yaml` sets `trusted_actors_source: standards`, the list
is `components/trusted-actors/trusted-actors.json` in the `<owner>/<repo>` that
`standards_repository` names, at its main commit, resolved once, instead; `repository` or no key
keeps the copy, and any other value, or `standards` with no valid `standards_repository`, prints
`no reason`. Where the list (that one, or
`.github/standards/trusted-actors/trusted-actors.json` on the default branch) exists, it decides
alone: the author must be a User whose id is a human entry. Where the default branch has no such
file, the author must be a User whose `author_association` on the issue is `OWNER`, `MEMBER` or
`COLLABORATOR`. Any other author, a list that exists but does not parse, a default branch that
cannot be resolved, or a read that fails prints `no reason`, and the spec is then not handed to
reviewers; `review:fanout-sweep` drops a `spec` arg unless its `loosenedSettings` carries the
`counts` line. The line names the rule that decided.

**Root rule.** The repository file is read only when the repository root (`CLAUDE_PROJECT_DIR`,
else `git rev-parse --show-toplevel`) is inside a git working tree and is neither `$HOME` nor an
ancestor of it. Otherwise the repository layer is skipped and the report line says why.

**Older releases.** A plugin release without a key has no option for it, and its schema does not
list the key, so its reader reports the repository key as unknown. A reader that ignores an
unknown key keeps the file's other keys; an older reader drops the whole repository layer, and
each key then resolves as it does for an invalid layer: `fanout_diversity`,
`fanout_act_on_cap`, `reproduce_findings` and `reproduce_findings_floor` take their defaults,
never the lower userConfig value, and `downstream_probe` still takes `report` from userConfig. A
key holding a map or a list, as `council_members`, `council_panel` and `council_rules` do, makes an
older reader drop the whole repository layer, not just that key: every other key in the file falls
back too. A repository shared with users on an older release should add a key only once they have
updated.
