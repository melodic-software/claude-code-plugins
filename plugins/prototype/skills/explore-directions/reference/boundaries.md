# Boundaries with nearby surfaces

The rest of each rule in the `## Boundary` section of [SKILL.md](../SKILL.md): that section keeps
the suggest sentence, the routing split and the mutation gates; this file holds the detail, and
states none of those again.

## Bundled `design` skill

One native Claude Code surface drafts layouts as this skill does, and the two get conflated when
the intent selector lands on the HTML mockup substrate:

- **`design` (bundled skill)**: drafts artboards on one canvas and publishes the canvas as a
  Claude Design Artifact; how that canvas persists, is shared and is edited is [Artifacts § Draft a design canvas](https://code.claude.com/docs/en/artifacts#draft-a-design-canvas).
- **This skill (marketplace plugin).** Throwaway variants as a local HTML mockup by default, or on
  the real stack on request, switchable from a control bar; only the winning-variant key survives.

**Routing.** On the mockup host, this skill builds the mockup whether or not the user runs
`/design`. The resolved medium is read per [medium.md](medium.md). State the lifecycle difference
with the offer; the design-canvas subsection in [SKILL.md](../SKILL.md) carries the offer shape. Why
the SKILL.md shadowing check and description line exist: a local skill named `design` at any level
shadows the bundled command (precedence: [Skills § Resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name)), and the
bundled one never appears in your skill listing. A local `design` skill that disables model
invocation shadows it too and is hidden from you; a `/design` whose description differs is a
local skill, not the canvas, and not to be run for it. With `--unattended`, never attempt the
command: build without asking.

**Mutation gate.** The canvas persists under the user's account; the capture discipline records
the winning key and notes only.

## Built-in `ClaudeDesign` tool

A request to mock up a page can name a Claude Design project the person already has, and then it
means that project, not a new mockup. What the tool and this skill each do is in
[claude-design-tool.md](claude-design-tool.md) "The two compared".

**Routing.** Otherwise this skill builds its variants as today. The tool is the project's editor;
this skill is the throwaway comparison.

**Mutation gate.** A `ClaudeDesign` write changes a project the person's team shares. A first write
asks the person for a one-time project approval, or goes through the tool's plan step. The tool
refuses writes in some execution contexts, which the probe record in
[claude-design-tool.md](claude-design-tool.md) lists. The four-part records live in that file.

## Marketplace `playground` plugin

[native-playground.md](native-playground.md) holds how the two differ, the routing rule, the
mutation gate and the availability records; read it when an ask to "try options visually" could
mean either.
