---
description: "One-shot plain-language explainer. Drops any concept, code, error, architecture, or the previous assistant response to genuinely plain words (concrete analogy, zero jargon), then layers altitude up only on request (high-school, then peer level). Use when: 'I don't understand this', 'I don't get it', 'what does this actually do', 'what does this mean', 'explain simply', 'rephrase that'. Empty argument targets the previous assistant response (anaphora), so 'I don't get it' needs no topic named. This changes ALTITUDE, in PROSE. Trades precision for plain words; when the ask is instead to reorganize a dense message faithfully without losing precision, that is a STRUCTURE change, adhd:clarify (if installed), not an altitude drop. When the ask is for a picture (a diagram, a visual explainer, ELI5), that is a MEDIUM change, education:illustrate. Sibling to education:teach. Hand off there for multi-session coaching; this is a single-shot check, not ongoing tutoring."
argument-hint: "[thing to explain]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Explain any concept or the last response in genuinely plain words
---

## Purpose

Explain one thing, once, in genuinely plain words. The object can be a concept, a
piece of code, an error, an architecture, or the assistant's own previous output.
The core move is an **altitude drop**: land the explanation at the lowest useful
altitude first, a concrete analogy, zero jargon, then layer altitude back up
**only when the user asks for it**. The `explain_starting_rung` setting can move
the start to peer level ([Starting rung](#starting-rung-explain_starting_rung)). The
[Feynman technique](https://fs.blog/feynman-technique/) is the method.

**Use when:** the user signals they didn't follow something, `I don't get it`,
`explain simply`, `what does this actually mean`, `rephrase that`. **Skip
when:** the user wants ongoing, multi-session coaching with persistent state (hand
off to `/education:teach`); a plain inline answer already lands (just answer).

This skill auto-invokes (no `disable-model-invocation`) because "I don't get it"
should reach it without the user naming a command. Auto-trigger is best-effort;
`/education:explain` is the guaranteed path.

## The core move. Plain-language first pass

1. **Identify the object.** With an argument, that is the thing. Empty argument →
   the **previous assistant response** (see "Empty argument" below).
   **Done when** you can name the object in one sentence, or, on a cold start
   with no prior assistant message, have asked what to explain instead of
   guessing.
2. **Ground it, don't recall it.** Re-read the actual artifact this turn, the
   message just sent, the file, the error text, the code. For an external concept,
   fetch a primary source rather than leaning on parametric memory (plugin
   doctrine: knowledge is grounded, not remembered).
   **Done when** this turn's explanation cites a specific passage, file, error
   text, or fetched primary source you re-read here. A recalled paraphrase does
   not count.

   When the object is a subsystem of the codebase you are in, ground it through
   the discovery skills when they are among the available skills: invoke
   `/discovery:explore --output explain <subsystem>` for what the code does,
   `/discovery:trace-intent <subsystem>` for why it was built that way, and
   explain from what they return. Keep trace-intent's confidence wording: a
   reason it marked inferred stays hedged ("appears to", "likely"), and one it
   could not find stays "not found", in plain words. When those skills are not
   available, read the subsystem's files yourself and cite them; state a reason
   for a design choice only when a file you read gives it.
3. **Land at the starting rung.** At rung 1 (`plain`), use one concrete analogy
   from everyday life. No jargon, no term that itself needs prior knowledge.
   Short. If a technical word is unavoidable, define it inline in ordinary words
   the first time. At rung 3 (`peer`), open with one precise sentence defining
   the object, as an engineer in the field would say it, then apply that
   definition to the user's example at full precision.
   **Done when**, at rung 1, the explanation contains one everyday analogy whose
   structure maps to the object, a "what it's actually doing" line, and no
   leftover term that is not defined inline in ordinary words; at rung 3, its
   first sentence is that precise definition.
4. **Close with the handoff line** (see "Handoff").
   **Done when** the response ends with the single standard `/education:teach`
   invitation line, followed by the one-line starting-rung report.

At rung 1, lead with the analogy and the "what it's actually doing," not with vocabulary.

## Empty argument. Anaphora default

When invoked with no argument, the object is the **assistant's own previous
response**. The thing the user is reacting to. `I don't get it` needs no topic
named. Re-read that prior message, find the part most likely to have lost the
reader (the densest jargon, the biggest leap), and drop *that* to plain words.
Do not ask "explain what?" when the conversation makes the referent obvious. But
when there is **no prior assistant message** to resolve the anaphora against, a
cold start where the user opens the conversation with `I don't get it` and nothing
has been said yet, do not hallucinate a referent: ask "What would you like
explained?" instead of proceeding blind.

## Starting rung: `explain_starting_rung`

Resolve the starting rung before writing the explanation. Layers, lowest first,
a later one winning (key contract:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md)):

| Layer | Value |
|---|---|
| default | `plain` |
| `userConfig` | `${user_config.explain_starting_rung}`. A literal unexpanded token means unset; `plain` here is reported as the default, since the two cannot be told apart. |
| repository | `explain_starting_rung` in `docs/conventions/education.yaml` at the repository root |

To read the repository layer, find the root with `git rev-parse --show-toplevel`,
then run
`bash "${CLAUDE_PLUGIN_ROOT}/skills/explain/scripts/parse-concern-value.sh" "<root>/docs/conventions/education.yaml" explain_starting_rung`.
Empty output means the layer is unset. Skip this layer outside a git working
tree, or when the root is `$HOME` or an ancestor of it.

A value other than `plain` or `peer` in a layer is named in the reply, with the
file or `userConfig` that held it, the key, and the value, and that layer is
dropped. A valid higher layer still wins; with none, the run continues on the
default, `plain`. It never stops on an invalid value and never falls through to
a lower layer's value.

Report the result as the last line of the reply, after the handoff line, e.g.
`explain_starting_rung: peer (userConfig)` or
`explain_starting_rung: plain (default)`.

## Altitude layering. On request only

Start at the resolved rung: rung 1 for `plain`, rung 3 for `peer`. Move only
when the user asks ("go deeper", "more precise", "I actually know X", "say that
more simply"). Never front-load a rung above the starting one.

| Rung | Altitude | Move |
|------|----------|------|
| 1 (`plain` start) | **Plain** | Concrete everyday analogy, zero jargon. The floor and the default landing. |
| 2 (on request) | **High-school** | Introduce one or two real terms of art as vocabulary-ladder entries: the term, its definition in ordinary words, and one modeled "you can now say: …" sentence showing the term doing work in the user's own next prompt. Keep the analogy as scaffolding. |
| 3 (on request, or `peer` start) | **Peer** | Full precision, jargon allowed, edge cases and tradeoffs, the explanation a colleague in the field would want. A `peer` start opens with one precise sentence of definition. |

Offer one other rung as a one-line invitation, not a wall of text. From a
`plain` start, offer the next rung up: "That's the plain version, want the
high-school one?" From a `peer` start, offer the plain version instead of a
higher rung: "Want the plain version?"

## Register. No framing labels or pacing narration

State the explanation directly. No labels that announce a sentence ("Key
insight:", "The big idea:", "Bottom line:"), no pacing narration ("let's
pause here", "take a moment", "step 2 of 4"), no comprehension questions and no
request to say it back. The single one-line rung offer and the handoff line are
the only lines addressed to the reader about what comes next.

## Feynman gap check

The plain-language pass is a comprehension self-test, not a rewording service. If
you **cannot** shed the jargon, if the only "explanation" you can produce still
leans on the very terms the user didn't follow, or on hand-waving, that is a
detected understanding gap, on the explainer's side. **Surface it honestly**
rather than papering over it: name the specific part you cannot yet reduce and
why, and ground harder (re-read the source, fetch the primary reference) before
claiming to explain it. A confident-sounding restatement of jargon is the failure
mode this check exists to catch.

## Success condition (original-ask invocations only)

When the explanation serves a task the user was stuck on, the success test is their **next
prompt**: it names what they mean in the newly plain terms instead of re-gesturing at the
confusion. Judge the explanation by that, and shape rung-2 vocabulary entries so the user can
reuse them. A bare comprehension ask with no task behind it ("I don't get it", full stop) has no
next-prompt contrast; this check does not apply there.

## Handoff to `education:teach`

Close every explanation with a single lightweight line offering the multi-session
path, the first-party sibling in this same plugin:

> Want to actually learn this, not just get past it? `/education:teach topic <x>`
> runs a multi-session coached deep-dive.

One line, standard close; only the starting-rung report line follows it. `explain` is one-shot; `teach` is the persistent,
mission-driven coach when the user wants ongoing depth or practice.

## Next

- The reader wants to keep learning the topic across sessions: `/education:teach`.
- The reader wants a diagram instead of prose: `/education:illustrate`.

## Gotchas

- **Don't climb unasked.** The default start is rung 1. Under a `plain` start,
  delivering the peer-level explanation first defeats the point: the user
  already didn't follow the peer-level version.
- **Anaphora referent is the *assistant's* output, not the user's.** Empty
  argument explains what the assistant just said, which the user is reacting to.
- **Analogy must actually map.** A decorative analogy that breaks under one step
  of pressure is worse than none. Pick one whose structure mirrors the real thing.
- **Ground before you simplify.** Simplifying a fact you recalled wrongly produces
  a confident, plain, wrong answer. Re-read or fetch first.

## What this skill does NOT do

- **Not multi-session coaching.** No workspace, mission, glossary, or persistent
  learning state. When the user wants ongoing tutoring, hand off to
  `/education:teach`.
- **Not `teach`'s `explain` *action*.** `/education:teach explain <concept>` writes
  a durable lesson into an active `teach` learning workspace. This skill,
  `/education:explain`, is a standalone one-shot with no workspace. Namespacing
  keeps them distinct; on "I don't get it" only this skill auto-fires
  (`teach` sets `disable-model-invocation`).
- **Not a rewording service.** If the jargon can't be shed, that's a gap to
  surface (Feynman gap check), not a synonym to swap in.
- **Not a restructure.** A dense, decision-heavy message that has the right content in the
  wrong shape is `adhd:clarify` (if that plugin is installed): same precision, same
  words, one decision at a time. This skill trades precision for plain words.
- **Not the reader's stop signal.** When the reader says the last message did not land
  and wants it re-pitched with the missing context, in Simplified Technical English and
  the project's own vocabulary, that is `/discipline:wait-what` (if installed), which only
  the human can fire. This skill answers "explain this"; that one repairs one message.
- **Not a picture.** This skill changes altitude and stays in prose. When the user
  wants a visual explainer instead, a diagram rather than a paragraph, that is the
  sibling `/education:illustrate`; invoke it via the Skill tool. It has two fixed
  presets rather than a ladder, which is the trade it makes for the medium.
