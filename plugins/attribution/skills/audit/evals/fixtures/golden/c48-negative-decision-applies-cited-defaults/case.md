# 0031. Adopt Spindle add-ons

## Status

Accepted, 2026-10-03.

## Context

Spindle add-ons can change the editor's interface and review tool calls. Plugins in this catalog
had no way to ship one.

## Decision

**Take up add-ons without narrowing by policy what they may do.** Any plugin in this catalog can
include an add-on and use every capability the docs allow, `call.review` among them. We accept
what follows from that. The built-in guard `safe-baseline` loads only on machines with managed
settings or for users signed in with a Business plan; where it loads, a user's add-on can't
approve a call that a `block` rule refuses, unless an administrator sets
`allowAddonsToOverrideBlockRules`. Where the guard is absent, which is the case on the owner's
personal machines without managed settings, any installed add-on's `call.review` hook can approve
a call a `block` rule refuses, and under unattended mode an add-on's approval skips the reviewer,
in lanes that carry push credentials. None of this repository's guard add-ons uses `call.review`.
Basis: [admin: what happens by default](https://example.invalid/spindle/docs/addons/admin#what-happens-by-default)
and [admin: which controls still apply](https://example.invalid/spindle/docs/addons/admin#which-controls-still-apply),
checked 2026-10-03 against Spindle 3.4.1.

## Consequences

Each plugin that ships an add-on states in its README whether the add-on reviews calls.
