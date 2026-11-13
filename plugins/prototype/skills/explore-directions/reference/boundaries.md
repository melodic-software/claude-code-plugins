# Boundaries with nearby surfaces

The full rules behind the `## Boundary` section in [SKILL.md](../SKILL.md), one section per surface.

## Boundary, the bundled `design` skill

One native Claude Code surface drafts layouts as this skill does, and the two get conflated when
the intent selector lands on the HTML mockup substrate:

- **`design` (bundled skill)**: drafts artboards on one canvas and publishes the canvas as a
  Claude Design Artifact; how that canvas persists, is shared and is edited is [Artifacts § Draft a design canvas](https://code.claude.com/docs/en/artifacts#draft-a-design-canvas).
  It is reserved for the person to run as `/design`; the model does not invoke it.
- **This skill (marketplace plugin).** Throwaway variants as a local HTML mockup by default, or on
  the real stack on request, switchable from a control bar; only the winning-variant key survives.

**Routing.** On the mockup host, this skill builds the mockup whether or not the user runs
`/design`. Unless the resolved medium keeps the view on this machine ([medium.md](medium.md)), which drops this offer, tell the user before building: If /design is available in your session (gate basis:
the verification record in [design-canvas.md](design-canvas.md)), you
can run `/design <scope>` instead of or alongside this skill for a hand-editable design canvas.
State the lifecycle difference with it; the design-canvas subsection in [SKILL.md](../SKILL.md) carries the offer
shape. A local skill named `design` at any level shadows the bundled command (precedence: [Skills § Resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name)), and the
bundled one never appears in your skill listing, so a `design` entry in that listing is a
shadowing local skill: do not make the offer, and tell the user a local `design` skill shadows the
bundled canvas command. A local `design` skill that disables model invocation shadows it too and
is hidden from you, so every offer adds that `/design`'s description should read "Make a new
Design artifact from a brief"; anything else is a local skill, not the canvas, and not to be run
for it. With `--unattended`, make no `/design` suggestion, record none, and never attempt the
command: build without asking.

**Mutation gate.** The canvas persists under the user's account. This skill never runs it, never
publishes on its own initiative, and never references the canvas from anything tracked in the
repository; the capture discipline records the winning key and notes only.

## Boundary, the built-in `ClaudeDesign` tool

A request to mock up a page can name a Claude Design project the person already has, and then it
means that project, not a new mockup. What the tool and this skill each do is in
[claude-design-tool.md](claude-design-tool.md) "The two compared".

**Routing.** When the person names or links an existing claude.ai/design project, or asks for the
work to go into one, and the `ClaudeDesign` tool resolves in this session, use that tool for the
project's files. Otherwise this skill builds its variants as today. The tool is the project's
editor; this skill is the throwaway comparison.

**Mutation gate.** A `ClaudeDesign` write changes a project the person's team shares. Write only
to the project the person named, and only after they asked for the change. A first write asks the
person for a one-time project approval, or goes through the tool's plan step. The tool refuses
writes in some execution contexts, which the probe record in
[claude-design-tool.md](claude-design-tool.md) lists; report the refusal and
never retry around it. The four-part records live in that file.

## Boundary, the marketplace `playground` plugin

A parameter explorer that hands back a prompt is the `playground` skill's job, not this one's: [native-playground.md](native-playground.md) holds
how the two differ, the routing rule, the mutation gate and the availability records; read it when
an ask to "try options visually" could mean either.
