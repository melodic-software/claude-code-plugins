---
name: questionnaire
description: "Turn a decision the user cannot answer — because another person holds the knowledge — into a Markdown questionnaire handed off async. Interviews the user only about the send (who it goes to, what they need back), never about the subject the recipient holds, then writes a discovery questionnaire aimed at the gap. Use for 'make a questionnaire for X', 'I need to ask my DBA/the client/legal about this', 'turn this into a doc someone else fills in', or when an interview branch defers to a person-arbiter; skip when the user can answer themselves (run /planning:interview) or when the answer is agent-lookupable."
argument-hint: "[topic]"
user-invocable: true
disable-model-invocation: true
---

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Some decisions are neither an agent-lookupable fact nor the user's to make — a *different person* holds the knowledge the decision needs. This skill turns that decision into a **questionnaire**: a Markdown document the user hands to one person to fill in async, or fills out together in a meeting. The recipient holds knowledge the user lacks; the questionnaire pulls it out of them.

This is the third routing bucket beside `/planning:interview`'s facts-vs-decisions split: facts the agent looks up, decisions the user makes, and person-held decisions this skill hands off. The deliverable is the document, full stop — delivery happens out-of-band (email, chat, a meeting), never through this skill.

## Stance

**Interview the send, not the subject.** Interview the user only about the *send*, which they can always answer: who it goes to, and what they need back. Never quiz the user about the subject the recipient holds — that knowledge gap is exactly why the questionnaire exists. The questions in the document target the **gap** between what the recipient knows and what the user needs.

**Route away when no one else holds the answer.** If it emerges that the user can answer the decision themselves (no third-party knowledge holder), do not produce a questionnaire for nobody — recommend `/planning:interview` and stop. Never invent a recipient to justify the artifact.

## The loop

1. **Who is it going to?** Ask, in one exchange, the recipient's role, expertise, and relationship to the user. This fixes the questionnaire's tone and how much context it must carry. Done when you know who the recipient is and what they know that the user doesn't.

2. **What do you need back?** Ask, in one exchange, the specific decisions or facts the user can't resolve alone and needs from this person. Done when you have a concrete list of what the user must walk away able to do or decide.

3. **Write the questionnaire.** Draft questions aimed at the gap from steps 1–2, per [`templates/questionnaire.md`](templates/questionnaire.md). Derive `<topic-slug>` from `$ARGUMENTS` or the current branch (kebab-case, ≤40 chars — shared with the sibling planning skills) and write the document to the topic's **memory slice** as `<memory_dir>/<topic-slug>/questionnaire-<recipient-role-slug>.md` (default `.work/`; the role slug — e.g. `dba`, `legal` — distinguishes questionnaires when one topic hands off to several people; roots resolve per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)), then report the path. Done when the file exists and every item the user named in step 2 is covered by a question.

The memory slice is deliberate: the document names a real person (name, role, relationship), and the memory tier's self-ignore guard keeps that PII out of git history. Never write the questionnaire to the working directory or a tracked path.

## Document structure

Frame the document as a **discovery questionnaire**: the user lacks context, the recipient holds it. Order questions most-important-first — async means you may only get one pass — and group them under `##` headings by theme once there are more than a handful. Every question carries one idea (never compound) with an answer stub beneath it. The literal shape is the bundled template.

## After the document

- **Delivery is the user's.** Report the path and stop. The skill never transmits anything.
- **Optional lifecycle tracking.** If the consumer's environment binds a work-item tracker (a `/work-items:track`-style seam), offer — never auto-file — an "awaiting answer from <role>" item carrying the questionnaire's title and topic only, never the recipient's name or the document body. Degrade gracefully: with no tracker bound, the document and its path are the complete deliverable.
- **When answers return,** the user resumes the deferred decision with the filled questionnaire as evidence — typically back through `/planning:interview` or the plan that deferred it.

## Upstream provenance

Adapted from Matt Pocock's `to-questionnaire` (mattpocock/skills, in-progress). No live upstream sync path — re-audit opportunistically.
