---
type: llm
arm: both
---

Judge the fenced README only, reading it top to bottom as a developer who has never used loglet.

The source notes use three domain terms before they define them, or without defining them at all: `checkpoint`, `collector` and `tail set`. For each term that appears in the README, find the first sentence that relies on it, meaning a sentence whose sense the reader cannot follow without knowing what the term means.

A term counts as introduced when the README says what it is at or before that sentence: a definition, an apposition ("the collector, the HTTP endpoint that receives your log lines"), a glossary or terms section placed before the first use, or a link-free gloss in the same sentence. A term counts as named assumed knowledge when the README says, before or at the first use, that it expects the reader to already know the term (for example "This README assumes you already run a log collector").

PASS only when every one of these terms that the README uses is introduced before a sentence relies on it, or is named as assumed reader knowledge. A term the README does not use at all does not affect the verdict, as long as the fact it carried is still stated in other words.

FAIL otherwise: when any of these terms appears in a sentence that relies on it before the README introduces it or names it as assumed knowledge, when a definition only comes after that first use, or when the reply has no fenced README.
