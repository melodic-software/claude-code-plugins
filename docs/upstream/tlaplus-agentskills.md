# Upstream source: tlaplus/AgentSkills

Pointer record for [tlaplus/AgentSkills](https://github.com/tlaplus/AgentSkills), the TLA+
project's collection of agent instructions for writing and editing TLA+ specifications, MIT
licensed. Nothing in this marketplace is derived from it today. This page exists so that work on
formal verification starts from a known commit instead of a fresh search.

**Last audited upstream state:** `tlaplus/AgentSkills@f2adb5e4e2c6250661d1aff8bcc0b9f92d5442ec` (upstream
HEAD of `main` when re-read for [#15648](https://github.com/melodic-software/claude-code-plugins/issues/15648),
unchanged since the first read; the repository has no tags or releases). Git history of this file
records *when*; this line records only *what was audited*.

**Recheck trigger:** a change, between the pinned commit and upstream HEAD, to a path a row we took
or rejected something from links, a unit removed or added under the scope: re-audit the affected
rows. The decision's recheck trigger below says when to re-read it.

## What the pinned commit holds

Three instruction sets for an agent editing TLA+: one adds a state variable to a spec and updates
every place that must mention it, one breaks a single action into two steps that run in order, and
one writes a TLA+ spec that models the behavior of existing program code. The upstream README
states the instructions are not tied to one agent product.

## Attribution table

| Upstream (links at the pin) | Ours | Relation | Decision |
|---|---|---|---|
| [`tlaplus-from-source`](https://github.com/tlaplus/AgentSkills/tree/f2adb5e4e2c6250661d1aff8bcc0b9f92d5442ec/skills/tlaplus-from-source) | none | Not adopted | Its four phases (understand the code, choose abstractions, write the spec, propose properties) are the job of the `specify` skill's create action, slices 2 and 3 ([#15773](https://github.com/melodic-software/claude-code-plugins/issues/15773)). `/formal-verification:chart` writes TLA+ only under pstack's "Write the spec" rules and adds none of this skill's guidance. Re-read when `specify` is planned. |
| [`tlaplus-add-variable`](https://github.com/tlaplus/AgentSkills/tree/f2adb5e4e2c6250661d1aff8bcc0b9f92d5442ec/skills/tlaplus-add-variable) | none | Not adopted | An editing recipe for an existing spec. The `formal-<area>` contract's Updating section leaves model edits to the agent following the code; no skill here edits a spec mechanically. |
| [`tlaplus-split-action`](https://github.com/tlaplus/AgentSkills/tree/f2adb5e4e2c6250661d1aff8bcc0b9f92d5442ec/skills/tlaplus-split-action) | none | Not adopted | Same as `tlaplus-add-variable`: an editing recipe with no consumer here. |

## Decision

- **A `formal-verification` plugin ships model checking.** On 2026-11-12 the owner reopened the
  earlier "no TLA+ skill" decision outside its recheck trigger (map
  [#15651](https://github.com/melodic-software/claude-code-plugins/issues/15651)). The plugin is
  built in three slices:
  [#15648](https://github.com/melodic-software/claude-code-plugins/issues/15648),
  [#15773](https://github.com/melodic-software/claude-code-plugins/issues/15773) and
  [#15775](https://github.com/melodic-software/claude-code-plugins/issues/15775). The first adds
  `/formal-verification:chart`, which checks a TLA+ spec with TLC, `/formal-verification:setup`,
  and the `formal-<area>` skill contract.
- **Its source is pstack, not this repository.** The plugin carries the formal-verification skills
  recorded in [`cursor-pstack.md`](cursor-pstack.md). Nothing wraps or depends on
  tlaplus/AgentSkills, and the rows above take nothing from it.
- **No vendored copy.** No file from this upstream is stored here.

## Recheck trigger

Re-read the upstream at its then-current HEAD, and move the pin to that commit, when a slice above
writes or changes TLA+ authoring guidance; the `specify` slices are the next.
