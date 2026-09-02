# playgrounds

One-step access to Anthropic's first-party playground capability. A playground is an
interactive single-file HTML explorer: controls on one side, a live preview on the
other, and a generated prompt with a copy button, so what you adjust visually flows
back into the session as text. The `playground` plugin on `claude-plugins-official`
owns that capability; this plugin gets you to it and makes it work well in more
places. It generates nothing itself.

| Skill | What it does |
|---|---|
| `/playgrounds:use` | Verify the upstream plugin is installed (by install record, not wording), invoke its skill with your brief, or emit the exact install commands; then guide delivery in cloud and remote sessions and supply field-tested prompt recipes |

## What the wrapper adds

- A declared cross-marketplace dependency, so installing this plugin offers the
  upstream plugin in the same step where dependency resolution runs, and names the
  exact command where it does not.
- Delivery guidance for sessions without a local browser, where the upstream flow's
  `open <file>.html` cannot work: publish as an Artifact, send the file, or report
  the path, each offered only when the session actually supports it.
- Field-tested prompt recipes (the plugin author's five published examples plus a
  repo-native SKILL.md-review recipe).
- Consumer cautions for the generated pages, commit-stamped, in
  [`skills/use/context/consumer-notes.md`](skills/use/context/consumer-notes.md).

## Boundary

Form selection for conversation content belongs to a visualization capability, and
throwaway variations of your own project's UI belong to a prototyping capability;
this plugin fires on requests for an interactive parameter explorer whose output
returns as a prompt. Generation and templates belong entirely to the upstream skill.

## Provenance

The wrapped capability is `playground@claude-plugins-official`
(<https://github.com/anthropics/claude-plugins-official>, Apache-2.0). Upstream facts
referenced by this plugin were read at commit
`ed404106fcd80ba98ecb7c851e531dcb626d13b7` (verified current 2026-09-01). This
wrapper is MIT-licensed and copies no upstream content.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install playgrounds@<marketplace>
```

Installing this plugin declares a dependency on `playground@claude-plugins-official`;
where dependency resolution does not run, `/playgrounds:use` emits the install
commands itself. No configuration options, no hooks, no persistent state, and no
network calls of its own.
