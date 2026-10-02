# claude-code-plugins

## Open a pull request as a draft

Open every pull request as a draft and flip it to ready when the work is done: a draft skips the
test lanes and both AI review lanes, and once it is ready they run again on every push. None of
their checks is required; `ci-status` is the only one. Flip with
`/source-control:pull-request ready`, which merges the base, reviews and verifies the merged head,
and then marks it ready.

Title every pull request in Conventional Commits form, `<type>[(<scope>)]: <subject>`;
`ci-status` fails any other title.

When a pull request is superseded or must not merge, apply the `do-not-merge` label (for example
`gh pr edit <n> --add-label do-not-merge`) before writing any explanation. "Do not merge" in the body
or a comment is not enforced by `ci-status`, which reads only the label; the babysit merge gate
still respects a body hold and human comments, so never override one. The hold convention is in
`docs/conventions/loop-lane/README.md`.

## When to stop and when to keep going

When a step doesn't need the user's input, keep going, with status notes in the same message as
the next action. Stop and ask only when you can't continue without the user, or before anything
destructive or outside this checkout: deleting data, force-pushing, pushing, merging, commenting on
a PR or issue, touching another worktree or repo, a fleet host, or user-scope config. A task or
loop prompt that explicitly authorizes one of those covers it. Launch unattended lanes with
`--permission-mode auto`; a lane whose action the auto-mode classifier denies records the denial
in its lane telemetry and moves on. A hook `ask` or `permissions.ask` rule can open a dialog no one
answers, so lane sessions carry none. `--permission-prompts none` is documented for print mode and
unattended runs; that a `--bg` lane denies with it is not probed. Never use bypass mode or
`--dangerously-skip-permissions`: lanes read untrusted issue and PR text while holding push
credentials. On a long run, keep the task list in a file and tick it as you go, and end with
three headings: Blocked on me, Changed, Found, unless a skill defines its own report shape.

<!-- BEGIN GENERATED: instruction-placement rules index -->

## Conventions that load on demand

Each surface below enters context automatically when Claude reads a file it covers, in subagents
as well as in the main session. The match is on the requested path, so even a read that finds no
file fires it. A surface whose trigger has not fired is simply absent, and after a compaction it
returns only when a covered file is read again. When you are working on something an entry covers
and its content is not already in context, read the file directly.

| Surface | Covers | Topic |
|---|---|---|
| `.claude/rules/cost-claims.md` | `plugins/*/skills/**, plugins/*/agents/**, plugins/*/reference/**, docs/**/*.md, prompts/**` | Cost claims link the costs and pricing docs and state no prices or per-task figures; `docs/upstream/` records may list vendor figures labelled vendor-reported |
| `.claude/rules/ruff-pin.md` | `**/*.py` | Python linting runs through the pinned ruff wrapper, never a bare ruff on PATH |
| `.claude/rules/skill-bodies-state-current-rules.md` | `plugins/*/skills/**, plugins/*/agents/**` | Skill and agent bodies carry a four-part verification record for any volatile specific they restate, and name their successor in a `## Next` section; read before editing any skill body |
| `plugins/attribution/skills/audit/AGENTS.md` | `plugins/attribution/skills/audit/**` | Editing the attribution audit skill: contributor conventions |
| `plugins/autonomy/AGENTS.md` | `plugins/autonomy/**` | autonomy plugin: contributor conventions |
| `plugins/machine-health/skills/audit/AGENTS.md` | `plugins/machine-health/skills/audit/**` | machine-health audit skill: contributor conventions |
| `plugins/playbooks/reference/model-adaptation/AGENTS.md` | `plugins/playbooks/reference/model-adaptation/**` | model-adaptation chapters: contributor conventions |
| `plugins/work-items/skills/work-loop/AGENTS.md` | `plugins/work-items/skills/work-loop/**` | work-loop: contributor conventions |

<!-- END GENERATED: instruction-placement rules index -->
