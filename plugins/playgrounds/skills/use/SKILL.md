---
description: "Reach Anthropic's first-party playground capability in one step: verify the upstream playground plugin is installed, invoke its skill for interactive single-file HTML explorers (controls beside a live preview, output is a prompt you paste back), or emit the exact install commands when it is absent. Use when: 'make me a playground', 'interactive explorer for X', 'install the playground plugin', 'critique this document with approve/reject controls', or any ask to tune a parameter space visually and see the result (sliders, balancing, exploring parameters). Also carries field-tested prompt recipes, delivery guidance for cloud and remote sessions where a local browser cannot open, and known-limitation notes. This wrapper generates nothing itself; the upstream skill owns generation. Not for choosing a visual form for conversation content (a visualization capability owns that) or for throwaway variations of your own project's UI (a prototyping capability owns that)."
argument-hint: "[what to explore] e.g. 'balance the Inferno hero deck'"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Route playground requests to the first-party plugin, or install it, with recipes and guidance
---

# Use playgrounds

## Purpose

Connect a playground-shaped request (an interactive parameter space the user wants to
manipulate visually, with the result flowing back as a prompt) to the maintained
first-party implementation: the `playground` skill from the `playground` plugin on the
`claude-plugins-official` marketplace. This skill routes, installs, and advises. It
never builds a playground itself.

## Step 1: Presence check (provenance, not prose)

Determine whether the upstream plugin is installed by its identity, not its wording:

- Run `claude plugin list` and look for the `playground` plugin sourced from
  `claude-plugins-official`. That marketplace-qualified install record is the
  authoritative signal.
- Where the CLI is unavailable to the session, fall back to the session's skill
  listing: a bare `playground` skill whose description says it creates interactive
  HTML playgrounds. Treat the description comparison as ADVISORY only; upstream may
  reword it at any time, and a listing under budget pressure can drop descriptions
  entirely. Never conclude "absent" from wording alone when the name is present.
- A local skill can shadow the upstream name. When the listed `playground` skill's
  description clearly describes something other than an interactive-explorer builder,
  say a shadow is likely, then let provenance decide: with the install record
  confirming `playground@claude-plugins-official`, warn about the shadow and invoke
  the namespaced `playground:playground` form (a bare-name shadow cannot intercept
  it); with no install record confirming it, take the install/guidance path, and
  never invoke the shadowing skill.

## Step 2: Present, so invoke

When the upstream skill is present, invoke it via the Skill tool with the user's
brief as arguments: the namespaced form `playground:playground` is the reliable
address for a plugin skill; the bare `playground` form resolves only while no other
skill carries that name. Pass the request
as stated; the upstream skill owns template choice and generation. If the invocation
is refused, do not retry blind: tell the user the skill is installed but this session
could not invoke it, and suggest they run it themselves by asking for a playground in
their own words.

## Step 3: Absent, so uplift

This plugin declares the upstream dependency in its manifest, so on installs where
dependency resolution runs, Claude Code offers to install `playground` automatically
and reports `dependency-unsatisfied` with the exact command when it cannot. In
contexts where resolution does not run (a synced or cloud session, a manual setup),
emit the commands directly:

```shell
/plugin marketplace add anthropics/claude-plugins-official
/plugin install playground@claude-plugins-official
```

Scope guidance: `user` scope makes the capability available everywhere; `project`
scope pins it to one repository. The marketplace-add step is often unnecessary (the
official marketplaces are preconfigured on most installs); include it only when the
install command reports the marketplace is unknown. If the install is blocked by
organization policy, say so plainly and stop; there is no workaround to offer.

## Step 4: Delivery, especially off the desktop

The upstream skill writes a single HTML file and opens it with `open <file>.html`,
which assumes a local desktop browser. Feature-detect the delivery path instead of
assuming it:

1. A desktop session with a local browser: let the upstream flow open the file.
2. A session that can publish an Artifact: offer to publish the generated HTML so the
   user gets a link. State that the page runs under the artifact sandbox, and confirm
   the copy-prompt button works there before promising the round trip.
3. A session with a file-send surface (remote control, managed cloud): send the HTML
   file to the user to open locally.
4. None of the above: report the file's absolute path and say how to open it.

Degrade visibly at every tier; never name a delivery surface as guaranteed.

## Recipes (field-tested)

From the plugin author's published examples, verbatim shapes to adapt:

- "Use the playground skill to create a playground that helps me explore new layout
  changes to the AskUserQuestion Tool"
- "Use the playground skill to review my SKILL.md and give me inline suggestions I
  can approve, reject or comment"
- "Use the playground skill to tweak my intro screen to be more interesting and
  delightful"
- "Use the playground skill to show how this email agent codebase works and let me
  comment on particular nodes in the architecture to ask questions, make edits, etc"
- "Use the playground skill to help me balance the 'Inferno' hero's deck"

Repo-native recipe for this marketplace: "Use the playground skill to review
plugins/<name>/skills/<skill>/SKILL.md and give me inline suggestions I can approve,
reject or comment" turns skill-file review into an interactive pass.

## Known limitations

Consumer guidance for the generated playgrounds lives in
[`context/consumer-notes.md`](context/consumer-notes.md); read it before relying on a
generated playground for anything beyond personal exploration.

## Gotchas

- A listed `playground` skill name proves presence of A skill, not THE skill: local
  shadows are silent, which is why Step 1 judges by install record and treats wording
  as advisory.
- The copy-prompt button is the product; a sandboxed page (an Artifact) can restrict
  clipboard access, so confirm the round trip once before a long exploration.
- A summarizing fetch of the upstream marketplace can misreport its contents;
  verify upstream facts against raw files or the install record, never a summary.

## Boundary

- Choosing the best visual FORM for conversation content is the visualization
  capability's job; this skill fires only when the user wants an interactive,
  manipulable explorer whose output returns as a prompt.
- Throwaway visual variations of your own project's UI are the prototyping
  capability's job; a playground explores a parameter space, not your codebase's
  routes.
- Generation, templates, and the playground page's own design belong to the upstream
  skill; nothing here overrides them.
