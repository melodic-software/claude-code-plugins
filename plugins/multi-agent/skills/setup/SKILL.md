---
description: "Configure the multi-agent role map for a person or a repository: check prints the resolved map (model and effort per role, single and fan-out variants, the layer behind each value) and whether the personal overlay is gitignored; apply writes the keys you confirm into the user-global, team or local multi-agent.yaml layer, showing the map before and after. Use when: 'set up multi-agent', 'configure model routing', 'change the worker effort for this repo', 'turn off the fan-out guard', 'which layer sets the verifier model', 'multi-agent setup'. Re-runnable."
argument-hint: "[check|apply] [--layer user|team|local] [<key>=<value> ...] [session=<alias>]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/setup.sh:*)"]
shell: bash
---

## Purpose

`/multi-agent:route` resolves the role map through four layers: the bundled
defaults, `~/.claude/multi-agent.yaml`, the team layer and
`.claude/multi-agent.local.yaml`. This skill shows what those layers resolve to
and writes one of them. All three consumer layers absent is a valid state: the
bundled defaults apply. Keys, values, layer paths and the fan-out guard are
owned by
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).

No argument means `check`. `apply` runs `check`, proposes, asks, writes, and
runs `check` again. It installs nothing; the resolver needs only Bash, awk and
git.

## `check` (read-only)

```bash
${CLAUDE_SKILL_DIR}/scripts/setup.sh check session=<alias>
```

Pass `session=<alias>` with the family in your own model ID (`opus`, `sonnet`,
`haiku`, `fable`); omit it when you cannot tell, and the map is resolved as
under a frontier session. The script runs the route wrapper, so the JSON is the
one `/multi-agent:route all` prints. Show:

1. one line per role: `single <model> @ <effort>; fanout <model> @ <effort>`,
   with `inherit` written as `inherit: omit the model option`, and the layer
   in `source` for each value;
2. the `layers` rows (read, absent, skipped, or not applicable at a home or
   non-repository root) and every entry of `notes` as written;
3. the overlay row: PASS when `.claude/multi-agent.local.yaml` is gitignored,
   else WARN with the recommended line `.claude/**/*.local.*`. Recommend the
   line; do not edit `.gitignore`.

It modifies nothing. A note in `notes` (a skipped layer, a rejected value, an
ignored key) is a finding to report.

## `apply`

1. Run `check` and show the map. This is the before state.
2. Settle the layer with the user, recommendation first:
   - `local` (`.claude/multi-agent.local.yaml`): this checkout only, for this
     person. The default for a personal preference.
   - `team`: the `yaml config` block of `docs/conventions/multi-agent.md`,
     else `.claude/multi-agent.yaml` when that file is already in use. Shared
     with everyone who clones the repository.
   - `user` (`~/.claude/multi-agent.yaml`): every repository on this machine.

   `team` and `local` are refused at a home or non-repository root.
3. Settle the keys. Ask only for what the user wants changed; each value comes
   from the table in `config.md`. Pass every key to set as `<key>=<value>`, and
   `<key>=` to remove one from that layer. Existing keys in the layer are kept.
4. Preview, writing nothing:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/setup.sh apply --layer <layer> <key>=<value> ...
   ```

   It prints the target path and a diff. It exits 1 without writing when the
   resolver would reject or ignore a key; relay the reason and return to
   step 3.
5. Show the diff and ask for an explicit yes. Write only on that yes:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/setup.sh apply --layer <layer> --write <key>=<value> ...
   ```

   It prints the path written and the keys it read back from the file.
6. Run `check` again and show the after map beside the before one, naming each
   value that changed and the layer that now supplies it. The file is what the
   next `/multi-agent:route` run reads; nothing about the running session
   changes. For `team`, offer `git add` and a commit and run each only when the
   user accepts.

### The fan-out guard

With `fanout.frontier_guard: true`, the bundled value, a stage that runs more
than one agent never runs them on a frontier model: under a Fable or `best`
session, or a session the caller did not name, each fan-out variant that would
inherit or name a frontier model takes `fanout.model` (`opus`) instead. A
single synthesis or judge agent keeps the role's own model. The basis is
recorded beside the key in
[`${CLAUDE_PLUGIN_ROOT}/reference/defaults.yaml`](${CLAUDE_PLUGIN_ROOT}/reference/defaults.yaml).

`fanout.frontier_guard=false` is an explicit opt-in to frontier fan-outs: every
parallel worker then runs on the session model, so a frontier session runs
every agent of the stage on the frontier model (rates:
[Pricing](https://platform.claude.com/docs/en/about-claude/pricing); usage:
[Manage costs: Track your costs](https://code.claude.com/docs/en/costs#track-your-costs)).
Before writing
it, say this and ask the user to confirm that specific key, separately from the
rest of the change. Recommend the narrowest layer that covers what they mean:
`local` for one checkout, `user` for one machine, `team` only when the whole
team has agreed.

## What this skill does NOT do

- Edit `.gitignore`, `CLAUDE.md` or `AGENTS.md`.
- Write a model ID. Only aliases are accepted, so the map stays portable across
  providers.
- Change a named agent's model or effort. An agent such as
  `implementation:implementer` or `implementation:scoped-implementer` owns its
  tier through its own frontmatter; the role map governs generic `agent()` and
  Agent dispatches only.
- Recheck a default against upstream. That is `/multi-agent:audit-defaults`.

## Next

/multi-agent:route all
Prints the map the next workflow reads from `args.roles`.

## Gotchas

- A file layer is rewritten whole, so its comments are not kept; the preview
  says so when the file has any. A docs block has only its body replaced, and
  the prose around it stays.
- An existing layer that does not parse stops `apply` with the line and the
  reason. Fix or remove the file first; setup never overwrites content it could
  not read.
- When both `docs/conventions/multi-agent.md` (with a block) and
  `.claude/multi-agent.yaml` exist, the docs block is the team layer and the
  `.claude` file is ignored. `check` names both in `notes`.
- Team and local layers resolve against the repository root of the working
  directory. Inside a second worktree, run from that worktree.
