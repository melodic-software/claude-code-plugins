---
description: "Check the multi-agent role map (model and effort per role and the layer behind each value) or write confirmed keys into the user, team or local multi-agent.yaml layer."
argument-hint: "[check|apply] [--layer user|team|local|--migrate] [<key>=<value> ...] [session=<alias>]"
user-invocable: true
disable-model-invocation: true
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/setup.sh:*)"]
shell: bash
---

## Purpose

`/multi-agent:route` resolves the role map through four layers: the bundled
defaults, the user file the `role_map_file` option names, the team layer and
`<home>/multi-agent.local.yaml`. This skill shows what those layers resolve to
and writes one of them. All three consumer layers absent is a valid state: the
bundled defaults apply. Keys, values, layer paths and the fan-out guard are
defined in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).

An old `~/.claude/multi-agent.yaml` or `.claude/multi-agent.local.yaml` is still read while its new
file is absent, with a warning; `apply --migrate` moves it.

No argument means `check`. It installs nothing; the resolver needs only Bash,
awk and git. Pass `--user-file '${user_config.role_map_file}'` on every
`setup.sh` call, exactly as written below.

## `check` (read-only)

```bash
${CLAUDE_SKILL_DIR}/scripts/setup.sh check session=<alias> --user-file '${user_config.role_map_file}'
```

Pass `session=<alias>` with the family in your own model ID (`opus`, `sonnet`,
`haiku`, `fable`); omit it when you cannot tell, and the map is resolved as
under a frontier session. The JSON is the one `/multi-agent:route all` prints.
Show:

1. one line per role: `single <model> @ <effort>; fanout <model> @ <effort>`,
   with `inherit` written as `inherit: omit the model option`, and the layer
   in `source` for each value;
2. the `layers` rows (read, absent, skipped, or not applicable at a home or
   non-repository root) and every entry of `notes` as written; each note (a
   skipped layer, a rejected value, an ignored key) is a finding to report;
3. the personal-override row: PASS when `<home>/multi-agent.local.yaml` is
   gitignored, else WARN with the recommended line `<home>/**/*.local.*`.
   Recommend the line; do not edit `.gitignore`;
4. each `WARN user-config:` or `WARN personal-override:` row naming an old
   path, and each `WARN team:` row: a retired team file (the config block in
   `docs/conventions/multi-agent.md`, or `.claude/multi-agent.yaml`) that the
   resolver no longer reads. Relay the row's next step as written, and offer
   `apply --migrate` for each old file.

It modifies nothing.

## `apply`

1. Run `check` and show the map. This is the before state.
2. Settle the layer with the user, recommendation first:
   - `local` (`<home>/multi-agent.local.yaml`): this checkout only, for this
     person. The default for a personal preference.
   - `team`: `docs/conventions/multi-agent.yaml` (under the convention home the
     repository binds). Shared with everyone who clones the repository.
   - `user`: the file the `role_map_file` option names, for every repository
     you work in. While the option is unset, `apply --layer user` stops: ask
     the user to set it in `/config` to a file of their choosing, then rerun.

   `team` and `local` are refused at a home or non-repository root. `user` and
   `local` are refused while that layer's old file exists: migrate first.
3. Settle the keys. Ask only for what the user wants changed; each value comes
   from the table in `config.md`. Pass every key to set as `<key>=<value>`, and
   `<key>=` to remove one from that layer. Existing keys in the layer are kept.
4. Preview, writing nothing:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/setup.sh apply --layer <layer> --user-file '${user_config.role_map_file}' <key>=<value> ...
   ```

   It prints the target path and a diff. It exits 1 without writing when the
   resolver would reject or ignore a key; relay the reason and return to
   step 3.
5. Show the diff and ask for an explicit yes. Write only on that yes:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/setup.sh apply --layer <layer> --write --user-file '${user_config.role_map_file}' <key>=<value> ...
   ```

   It prints the path written and the keys it read back from the file.
