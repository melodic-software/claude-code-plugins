# session-flow settings

The keys session-flow's skills read in their own text, one row each. A key is set per user through
the plugin's `userConfig` option of the same name and per repository in
`docs/conventions/session-flow.yaml`, validated by
[`schemas/session-flow.schema.json`](../schemas/session-flow.schema.json). No `~/.claude` file,
`.claude/` file or local overlay sets these keys. `/session-flow:setup apply` writes the repository
file after validating it against the schema; `/session-flow:setup check` validates it. The observer and `audit_sessions_*` options are
`userConfig` only; the README's Options reference lists them.

| Key | Values | Default | Reader | Level rule |
|---|---|---|---|---|
| `worker_continuation` | `resume`, `respawn` | `resume` | `/session-flow:orchestrate` (priming addendum only; export modes omit it) | repository file over user option over default |
| `encode_policy` | `promote-when-must-hold`, `strongest-first` | `promote-when-must-hold` | `/session-flow:retro codify` (Strength step) | repository file over user option over default |
| `review_mining_prs` | an unquoted integer from 2 to 200 | `20` | `/session-flow:retro codify reviews` | repository file over user option over default |
| `wip_commit` | an unquoted `true` or `false` | `false` | `/session-flow:handoff` ("WIP commit on an explicit pause") | repository file over user option over default |
| `transcript_scope` | `worktree`, `repo`, `all` | `worktree` | `/session-flow:find-handoff` (step 2, the transcript scan); `/session-flow:recall` (Steps 2 and 3) | narrowest wins (`worktree` < `repo` < `all`); an unset user option counts as `worktree` |

`transcript_scope` bounds which project directories `/session-flow:find-handoff` and
`/session-flow:recall` read transcripts from, through `scripts/transcript_dirs.sh`. `worktree`
scans this worktree's directories, widens on a miss to the repository's other worktrees, and asks before reading any
other project's transcripts; unattended, it reports the miss instead of asking. `repo` starts with
every worktree of the repository and asks the same way. `all` widens to every project without
asking. This key does not follow the later-layer rule below: the narrower of the two layers wins,
and an unset or unrendered user option counts as `worktree`. A repository file can therefore
narrow a user's scan but never widen it, and a user who wants `all` sets it in their own option.

`encode_policy` decides where codify starts a lesson on the enforcement ladder. Under
`promote-when-must-hold`, a lesson becomes a line in `CLAUDE.md`, a rules file or `REVIEW.md`,
and only a rule that must hold every time moves up to a rung that checks it. Under
`strongest-first`, every lesson is proposed at the strongest rung that can assert it.
`review_mining_prs` is how many of the repository's most recent merged pull requests
`codify reviews` reads; a lesson is routed only when it recurs in two or more of them.

`wip_commit` lets `/session-flow:handoff` make one local `chore(wip): <one-line state>` commit of
tracked changes, and only when the user asks in this session to pause. A handoff another skill
calls, one a hook suggests, one at a phase boundary and one run under `orchestrator` commit
authority never commit. The skill refuses the commit, and says why in the save-point, during a
merge, rebase, cherry-pick or revert, on a detached HEAD, on the default branch, and over a
partially staged path. It never skips commit hooks and never pushes. `false` keeps the handoff
from committing anything.

`resume` keeps a worker across related units, as imperative 4 of the orchestration brief says.
`respawn` gives each new unit (a fix round, a follow-up, a retry, the next queue item) a fresh
worker whose brief consolidates the original brief, every later directive, the prior worker's
report and its branch, and resumes the old worker only when the unit needs state that lives in it
and is costly to move: its checkout, uncommitted changes, or a running process. Under either
value, a worker is respawned after an interrupt, and every resume message restates the brief's
scope fence and standing constraints.

## Resolution

The reading skill resolves each key once, lowest layer first:

1. The default in the table above.
2. The user's option, rendered into the skill as `${user_config.<key>}`. A literal, unexpanded
   placeholder means the option is unset. A user value equal to the default reads as the default,
   since the two cannot be told apart.
3. The key in the repository's `docs/conventions/session-flow.yaml`, read with the plugin's copy
   of the shared reader, `skills/retro/scripts/parse-concern-value.sh`. A missing file or key
   leaves this layer unset. The reader prints nothing both for an absent key and for an empty
   one (`key:`), so a skill that reads `encode_policy`, `review_mining_prs`, `wip_commit` or
   `transcript_scope` first runs `node skills/setup/scripts/setup-apply.mjs --check --root <git root>` from the plugin root.
   When it exits 1, a problem line naming the key marks the repository value invalid, and a
   parse-error line (`line <n>: ...`, no key named) marks every key in the file invalid; any other
   exit leaves the reader's output standing. A quoted number or boolean is a string, so
   `review_mining_prs: "20"` and `wip_commit: "true"` are invalid, and so is `wip_commit: yes`.

The later layer wins. The skill reports one line naming the resolved value and the layer that
supplied it, for example `worker_continuation: respawn (docs/conventions/session-flow.yaml)`. A
value outside the key's values in either layer is named with its file or option, the key and the
value, and that layer is dropped: a valid higher layer still wins, otherwise the key's default,
never a lower layer's value. An invalid value never stops the run.

**`transcript_scope` is the exception.** The narrower of the user option and the repository value
wins, an unset or unrendered user option counting as `worktree`. An invalid user option counts as
unset, so the result is `worktree`. An invalid repository value is named and dropped, and the key
resolves its default, `worktree`, not the user's value. The report line names the layer whose value
won, for example `transcript_scope: repo (user option; docs/conventions/session-flow.yaml says all)`.

**Root rule.** The repository file is read only when the working directory's git root is neither
`$HOME` nor an ancestor of it. Otherwise the repository layer is skipped and the report line says
so. This is step 2 of the config-cascade resolution algorithm, applied in the skill text.

**Older releases.** A plugin release without a key has no option for it and ignores the repository
key, since unknown keys are inert, so it keeps its earlier behavior.
