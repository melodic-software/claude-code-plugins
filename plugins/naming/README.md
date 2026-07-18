# naming

A Claude Code plugin for generating and evaluating name candidates. One
skill, one job: when a name was just rejected — or none exists yet — break
the anchor by fanning out blind, fresh-context generators from distinct
lenses, then hand the human a scored shortlist to choose from.

| Skill | What it does |
|---|---|
| `/naming:name-it-better` | Generate fresh name candidates from blind lenses, score them, recommend a shortlist — the human picks |

## Why blind generators

The dominant trigger is a reactive retry: a name was suggested and
rejected, and the same context that produced it will only produce more of
the same. So the generators run BLIND to the conversation, seeded only with
a structured context brief (responsibility, firing context, scope
boundaries, collision vocabulary, word-level blocklist — rejected NAMES
stay on the main thread's reject list, never in the brief), each
working a distinct lens (responsibility-literal, moment-of-use,
domain-lore). Diverge widely from
independent perspectives, then converge once — and keep the first-seen
suggestion from anchoring the choice. The method grounding is in the
skill's `context/sources.md`.

**The human always picks.** The skill narrows and recommends; it never
auto-locks a name.

```shell
/naming:name-it-better              # blind lenses → scored shortlist → human picks
/naming:name-it-better tournament   # ~5 generators + elimination rounds for high-stakes names
```

`tournament` is an honest adaptation of elimination brackets plus pairwise
social-choice scoring — not a documented naming technique; the skill
presents it as such.

## Consumer conventions

- **Criteria source of truth.** The skill scores against the consuming
  organization's naming and domain-language conventions when the project
  declares them (its `CLAUDE.md` / `.claude/rules/` or a standards source
  it points to). When none is declared, it falls back to a research-ordered
  general criteria priority — semantic accuracy first, trigger utility last
  — grounded in the skill's `context/sources.md`. A criterion the user
  wants that is missing from their conventions flows UP into those
  conventions, not into the skill.
- **Adjacent capabilities.** Resolving what a domain concept IS routes to a
  domain-modelling capability; propagating a chosen name across call sites
  routes to a rename-references capability — each invoked through its slash
  command when present, degrading to prose guidance when absent.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install naming@melodic-software
```

## Configuration

No `userConfig`. No persistent state. Network: the generators are
subagents; `context/sources.md` carries external reference links for the
method, not fetched at runtime.
