---
description: "Plain-language explanation of a concept, code, error, architecture or the previous assistant response: a concrete analogy and no jargon first, higher altitude (high-school, then peer level) only on request. Use when the user says 'I don't understand this', 'I don't get it', 'what does this actually do', 'what does this mean', 'explain simply' or 'rephrase that'; with no argument it explains the previous assistant response. A faithful restructure is adhd:clarify (if installed), a diagram or ELI5 is education:illustrate, multi-session coaching is education:teach."
argument-hint: "[thing to explain]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Explain any concept or the last response in genuinely plain words
---

# Explain it in plain words

Explain one thing, once, at the lowest useful altitude, then climb only when the reader asks. The
method is the [Feynman technique](https://fs.blog/feynman-technique/). When a plain inline answer
already lands, just answer.

## The core move

1. **Identify the object.** The argument, or with none, the previous assistant response
   ([Empty argument](#empty-argument)).
   **Done when** you can name the object in one sentence, or, on a cold start with no prior
   assistant message, have asked what to explain instead of guessing.
2. **Ground it, don't recall it.** Re-read the actual artifact this turn (the message, the file,
   the error text, the code). For an external concept, fetch a primary source.
   **Done when** the explanation cites a specific passage, file, error text or fetched source
   re-read this turn. A recalled paraphrase does not count.

   For a subsystem of the current codebase, when the discovery skills are available, invoke
   `/discovery:explore --output explain <subsystem>` for what the code does and
   `/discovery:trace-intent <subsystem>` for why it was built that way, and explain from what they
   return. Keep trace-intent's confidence wording: a reason it marked inferred stays hedged
   ("appears to", "likely"), and one it could not find stays "not found", in plain words. Without those skills,
   read the files yourself and cite them; state a reason for a design choice only when a file you
   read gives it.
3. **Land at the starting rung** ([Starting rung](#starting-rung-explain_starting_rung)). Rung 1
   (`plain`) is brief and rests on one everyday analogy, with no jargon and no term that presumes
   background; an unavoidable technical word gets an ordinary-words gloss where it first appears.
   Lead with the analogy and "what it's actually doing", not vocabulary. Rung 3 (`peer`) opens
   with an exact definition in the field's own terms, then works the user's example through it
   without loosening it.
   **Done when** a rung 1 answer has an analogy whose parts map to the object's, a "what it's
   actually doing" line and no unglossed term, and a rung 3 answer opens with the exact
   definition.
4. **Close with the [handoff line](#handoff-to-educationteach)**, then the starting-rung report
   line.
   **Done when** the reply ends with that single handoff line followed by the starting-rung
   report line.

## Empty argument

With no argument, the object is the assistant's own previous response, the thing the user is
reacting to. Re-read it, find the part most likely to have lost the reader (the densest jargon,
the biggest leap), and drop that to plain words. Do not ask "explain what?" when the conversation
makes the referent obvious. With no prior assistant message, ask "What would you like explained?"
instead of inventing a referent.

## Starting rung: `explain_starting_rung`

Resolve the starting rung before writing. Layers, lowest first, a later one winning (key contract:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md)):

| Layer | Value |
|---|---|
| default | `plain` |
| `userConfig` | `${user_config.explain_starting_rung}`. A literal unexpanded token means unset; `plain` here is reported as the default, since the two cannot be told apart. |
| repository | `explain_starting_rung` in `docs/conventions/education.yaml` at the repository root |

To read the repository layer, find the root with `git rev-parse --show-toplevel`, then run
`bash "${CLAUDE_PLUGIN_ROOT}/skills/explain/scripts/parse-concern-value.sh" "<root>/docs/conventions/education.yaml" explain_starting_rung`.
Empty output means the layer is unset. Skip this layer outside a git working tree, or when the
root is `$HOME` or an ancestor of it.

A value other than `plain` or `peer` in a layer is named in the reply, with the file or
`userConfig` that held it, the key and the value, and that layer is dropped. A valid higher layer
still wins; with none, the run uses the default, `plain`. Never stop on an invalid value and never
fall through to a lower layer's value.

Report the result as the last line of the reply, after the handoff line, e.g.
`explain_starting_rung: peer (userConfig)` or `explain_starting_rung: plain (default)`.

## Altitude layering, on request only

Start at rung 1 for `plain`, rung 3 for `peer`. Move only when the user asks ("go deeper", "more
precise", "I actually know X", "say that more simply"). Never front-load a rung above the starting
one.

| Rung | Altitude | Move |
|------|----------|------|
| 1 (`plain` start) | **Plain** | Concrete everyday analogy, zero jargon. The floor and the default landing. |
| 2 (on request) | **High-school** | Introduce one or two real terms of art as vocabulary-ladder entries: the term, its definition in ordinary words, and one modeled "you can now say: …" sentence showing the term doing work in the user's own next prompt. Keep the analogy as scaffolding. |
| 3 (on request, or `peer` start) | **Peer** | Full precision, jargon allowed, edge cases and tradeoffs, the explanation a colleague in the field would want. A `peer` start opens with one precise sentence of definition. |

Offer one other rung in a one-line invitation. From a `plain` start, offer the next rung up:
"That's the plain version, want the high-school one?" From a `peer` start, offer the plain
version: "Want the plain version?"

## Register: content only

Every sentence explains. Leave out comprehension checks on the reader (a question, a request to
restate), role tags in front of a sentence ("Key insight:", "The big idea:", "Bottom line:"), and
commentary on the explanation's tempo ("let's pause here", "step 2 of 4"). Only two lines speak to
the reader about what follows: the rung offer and the handoff line.

## Feynman gap check

If you cannot shed the jargon, or the only explanation you can produce still leans on the terms
the user didn't follow or on hand-waving, that is an understanding gap on the explainer's side.
Name the part you cannot yet reduce and why, and ground harder (re-read the source, fetch the
primary reference) before claiming to explain it. Never swap in a confident restatement or
synonyms.

## Success condition

When the explanation serves a task the user was stuck on, it succeeded if their next prompt names
what they mean in the newly plain terms; shape rung-2 vocabulary so they can reuse it. A bare "I
don't get it" with no task behind it has no such test.

## Handoff to `education:teach`

Close every explanation with this single line; only the starting-rung report follows it:

> Want to actually learn this, not just get past it? `/education:teach topic <x>`
> runs a multi-session coached deep-dive.

## Boundaries

- **Multi-session coaching** (workspace, mission, glossary, persistent state) is
  `/education:teach`. Its `explain <concept>` action writes a lesson into a teach workspace; this
  skill is a standalone one-shot with no workspace.
- **A faithful restructure** of a dense, decision-heavy message, same precision and words, is
  `adhd:clarify` (if installed). This skill trades precision for plain words.
- **Re-pitching a message that did not land**, with the missing context, in Simplified Technical
  English and the project's own vocabulary, is `/discipline:wait-what` (if installed), which only the human fires.
- **A picture** (a diagram rather than a paragraph) is `/education:illustrate`; invoke it via the
  Skill tool.

## Next

- The reader wants to keep learning the topic across sessions: `/education:teach`.
- The reader wants a diagram instead of prose: `/education:illustrate`.

## Gotchas

- **Don't climb unasked.** Under a `plain` start, delivering the peer-level version first defeats
  the point: the user already didn't follow it.
- **The empty-argument referent is the assistant's output, not the user's.**
- **The analogy must map.** A decorative analogy that breaks under one step of pressure is worse
  than none; pick one whose structure mirrors the real thing.
- **Ground before you simplify.** Simplifying a fact recalled wrongly produces a confident, plain,
  wrong answer.
