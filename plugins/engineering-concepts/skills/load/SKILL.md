---
description: "Loads a built-in engineering-concept topic or entry into the session as working context: pointers to official sources, no definitions. Use when asked to load a topic or apply a named concept to the current design, plan or review. Interface terms: /user-interface:glossary; domain terms: /domain-driven-design:ubiquitous-language."
argument-hint: "<topic|term>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Bring a catalog topic or entry into the session as working context
---

# Load

Bring catalog entries into the session so the work ahead is checked against them. The records are
pointers to official sources, no definitions: the session keeps each entry's name, source and
counterweights in view and reads a source only when a decision turns on what it says.

Run `node "${CLAUDE_PLUGIN_ROOT}/scripts/lookup.mjs" --topic <topic>` for a topic, or with the term
for one entry; `--help` lists the filters. When the argument could be either, try it as a topic
first, since a topic name is a file under `data/`, then as a term. Pass the user's own `--exclude`
and `--source-bar` values when they give them.

Report what was loaded as a short list: each entry's name, id, source link, stage and its
counterweights. Then keep the list as standing context for the rest of the task: when a step meets
an entry's stage and concern, name the entry and its counterweight together, so neither is applied
alone.

- Nothing matched (exit 1): say so with the argument tried, and load nothing.
- A stderr line with `"event":"record rejected"` names a broken data file at its `at` location:
  report it and load the records that parsed.

Loading never adopts a concept as a standard. A stance a team or person keeps lives in their
standards layers.

## Boundaries

- A single question about the catalog, with nothing to keep in view: `/engineering-concepts:lookup`.
- Interface effect names: `/user-interface:glossary` (if enabled).
- A project's own domain terms: `/domain-driven-design:ubiquitous-language` (if enabled).

## Gotchas

- An entry staged `any` loads with every stage filter; it is not specific to the current stage.

## Next

- Settle a design choice the loaded entries raise: `/planning:design` (if enabled).
