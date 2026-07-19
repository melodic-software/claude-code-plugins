---
name: setup
description: "Configure the songwriting plugin for this repository: inventory or scaffold the project-level prompt-template overrides under songwriting/templates/pat-pattison/, and confirm where craft artifacts land. Use when: 'set up songwriting', 'configure songwriting', 'songwriting setup', 'customize a songwriting template', 'override the co-write prompt', or a craft skill reports you want to tune its bundled prompt. Actions: check (read-only inventory, default) | apply (scaffold or remove overrides). Re-runnable and safe."
argument-hint: "check | apply [scaffold <name>...] [remove <name>...]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inventories the consuming repo's tracked
prompt-template overrides and reports the effective artifact layout; `apply` scaffolds an override from
a bundled default (or removes a byte-identical one). The override seam and the output layout are the
plugin's only extension points — it carries no `userConfig`. Both surfaces are described once in
[`${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/research/artifact-persistence.md`](../../context/pat-pattison/research/artifact-persistence.md).

Action routing: no argument or `check` runs the inventory; `apply scaffold <name>...` copies the named
bundled defaults into overrides; `apply remove <name>...` deletes the named overrides. `apply` runs
`check` first. `apply` is non-interactive for the safe paths (scaffolding a not-yet-overridden template,
removing a byte-identical one); the single deliberate exception is a destructive-collision guard —
overwriting an already-diverged override or removing a customized one would lose the consumer's edits,
so those confirm first rather than clobber.

## The two surfaces

- **Template overrides (the only thing this skill writes).** A file at
  `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` in the consuming repo wins over
  the bundled default `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/templates/<name>.md` (first match).
  These overrides are **tracked, team-shared config** — they belong in the consumer's repo, not in
  machine-local state or the plugin directory.
- **Artifact layout (read/confirm only, never written by this skill).** Craft skills persist work under
  `${CLAUDE_PROJECT_DIR}/songwriting/` by default; if the consuming project's own `CLAUDE.md` or rules
  declare a different songwriting layout, that layout wins. That declaration is the consumer's own
  instruction surface — setup surfaces it and reports the effective layout, but does not edit the
  consumer's `CLAUDE.md`.

## The override cost — scaffold only what you intend to customize

An override **freezes** that template: once `songwriting/templates/pat-pattison/<name>.md` exists, the
craft skills load it instead of the bundled default forever, so later plugin improvements to that
template stop reaching this repo. Scaffold an override **only** for a template the consumer actually
wants to change. Copying all sixteen defaults verbatim is an anti-pattern — sixteen files that opt out
of updates while customizing nothing.

## `check` (read-only)

Inventory without writing anything. Apply the convention-resolution ladder — override present → it wins;
no override → the bundled default stays in force (the safe default).

1. **Overrides present.** List what exists under
   `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/`, and list the bundled defaults in
   `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/templates/` (each `<name>.md` is loaded by the craft
   skill that references it — e.g. `co-write-session-opener` by `/songwriting:co-write`,
   `metaphor-recipe-prompt` by `/songwriting:object-writing`). Report: templates available to override,
   templates already overridden, and — for each existing override — whether it is byte-identical to the
   current bundled default (INFO: a byte-identical override customizes nothing and only opts the repo
   out of future improvements; `apply remove <name>` clears it).
2. **Artifact layout.** Read the consuming project's `CLAUDE.md` and `.claude/rules` for a declared
   songwriting layout. Report the effective layout — the declared one if present, else the default
   `songwriting/` layout from the artifact-persistence contract.

## `apply` (idempotent)

Run `check`, then act on the named arguments only — never scaffold or remove a template the consumer
did not name.

- **`apply scaffold <name>...`** — create the
  `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/` directory if absent, then copy each named
  bundled default verbatim to `<name>.md` as the starting point for the consumer to edit. If an override
  already exists, show the difference and do not overwrite it without explicit confirmation in this
  conversation. Confirm the scaffolded files are tracked, not gitignored.
- **`apply remove <name>...`** — delete the named override(s). Offer this for any override `check` found
  byte-identical to its bundled default; for a diverged override, show what would be lost and confirm
  first.
- **Custom artifact layout.** If the consumer wants a non-default layout, show them the one-line
  convention to add to their **own** `CLAUDE.md` or rules; do not write it for them (that surface is
  consumer-owned).

After any change, re-run the `check` inventory and report the resulting override set. Re-running `apply`
with no scaffold/remove argument changes nothing and reports the current inventory.

## What this skill does NOT do

- Run a craft skill — that is `/songwriting:workflow` and the concern skills it routes to.
- Write machine-local state — overrides live in the consumer's tracked repo, never in the plugin
  directory or the plugin data directory.
- Edit the consumer's `CLAUDE.md` or rules — the artifact-layout convention is the consumer's own
  instruction surface; setup reads and reports it, it does not author it.
- Scaffold templates the consumer did not name — a bundled default left in place keeps receiving plugin
  improvements.
