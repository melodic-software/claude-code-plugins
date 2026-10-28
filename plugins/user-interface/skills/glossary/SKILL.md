---
description: "Reverse term lookup for interface design and front-end behavior: the name for an effect, detail or behavior described without its name, and the line between near-synonyms. Use when someone asks what a thing is called ('the bouncy thing when a popover opens', 'the gap between two particular letters'), which of two close terms they mean ('clip or mask'), or a vague feel request ('make it snappier') needs named terms."
argument-hint: "[<description>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Name the design or front-end term for a described effect, detail or behavior
---

# Glossary

Name the term for what `$ARGUMENTS` describes, or for the effect, detail or behavior the
conversation is trying to name. A request built on the right word gets the right result; a vague
one gets a vague interface.

**Arguments.** `[<description>]`: the loose description to name. Without one, use what the
conversation describes, and ask only when nothing does.

The project's design system and docs win: when they already name the thing, answer with their
name and give the general term beside it.

## Name it

1. **Read for the sensation or behavior**, not the keywords: what the eye sees, what the hand
   feels, or what the interface does.
2. **Pick the term file** for its category from the list below and read the matching section. A
   category with no term file yet is answered from the field's established vocabulary, saying the
   glossary has no entry for it.
3. **Answer with the term first**, then its definition in a line. When two terms compete, name one
   or two alternates and the line between them, so the user learns the boundary as well as the
   word.
4. **Turn a feel request into named terms.** "Snappier" or "smoother" becomes the terms that carry
   it (an easing, a duration, a spring), so the request that builds it can name each one.
5. **When no term fits**, name the closest term and say it is an approximation, or describe the
   thing in the files' words ("a stagger of scale-in entrances"). Never coin a term. When even the
   closest term is a guess, ask for a reference image, a recording or a link to an example.

   Done when the answer names a term with its definition, or names the closest term as an
   approximation and asks for a reference.

## Term files

| File | Covers |
|---|---|
| [reference/motion.md](reference/motion.md) | Motion: entrances and exits, sequencing and timing, transforms, transitions between states, scroll, feedback and interaction, easing, springs, looping, polish, performance terms, animation principles |

## Next

- A named motion to build: /user-interface:write-animation.
- A named visual change to style: /user-interface:write-css.

## Gotchas

- A lookup answers with a name, not an implementation: building the thing belongs to the skill
  that writes it.
- Two terms that look interchangeable usually differ on one axis (hard or soft edge, overshoot or
  none, one element or two); name that axis instead of calling them synonyms.
- A term the user already used correctly needs no correction; confirm it and add the boundary only
  when it matters to the request.
