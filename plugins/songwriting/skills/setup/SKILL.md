---
description: "Inventory (check, read-only) or scaffold and remove (apply) this repository's songwriting prompt-template overrides, and confirm where craft artifacts land."
argument-hint: "[check|apply] [scaffold <name>...] [remove <name>...]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md` "Setup is explicit
and repeatable" in the marketplace repository). The plugin's only extension points are the
template-override seam and the artifact layout, both described in
[`${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/research/artifact-persistence.md`](../../context/pat-pattison/research/artifact-persistence.md).
It carries no `userConfig`.

Action routing: no argument or `check` runs the inventory; `apply scaffold <name>...` copies the
named bundled defaults into overrides; `apply remove <name>...` deletes the named overrides.
`apply` runs `check` first. `apply` is non-interactive for the safe paths (scaffolding a
not-yet-overridden template, removing a byte-identical one); the single exception is a
destructive-collision guard: overwriting an already-diverged override or removing a customized one
would lose the consumer's edits, so those confirm first rather than clobber.

## The two surfaces

- **Template overrides (the only thing this skill writes).** A file at
  `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` in the consuming repo wins
  over the bundled default `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/templates/<name>.md` (first
  match). Overrides are **tracked, team-shared config** in the consumer's repo, never in
  machine-local state, the plugin directory or the plugin data directory.
- **Artifact layout (read and report only).** Craft skills persist work under
  `${CLAUDE_PROJECT_DIR}/songwriting/` by default; a songwriting layout declared in the consuming
  project's own `CLAUDE.md` or rules wins. That is the consumer's instruction surface: setup reports
  the effective layout and never edits their `CLAUDE.md` or rules.

## The override cost. Scaffold only what you intend to customize

An override **freezes** that template: once `songwriting/templates/pat-pattison/<name>.md` exists,
the craft skills load it instead of the bundled default forever, so later plugin improvements to
that template stop reaching this repo. Scaffold an override **only** for a template the consumer
wants to change, never every default verbatim.

## `check` (read-only)

Write nothing. Apply the convention-resolution ladder: override present → it wins; no override →
the bundled default stays in force.

1. **Overrides present.** List what exists under
   `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/`, and list the bundled defaults in
   `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/templates/` (each `<name>.md` is loaded by the craft
   skill that references it, e.g. `co-write-session-opener` by `/songwriting:co-write`,
   `metaphor-recipe-prompt` by `/songwriting:metaphor`). Report templates available to override,
   templates already overridden, and, for each existing override, whether it is byte-identical to
   the current bundled default (INFO: a byte-identical override customizes nothing and only opts
   the repo out of future improvements; `apply remove <name>` clears it).
2. **Artifact layout.** Read the consuming project's `CLAUDE.md` and `.claude/rules` for a declared
   songwriting layout. Report the effective layout: the declared one if present, else the default
   `songwriting/` layout from the artifact-persistence contract.

## `apply` (idempotent)

Run `check`, then act on the named arguments only; never scaffold or remove a template the
consumer did not name.

- **`apply scaffold <name>...`**. Create the
  `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/` directory if absent, then copy each
  named bundled default verbatim to `<name>.md` as the consumer's starting point. If an override
  already exists, show the difference and do not overwrite it without explicit confirmation in this
  conversation. Confirm the scaffolded files are tracked, not gitignored, via the pair:
  `git check-ignore -v` reports no match (a match is a finding with the pattern) AND
  `git ls-files --error-unmatch` exits 0 (non-zero right after a fresh scaffold means "written but
  untracked: commit it to share with the team", never success).
- **`apply remove <name>...`**. Delete the named override(s). Offer this for any override `check`
  found byte-identical to its bundled default; for a diverged override, show what would be lost and
  confirm first.
- **Custom artifact layout.** If the consumer wants a non-default layout, show them the one-line
  convention to add to their **own** `CLAUDE.md` or rules; do not write it for them.

After any change, re-run the `check` inventory and report the resulting override set. `apply` with
no scaffold/remove argument changes nothing and reports the current inventory.

## What this skill does NOT do

- Run a craft skill. That is `/songwriting:workflow` and the concern skills it routes to.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
