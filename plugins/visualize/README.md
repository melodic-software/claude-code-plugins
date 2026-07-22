# visualize

A Claude Code plugin for on-demand visualization. One skill, one job: at any point
in a conversation, decide **what** is most worth showing visually and **how** to
show it, then render it — a form-and-medium router, not a craft teacher.

| Skill | What it does |
|---|---|
| `/visualize:visualize` | Infer the target from the conversation, pick a form (mermaid diagram, table, chart, ASCII/Unicode, or a rich page) and a medium (terminal, local HTML file, or published Artifact), and render it — asking only on genuine ambiguity |

## What it decides

Two decisions, then the output:

- **Form** — matched to the *shape* of the content: a mermaid diagram for flow /
  hierarchy / sequence / state / relationships; a markdown table for attribute
  comparison; a chart for quantities; ASCII/Unicode for a small structural sketch;
  a rich rendered page for a composite or interactive view.
- **Medium** — one of three ascending tiers, **inline terminal → local HTML file →
  published Artifact**, chosen by the form's weight, a configurable preference, and
  which surfaces are actually available.

The full grounded catalog — every mermaid family, the zero-dependency chart paths,
and the rendering-surface facts — lives in the skill's
[`context/decision-matrix.md`](skills/visualize/context/decision-matrix.md).

## Router, not craft

This skill decides the form and medium; it does **not** own the craft of a good
chart or the fundamentals of a good page. When a chart is the right form and a
chart-craft/dataviz capability is installed, it routes the craft there; when a rich
page is the right medium, the page's contract and design are owned by the Artifact
tool's own contract and an artifact-design capability. Each is invoked through its
capability when present and degrades to a documented fallback when absent — this
skill never restates their guidance.

It is also **not** a comprehension aid: restating dense text in plainer words is a
different concern. This skill is form-driven (render content as a visual), not
comprehension-driven.

```shell
/visualize                          # infer the target, auto-decide form and medium
/visualize this as a sequence       # honor a named form
/visualize file                     # render richer forms as a local HTML file, never published
/visualize artifact                 # prefer a published Artifact when that surface is available
```

## Surfaces and availability

A published Artifact is heavily gated (plan, sign-in, provider, version, and
context constraints); when it is unavailable the skill writes a self-contained
local HTML file instead, and if no page surface is available it degrades visibly to
the terminal. A ` ```mermaid ` fence in the terminal is shown as source, not a
rendered diagram. These facts and their sources are documented in the catalog.

## Configuration

- **`medium`** (`userConfig`, string, default `auto`). Preferred delivery medium
  when the skill auto-selects: `auto` (decide by content and available surfaces),
  `terminal` (always inline), `file` (rich forms as a local HTML file, never
  published off the machine), or `artifact` (prefer a published Artifact when
  available, else a local file, else terminal). An unrecognized value is reported
  and treated as `auto`. There is no native enum type for `userConfig`, so the
  allowed values are validated in-skill.

Configure with `/plugin configure visualize` (or `--config medium=<value>` on a
fresh install). No persistent state; no external prerequisites; no network calls of
its own.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install visualize@melodic-software
```

## Possible future change

- **Category.** Filed under `workflow` as the least-bad existing fit; a visualization
  router is really presentation/output-shaping, which the taxonomy has no category
  for yet. Recategorization is tracked in
  [#1068](https://github.com/melodic-software/claude-code-plugins/issues/1068).
- **Third-party visualization server.** No credible egress-free, self-hostable
  visualization server exists to depend on today. Re-evaluate if one lands with a
  maintained security posture (a self-hosted AntV deployment is the current
  candidate) — until then the skill relies only on native rendering surfaces and
  the presence-gated craft capabilities.
