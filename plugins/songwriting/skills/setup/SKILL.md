---
name: setup
description: "Configure the songwriting plugin for this repository: interview the user, then scaffold project-level prompt-template overrides under songwriting/templates/pat-pattison/ from the bundled defaults and confirm where craft artifacts land. Use when: 'set up songwriting', 'configure songwriting', 'songwriting setup', 'customize a songwriting template', 'override the co-write prompt', or a craft skill reports you want to tune its bundled prompt. Re-runnable — safe to invoke again to reconfigure."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Scaffold (or update) the consuming repo's tracked prompt-template overrides for `/songwriting` craft
skills, and confirm where generated craft artifacts land. The override seam and the output layout are
the plugin's only extension points — it carries no `userConfig`. Both surfaces are described once in
[`${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/research/artifact-persistence.md`](../../context/pat-pattison/research/artifact-persistence.md);
this skill materializes an override deliberately instead of leaving the consumer to hand-create the
directory and hunt for the right default to copy.

Idempotent: re-running reads the existing overrides first and offers updates rather than overwriting
blind.

## The two surfaces

- **Template overrides (the only thing this skill writes).** A file at
  `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` in the consuming repo wins
  over the bundled default `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/templates/<name>.md` (first
  match). These overrides are **tracked, team-shared config** — they belong in the consumer's repo,
  not in machine-local state or the plugin directory.
- **Artifact layout (read/confirm only, never written by this skill).** Craft skills persist work
  under `${CLAUDE_PROJECT_DIR}/songwriting/` by default; if the consuming project's own `CLAUDE.md`
  or rules declare a different songwriting layout, that layout wins. That declaration is the
  consumer's own instruction surface — setup surfaces it and reports the effective layout, but does
  not edit the consumer's `CLAUDE.md`.

## The override cost — scaffold only what you intend to customize

An override **freezes** that template: once `songwriting/templates/pat-pattison/<name>.md` exists,
the craft skills load it instead of the bundled default forever, so later plugin improvements to that
template stop reaching this repo. Scaffold an override **only** for a template the consumer actually
wants to change. Copying all sixteen defaults verbatim is an anti-pattern — sixteen files that opt out
of updates while customizing nothing.

## Task

Apply the convention-resolution ladder — override present → use it; a template the consumer wants to
change but has not overridden → scaffold from the bundled default; otherwise leave the bundled
default in force (the safe default; no scaffolding needed).

1. **Read existing overrides first.** List what already exists under
   `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/`, and list the bundled defaults in
   `${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/templates/` (each `<name>.md` is loaded by the craft
   skill that references it — e.g. `co-write-session-opener` by `/songwriting:co-write`,
   `metaphor-recipe-prompt` by `/songwriting:object-writing`). Present a short summary: templates
   available to override, templates already overridden, and — for each existing override — whether it
   is byte-identical to the current bundled default. Offer to **remove** any byte-identical override
   (it customizes nothing and only opts the repo out of future improvements to that template).
2. **Interview which templates to customize, one at a time.** For each template the consumer names,
   confirm the intent to diverge from the bundled default before scaffolding. Do not scaffold a
   template the consumer did not ask for.
3. **Scaffold selected overrides.** Create the
   `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/` directory if absent, then copy the
   chosen bundled default verbatim to `<name>.md` as the starting point for the consumer to edit.
   Never overwrite an existing override without explicit confirmation in this conversation — if one
   exists, show the difference and ask before replacing it. Confirm the scaffolded files are tracked,
   not gitignored.
4. **Confirm the artifact layout.** Read the consuming project's `CLAUDE.md` and `.claude/rules` for
   a declared songwriting layout. Report the effective layout — the declared one if present, else the
   default `songwriting/` layout from the artifact-persistence contract. If the consumer wants a
   custom layout, show them the one-line convention to add to their **own** `CLAUDE.md` or rules; do
   not write it for them (that surface is consumer-owned).

## Output

The scaffolded override files under `songwriting/templates/pat-pattison/` (only those the consumer
chose), plus a one-paragraph summary of what was scaffolded or removed, the effective artifact
layout, and how to re-run this setup to reconfigure.

## What this skill does NOT do

- Run a craft skill — that is `/songwriting:workflow` and the concern skills it routes to.
- Write machine-local state — overrides live in the consumer's tracked repo, never in the plugin
  directory or the plugin data directory.
- Edit the consumer's `CLAUDE.md` or rules — the artifact-layout convention is the consumer's own
  instruction surface; setup reads and reports it, it does not author it.
- Scaffold templates the consumer did not ask for — a bundled default left in place keeps receiving
  plugin improvements.
