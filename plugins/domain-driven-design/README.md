# domain-driven-design

A Claude Code plugin owning **DDD practice skills**. It holds the stewardship
disciplines of domain-driven design, independent of any one planning or workshop
workflow.

| Skill | What it does |
|---|---|
| `/domain-driven-design:curate-language` | Actively maintains the consuming project's ubiquitous-language glossary: resolves ambiguous or overloaded terms, records canonical language and rejected synonyms, sharpens definitions to say what each term is, and routes entries to already-known bounded contexts. It never discovers boundaries itself. |

Deferred: `context-mapping` and `aggregate-design` join this plugin when those
practices materialize as skills.

Bounded-context **discovery** is out of scope here. Workshop-driven discovery lives in
the standalone `event-storming` plugin, which `curate-language` soft-routes to when
boundaries are missing.

## Works in any repo

- **Reads your conventions first.** Glossary filename, location, shape, and context map
  come from the consuming project. Where none exist, it proposes, never imposes, one
  `GLOSSARY.md` per bounded context and a root `GLOSSARY-MAP.md` once more than one
  context exists, and writes only after you confirm; creation stays lazy.
- **Settings.** `glossary_file` and `glossary_map_file` set those two names. They
  resolve through the config cascade: the plugin default, `userConfig`, the team file
  `docs/conventions/domain-driven-design.yaml` (schema
  `schemas/domain-driven-design.schema.json`) and the personal overlay
  `docs/conventions/domain-driven-design.local.yaml`. Each is a file name, never a path.
- **No persistent state, no network.**

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install domain-driven-design@melodic-software
```

The `planning` plugin invokes `/domain-driven-design:curate-language` when it is installed, and
records resolved terms in its own artifacts when it is not. Install this plugin alongside
`planning` to get glossary stewardship inside the planning workflow.

## License

MIT (SPDX-License-Identifier: MIT).
