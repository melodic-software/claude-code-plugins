# Upstream source: tlaplus/AgentSkills

Pointer record for [tlaplus/AgentSkills](https://github.com/tlaplus/AgentSkills), the TLA+
project's collection of agent instructions for writing and editing TLA+ specifications, MIT
licensed. Nothing in this marketplace is derived from it today. This page exists so that work on
formal verification starts from a known commit instead of a fresh search.

**Last audited upstream state:** `tlaplus/AgentSkills@f2adb5e4e2c6250661d1aff8bcc0b9f92d5442ec` (upstream
HEAD of `main` when read; the repository has no tags or releases). Git history of this file records
*when*; this line records only *what was audited*.

**Recheck trigger:** a change, between the pinned commit and upstream HEAD, to a path a row we took
or rejected something from links, a unit removed or added under the scope: re-audit the affected
rows. This page has no rows and no scope, so the drift check lists it as `untracked` and never
reports it as drift. The revisit trigger below says when to re-read it.

## What the pinned commit holds

Three instruction sets for an agent editing TLA+: one adds a state variable to a spec and updates
every place that must mention it, one breaks a single action into two steps that run in order, and
one writes a TLA+ spec that models the behavior of existing program code. The upstream README
states the instructions are not tied to one agent product.

## Decision

- **A `formal-verification` plugin is planned.** On 2026-11-12 the owner reopened the earlier "no
  TLA+ skill" decision outside its revisit trigger (map
  [#15651](https://github.com/melodic-software/claude-code-plugins/issues/15651)). The plugin is
  built in three slices:
  [#15648](https://github.com/melodic-software/claude-code-plugins/issues/15648),
  [#15773](https://github.com/melodic-software/claude-code-plugins/issues/15773) and
  [#15775](https://github.com/melodic-software/claude-code-plugins/issues/15775). Until they land,
  no plugin in this marketplace ships model checking or TLA+ authoring.
- **Its source is pstack, not this repository.** The plugin adapts the formal-verification skills
  recorded in [`cursor-pstack.md`](cursor-pstack.md). Nothing wraps or depends on
  tlaplus/AgentSkills.
- **No vendored copy.** No file from this upstream is stored here. If a slice takes anything from
  it, this page gains attribution rows linking the upstream paths at a new pin.

## Revisit trigger

Re-read the upstream at its then-current HEAD, and move the pin to that commit, when a slice above
writes or changes TLA+ authoring guidance.
