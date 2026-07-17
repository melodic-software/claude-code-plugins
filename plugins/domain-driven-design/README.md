# domain-driven-design

A Claude Code plugin owning **DDD practice skills** — the stewardship disciplines of
domain-driven design, independent of any one planning or workshop workflow.

| Skill | What it does |
|---|---|
| `/domain-driven-design:ubiquitous-language` | Actively maintains the consuming project's ubiquitous-language glossary: resolves ambiguous or overloaded terms, records canonical language and rejected synonyms, and routes entries to already-known bounded contexts — never discovering boundaries itself. |

Deferred: `context-mapping` and `aggregate-design` join this plugin when those
practices materialize as skills.

Bounded-context **discovery** is out of scope here — workshop-driven discovery lives in
the standalone `event-storming` plugin, which `ubiquitous-language` soft-routes to when
boundaries are missing.

## Works in any repo

- **Reads your conventions, assumes none.** Glossary filename, location, shape, and
  context map come from the consuming project; where none exist, creation is lazy and
  discovery-first — never a prescribed universal filename.
- **No `userConfig`, no persistent state, no network.**

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install domain-driven-design@melodic-software
```

The `planning` plugin declares a dependency on this plugin, so installing `planning`
installs it automatically.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