6. Run `check` again and show the after map beside the before one, naming each
   value that changed and the layer that now supplies it. The file is what the
   next `/multi-agent:route` run reads; nothing about the running session
   changes. For `team`, offer `git add` and a commit and run each only when the
   user accepts.

### `apply --migrate`

Moves each old file into its new location, so each layer ends with one file:
`~/.claude/multi-agent.yaml` into the `role_map_file` option's file,
`.claude/multi-agent.local.yaml` into `<home>/multi-agent.local.yaml`, and the
retired `.claude/multi-agent.yaml` into the team YAML.

1. Run `check` and show the map and the old-path rows.
2. Preview, writing nothing:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/setup.sh apply --migrate --user-file '${user_config.role_map_file}'
   ```

   It prints one `would move:` line and a diff per old file. A key the new
   file already sets keeps its value, and a `kept:` line names it with the old
   value. A `skip:` line means the old user file has no new home yet: relay
   its step (set the option in `/config`).
3. Show the preview and ask for an explicit yes. Move only on that yes:

   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/setup.sh apply --migrate --write --user-file '${user_config.role_map_file}'
   ```

   For each file it writes the new file, reads it back, checks that the
   layers resolve the values the old file gave (when the old file was the one
   read), and only then deletes the old file. On a failed check it exits 1
   and keeps the old file; relay the message.
4. Run `check` again and show the after map beside the before one.

### The fan-out guard

With `fanout.frontier_guard: true`, the bundled value, a stage that runs more
than one agent never runs them on a frontier model: under a Fable
session, or a session the caller did not name, each fan-out variant that would
inherit or name a frontier model takes `fanout.model` (`opus`) instead. A
single synthesis or judge agent keeps the role's own model. The basis is
recorded beside the key in
[`${CLAUDE_PLUGIN_ROOT}/reference/defaults.yaml`](${CLAUDE_PLUGIN_ROOT}/reference/defaults.yaml).

`fanout.frontier_guard=false` is an explicit opt-in to frontier fan-outs: every
parallel worker then runs on the session model, so a frontier session runs
every agent of the stage on the frontier model (rates:
[Pricing: model pricing](https://platform.claude.com/docs/en/about-claude/pricing#model-pricing); usage:
[Manage costs: Track your costs](https://code.claude.com/docs/en/costs#track-your-costs)).
Before writing it, say this and ask the user to confirm that specific key,
separately from the rest of the change. Recommend the narrowest layer that
covers what they mean: `local` for one checkout, `user` for every repository
you work in, `team` only when the whole team has agreed.

## What this skill does not do

- Edit `.gitignore`, `CLAUDE.md` or `AGENTS.md`.
- Write a model ID. Only aliases are accepted, so the map stays portable across
  providers.
- Change a named agent's model or effort. An agent such as
  `implementation:implementer` or `implementation:scoped-implementer` owns its
  tier through its own frontmatter and whatever its dispatcher passes on the
  call; the role map governs generic `agent()` and Agent dispatches only.
- Recheck a default against upstream. That is `/multi-agent:audit-defaults`.

## Next

/multi-agent:route all
Prints the map the next workflow reads from `args.roles`.

## Gotchas

- A layer file is rewritten whole, so its comments are not kept; the preview
  says so when the file has any.
- An existing layer that does not parse stops `apply` with the line and the
  reason. Fix or remove the file first; setup never overwrites content it could
  not read.
- The first `team` write creates the YAML. A retired team file, which the
  resolver no longer reads, seeds its keys and stays as it was; `check` names
  it until it is deleted. `apply --migrate` moves a retired
  `.claude/multi-agent.yaml` and deletes it; the config block in
  `docs/conventions/multi-agent.md` is left to delete by hand.
- Team and local layers resolve against the repository root of the working
  directory. Inside a second worktree, run from that worktree.
