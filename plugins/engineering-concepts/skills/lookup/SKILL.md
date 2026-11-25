---
description: "Built-in engineering-concept catalog lookup: finds a principle, pattern, practice or architecture by name, alias, id or tag and returns pointers to official sources, no definitions. Use when asked which concepts fit a concern or stage, or for a concept's source or counterweights. Interface terms: /user-interface:glossary; domain terms: /domain-driven-design:ubiquitous-language."
argument-hint: "[<term>] [--concern <c>] [--kind <k>] [--stage <s>] [--reversibility <r>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Find built-in engineering-concept records and their official sources
---

# Lookup

Answer from the catalog's records: each one names a concept, its official source, its tags and the
concepts that pull against it. A record holds pointers to official sources, no definitions; when
the question needs what a concept says, read its `source_url` and answer from that page.

Run `node "${CLAUDE_PLUGIN_ROOT}/scripts/lookup.mjs"` with the term and filters the request implies
(`--help` lists them). Pass the user's own `--exclude` and `--source-bar` values when they give
them. Report each hit as its name and id, the source link, the tags that made it match, and its
counterweights and conflicts by name; say which filters you applied.

- Exit 1 means nothing matched: say so and name the term and filters tried, never a concept from
  memory presented as a catalog entry.
- A stderr line with `"event":"record rejected"` names a broken data file at its `at` location:
  report it beside the results.
- A record's `owner` names the skill or page that owns the practice in depth; point there when the
  user wants to act on it.

The catalog holds no positions: a record says what a concept is called and where its source is,
never whether to use it. A team's or person's stances live in their standards layers.

## Boundaries

- The name for an interface effect or front-end behavior: `/user-interface:glossary` (if enabled).
- A project's own domain terms: `/domain-driven-design:ubiquitous-language` (if enabled).
- Bringing a whole topic or entry into the session for the work ahead:
  `/engineering-concepts:load`.

## Next

`/engineering-concepts:load`, to keep the found entries in view for the design or review ahead.

## Gotchas

- A merged id still finds its record through the alias it became; the record printed carries the
  surviving id, so cite that one.
- `--stage` also matches records staged `any`.
