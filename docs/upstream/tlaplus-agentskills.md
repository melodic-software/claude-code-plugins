# Upstream source: tlaplus/AgentSkills

Pointer record for [tlaplus/AgentSkills](https://github.com/tlaplus/AgentSkills), the TLA+
project's collection of agent instructions for writing and editing TLA+ specifications, MIT
licensed. Nothing in this marketplace is derived from it today. This page exists so that a later
decision about formal verification starts from a known commit instead of a fresh search.

**Last audited upstream state:** `tlaplus/AgentSkills@f2adb5e4e2c6250661d1aff8bcc0b9f92d5442ec` (upstream
HEAD of `main` when read; the repository has no tags or releases). Git history of this file records
*when*; this line records only *what was audited*.

**Recheck trigger:** a change, between the pinned commit and upstream HEAD, to a path a row we took
or rejected something from links, a unit removed or added under the scope: re-audit the affected
rows. This page has no rows and no scope, so the drift check lists it as `untracked` and never
reports it as drift. The revisit trigger below is what reopens the decision.

## What the pinned commit holds

Three instruction sets for an agent editing TLA+: one adds a state variable to a spec and updates
every place that must mention it, one breaks a single action into two steps that run in order, and
one writes a TLA+ spec that models the behavior of existing program code. The upstream README
states the instructions are not tied to one agent product.

## Decision

- **No TLA+ skill now.** No plugin in this marketplace ships model checking or TLA+ authoring, and
  none wraps or depends on this repository.
- **No vendored copy.** No file from the upstream is stored here.
- **A later skill is ours.** If the revisit trigger fires and a skill is warranted, it is written
  from the upstream in our own words and our own examples, the way the
  [pstack](cursor-pstack.md) and [Matt Pocock](mattpocock-skills.md) adaptations were, and this page
  gains attribution rows linking the upstream paths at a new pin.

## Revisit trigger

Reopen the decision when either event happens:

- a concurrency bug in the [loop lanes](../conventions/loop-lane/README.md), such as two lanes
  acting on the same pull request or issue in an order the lane rules did not allow, that a
  model of the lane protocol would have caught; or
- a consumer of this marketplace asks for TLA+ or model-checking support.

Re-read the upstream at its then-current HEAD before deciding, and move the pin to that commit.
