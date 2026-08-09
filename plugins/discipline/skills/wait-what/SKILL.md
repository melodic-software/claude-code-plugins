---
name: wait-what
description: "Stop — that last message did not land. Re-pitch it: back up as far as needed, add the context that was missing, write in ASD-STE100 Simplified Technical English, and use the project's own ubiquitous language. Type /discipline:wait-what the moment you notice you are skimming; only you know when you stopped following."
user-invocable: true
disable-model-invocation: true
metadata:
  workflow-stage: anytime
  summary: Re-pitch the message that did not land — missing context added, plain register, project vocabulary
---

# Wait — what?

Wait — I don't understand where you've got to here. Re-pitch that: back up as
far as needed, give me the context I was missing, talk in ASD-STE100
Simplified Technical English (short sentences, one meaning per word, technical
terms exact), and use the project's ubiquitous language — read the nearest
domain glossary or context map, per the project's own convention, when one
exists; with none, plain technical English alone.

## A declared species in this plugin: NOT a corrector

Every sibling corrector re-anchors a standing discipline through the
re-anchor/audit/correct loop. This skill is a one-shot, user-fired
communication repair: the human — the only party who can detect that a message
did not land — fires it, and the re-pitch IS the repair. It deliberately stays
this small: a skill that fights unclear output fails by growing, because the
model reads the volume, not the plea. Nearest siblings, for routing:
`/discipline:tighten-your-output` when the problem is too many words, and
`/discipline:mind-your-maxims` when the standing cooperative-communication
discipline itself needs re-anchoring; this skill repairs the one message that
lost its reader.

## Boundaries

- **Never model-invoked.** `disable-model-invocation: true` is load-bearing:
  the model cannot detect that its reader stopped following, so an
  auto-fired re-pitch would be incoherent.
- **Re-pitch means re-ground, not compress.** Full technical precision stays;
  the premise the reader was missing comes back. A re-pitch that is shorter
  and blunter — but no clearer — is the failure this skill exists to avoid.
- **No glossary is a no-op, not an error.** The vocabulary half degrades
  silently; the register and missing-context halves always apply.
- **Excluded from batch sweeps.** No `discipline-batch` tier on purpose: a
  sweep must never fire a repair only the human can call for.
