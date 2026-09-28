# map-* family status

Epic [#4639](https://github.com/melodic-software/claude-code-plugins/issues/4639).
`origin/main` still has four architecture skills: `improve`, `map-landscape`,
`record-decision`, and `setup`. The nine skills below the landscape rung are
implemented on open child pull requests. They are not in this tree, and this
page does not re-implement them.

`map-landscape`'s thin-result remedy stays `/architecture:improve` or
`/discovery:explore` until `map-components` is on main. Do not point `## Next`
at a skill this checkout cannot run.

## Build order

The epic's order, with the pull request that carries each skill:

| Order | Skill | Issue | Pull request | On main |
| --- | --- | --- | --- | --- |
| 1 | map-dependencies | #4641 | [#5046](https://github.com/melodic-software/claude-code-plugins/pull/5046) | no |
| 2 | map-components | #4642 | [#5063](https://github.com/melodic-software/claude-code-plugins/pull/5063) | no |
| 3 | map-events | #4647 | [#5102](https://github.com/melodic-software/claude-code-plugins/pull/5102) | no |
| 4 | map-flow | #4645 | [#5093](https://github.com/melodic-software/claude-code-plugins/pull/5093) | no |
| 5 | map-containers | #4644 | [#5086](https://github.com/melodic-software/claude-code-plugins/pull/5086) | no |
| 6 | map-context | #4643 | [#5080](https://github.com/melodic-software/claude-code-plugins/pull/5080) | no |
| 7 | map-data | #4648 | [#5091](https://github.com/melodic-software/claude-code-plugins/pull/5091) | no |
| 8 | map-deployment | #4649 | [#5109](https://github.com/melodic-software/claude-code-plugins/pull/5109) | no |
| 9 | map-states | #4650 | [#5108](https://github.com/melodic-software/claude-code-plugins/pull/5108) | no |

`map-dependencies` is the shared build-declaration graph the component, context,
and container views are meant to read. The behavior skills (events, flow, data,
deployment, states) do not wait on it. `map-states` is the optional one: it
earns its place where state machines are explicit in source.

## What is still open on the epic

- The dialect-key decision (reuse `diagram_dialect.*` versus plugin-local keys)
  is not recorded here. The child pull requests own that choice for the views
  they emit. This page does not pick a dialect ahead of them.
- Each child closes on its own issue when that pull request merges. This page
  is the index, not a substitute for those skills.
- After `map-components` merges, `map-landscape`'s thin-result `## Next` should
  name it. Until then the landscape skill must not route to a missing command.

Checked against `origin/main` at `ec232d017`: `plugins/architecture/skills`
contains `map-landscape` and no other `map-*` directory.
