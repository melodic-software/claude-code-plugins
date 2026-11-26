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

Run the lookup with `--topic <topic>` for a topic, or with the term for one entry; `--help` lists
the filters. When the argument could be either, try it as a topic first, since a topic name is a
file under `data/`, then as a term. Keep the heredoc as written: it hands the plugin's saved
options to the script, which merges them with the repository's settings files
([Reference a saved value](https://code.claude.com/docs/en/plugins/manifest-reference#reference-a-saved-value)).

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/lookup.mjs" --topic <topic> --project "<repository root>" --user-config - <<'EC_SETTINGS'
source_bar=${user_config.source_bar}
exclude=${user_config.exclude}
EC_SETTINGS
```

If that run is refused, report the refusal and stop; never reshape the command and retry. A `--source-bar` or `--exclude` the user asks for goes on the command
line.

Report what was loaded as a short list: each entry's name, id, source link, stage and its
counterweights. Then keep the list as standing context for the rest of the task: when a step meets
an entry's stage and concern, name the entry and its counterweight together, so neither is applied
alone.

- Nothing matched (exit 1): say so with the argument tried, and load nothing.
- Exit 1 with a stderr line `"event":"catalog empty"`: the plugin ships no curated concepts yet.
  Tell the user the catalog has no entries to load, and keep no list as standing context.
- A stderr line with `"event":"record rejected"` names a broken data file at its `at` location:
  report it and load the records that parsed. One with `"event":"setting rejected"` names a
  dropped settings value: report it.

Loading never adopts a concept as a standard. A stance a team or person keeps lives in their
standards layers.

## Boundaries

- A single question about the catalog, with nothing to keep in view: `/engineering-concepts:lookup`.
- Interface effect names: `/user-interface:glossary` (if enabled).
- A project's own domain terms: `/domain-driven-design:ubiquitous-language` (if enabled).

## Next

`/planning:design`, to settle a design choice the loaded entries raise.

## Gotchas

- An entry staged `any` loads with every stage filter; it is not specific to the current stage.
