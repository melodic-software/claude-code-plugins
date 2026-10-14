---
description: "Turn a decision another person holds into an async Markdown questionnaire, interviewing the user only about the send, never the subject. Use when: 'make a questionnaire for X', 'I need to ask my DBA/the client/legal about this', 'turn this into a doc someone else fills in', 'I don't know, that's the client's call', 'send this to someone else to answer', 'write up questions for our security team', or an interview branch defers to a person. Self-answerable: /planning:interview."
argument-hint: "[topic]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: contract
  summary: Turn a decision someone else must answer into an async questionnaire
---

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Some decisions are neither an agent-lookupable fact nor the user's to make: a *different person*
holds the knowledge. Turn that decision into a **questionnaire**, a Markdown document the user hands
to one person to fill in async, or fills out with them in a meeting. This is the third routing
bucket beside `/planning:interview`'s facts (the agent looks up) and decisions (the user makes).
The deliverable is the document; delivery (email, chat, a meeting) happens out-of-band, never
through this skill.

## Stance

**Interview the send, not the subject.** Ask the user only about the *send*, which they can always
answer: who it goes to, and what they need back. Never quiz the user about the subject the
recipient holds. The document's questions target the **gap** between what the recipient knows and
what the user needs.

**Route away when no one else holds the answer.** If the user can answer the decision themselves
(no third-party knowledge holder), invoke `/planning:interview` via the Skill tool and stop this
skill. Never invent a recipient to justify the artifact. Invoke it, never just mention it: bare
`/name` prose reads as advice to the human and strands the decision.

## The loop

1. **Who is it going to?** Ask, in one exchange, the recipient's role, expertise, and relationship
   to the user; this fixes the tone and how much context the document must carry. Done when you
   know who the recipient is and what they know that the user doesn't.

2. **What do you need back?** Ask, in one exchange, the specific decisions or facts the user can't
   resolve alone and needs from this person. Done when you have a concrete list of what the user
   must walk away able to do or decide. Run each item through the self-answer step
   ([`${CLAUDE_PLUGIN_ROOT}/context/self-answer.md`](../../context/self-answer.md)) first: leave
   out a fact a lookup settles, from a connected system or one the user connects when offered; keep
   a fact no lookup settles for the person.

3. **Write the questionnaire.** Draft questions aimed at the gap from steps 1–2, per
   [`templates/questionnaire.md`](templates/questionnaire.md). Derive `<topic-slug>` from
   `$ARGUMENTS` or the current branch (kebab-case, ≤40 chars, shared with the sibling planning
   skills) and write the document to the topic's **memory slice** as
   `<memory_dir>/<topic-slug>/questionnaire-<recipient-role-slug>.md` (default `.work/`; the role
   slug, for example `dba` or `legal`, distinguishes questionnaires when one topic hands off to
   several people; placement per
   [`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)),
   then report the path. If a file already exists at that path (same topic, same role), never
   overwrite silently: ask whether to **revise** it (fold the new questions in) or write a **new**
   document with a short disambiguating suffix (`questionnaire-<recipient-role-slug>-2.md`, or a
   sharper role slug). Done when the file exists and every item the user named in step 2 is covered
   by a question.

The document names a real person, and the memory tier's self-ignore guard keeps that PII out of git
history: never write the questionnaire to the working directory or a tracked path.

## Document structure

Frame the document as a **discovery questionnaire**: the user lacks context, the recipient holds
it. Order questions most-important-first (async may give only one pass), and group them under `##`
headings by theme once there are more than a handful. Every question carries one idea (never
compound) with an answer stub beneath it. The literal shape is the bundled template.

## Next

- The answers came back on an interview branch: /planning:interview.
- The answers came back on a PRD question: /planning:prd.

## After the document

- **Delivery is the user's.** Report the path and stop. The skill never transmits anything.
- **Optional lifecycle tracking.** If the consumer's environment binds a work-item tracker (a
  `/work-items:track`-style seam), offer, never auto-file, an "awaiting answer from <role>" item
  carrying the questionnaire's title and topic only, never the recipient's name or the document
  body. With no tracker bound, the document and its path are the complete deliverable.
- **When answers return,** the user resumes the deferred decision with the filled questionnaire as
  evidence, typically back through `/planning:interview` or the plan that deferred it.
