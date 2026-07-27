---
name: explain
description: "One-shot plain-language explainer — drops any concept, code, error, architecture, or the previous assistant response to genuinely plain words (concrete analogy, zero jargon), then layers altitude up only on request (high-school, then peer level). Use when: 'I don't understand this', 'I don't get it', 'what does this actually do', 'what does this mean', 'explain simply', 'ELI5', 'rephrase that'. Empty argument targets the previous assistant response (anaphora), so 'I don't get it' needs no topic named. This changes ALTITUDE — trades precision for plain words; when the ask is instead to reorganize a dense message faithfully without losing precision (chunk it one-decision-at-a-time, define its jargon, surface the decisions), that is a STRUCTURE change, adhd:clarify (if installed), not an altitude drop. Sibling to education:teach — hand off there for multi-session coaching; this is a single-shot comprehension check, not ongoing tutoring."
argument-hint: "[thing to explain] (empty = the previous assistant response)"
user-invocable: true
metadata:
  cheatsheet-stage: anytime
  cheatsheet-summary: Explain any concept or the last response in genuinely plain words
---

## Purpose

Explain one thing, once, in genuinely plain words. The object can be a concept, a
piece of code, an error, an architecture, or the assistant's own previous output.
The core move is an **altitude drop**: land the explanation at the lowest useful
altitude first — a concrete analogy, zero jargon — then layer altitude back up
**only when the user asks for it**. Michael Scott's "Why don't you explain this to
me like I'm five" (*The Office* US, S5E9 "The Surplus") is the tone anchor; the
[Feynman technique](https://fs.blog/feynman-technique/) is the method.

**Use when:** the user signals they didn't follow something — `I don't get it`,
`explain simply`, `ELI5`, `what does this actually mean`, `rephrase that`. **Skip
when:** the user wants ongoing, multi-session coaching with persistent state (hand
off to `/education:teach`); a plain inline answer already lands (just answer).

This skill auto-invokes (no `disable-model-invocation`) because "I don't get it"
should reach it without the user naming a command. Auto-trigger is best-effort;
`/education:explain` is the guaranteed path.

## The core move — plain-language first pass

1. **Identify the object.** With an argument, that is the thing. Empty argument →
   the **previous assistant response** (see "Empty argument" below).
2. **Ground it, don't recall it.** Re-read the actual artifact this turn — the
   message just sent, the file, the error text, the code. For an external concept,
   fetch a primary source rather than leaning on parametric memory (plugin
   doctrine: knowledge is grounded, not remembered).
3. **Drop to plain.** One concrete analogy from everyday life. No jargon, no term
   that itself needs prior knowledge. Short. If a technical word is unavoidable,
   define it inline in ordinary words the first time.
4. **Close with the handoff line** (see "Handoff").

Lead with the analogy and the "what it's actually doing," not with vocabulary.

## Empty argument — anaphora default

When invoked with no argument, the object is the **assistant's own previous
response** — the thing the user is reacting to. `I don't get it` needs no topic
named. Re-read that prior message, find the part most likely to have lost the
reader (the densest jargon, the biggest leap), and drop *that* to plain words.
Do not ask "explain what?" when the conversation makes the referent obvious. But
when there is **no prior assistant message** to resolve the anaphora against — a
cold start where the user opens the conversation with `I don't get it` and nothing
has been said yet — do not hallucinate a referent: ask "What would you like
explained?" instead of proceeding blind.

## Altitude layering — on request only

Start at rung 1. Climb only when the user asks ("go deeper", "more precise", "I
actually know X"). Never front-load a higher rung.

| Rung | Altitude | Move |
|------|----------|------|
| 1 (default) | **Plain / ELI5** | Concrete everyday analogy, zero jargon. The floor and the default landing. |
| 2 (on request) | **High-school** | Introduce one or two real terms of art, each defined as it appears. Keep the analogy as scaffolding. |
| 3 (on request) | **Peer** | Full precision, jargon allowed, edge cases and tradeoffs — the explanation a colleague in the field would want. |

Offer the next rung as a one-line invitation, not a wall of text: "That's the
five-year-old version — want the high-school one?"

## Feynman gap check

The plain-language pass is a comprehension self-test, not a rewording service. If
you **cannot** shed the jargon — if the only "explanation" you can produce still
leans on the very terms the user didn't follow, or on hand-waving — that is a
detected understanding gap, on the explainer's side. **Surface it honestly**
rather than papering over it: name the specific part you cannot yet reduce and
why, and ground harder (re-read the source, fetch the primary reference) before
claiming to explain it. A confident-sounding restatement of jargon is the failure
mode this check exists to catch.

## Handoff to `education:teach`

Close every explanation with a single lightweight line offering the multi-session
path — the first-party sibling in this same plugin:

> Want to actually learn this, not just get past it? `/education:teach topic <x>`
> runs a multi-session coached deep-dive.

One line, standard close. `explain` is one-shot; `teach` is the persistent,
mission-driven coach when the user wants ongoing depth or practice.

## Gotchas

- **Don't climb unasked.** The default is rung 1. Delivering the peer-level
  explanation first defeats the point — the user already didn't follow the
  peer-level version.
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
