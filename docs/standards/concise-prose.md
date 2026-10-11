# Concise prose without semantic loss

Write prose as briefly as clarity and completeness allow. Remove words only
when the result preserves the same meaning and remains as easy to apply. This
is a reasoning-only judgment: word or sentence counts can flag a passage for
review, but they cannot prove that a shorter version is equivalent.

This rule owns wording, not whether content belongs or where it lives.
[`documentation-existence.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/documentation-existence.md) owns whether a
page may exist at all;
[`simpler-code.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/simpler-code.md) owns reductions to executable code;
[`progressive-disclosure.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/progressive-disclosure.md) owns information
layering; and [`reference-dont-duplicate.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/reference-dont-duplicate.md) and
[`documentation-and-citations.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/documentation-and-citations.md) jointly own
whether a fact stays inline or is cited. [`naming.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/naming.md) owns
identifiers, and [`legacy-and-migration-debt.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/legacy-and-migration-debt.md)
owns whether historical narration belongs at all. Apply this convention to the
prose that remains after those decisions.

## Remove non-semantic overhead

Cut filler openings, empty intensifiers, reflexive hedges, unnecessary
modifiers, repeated restatements, and multi-word phrases that a precise word
can replace. Keep a hedge or qualifier when it communicates real uncertainty,
confidence, or scope. The test is whether each word adds meaning or helps the
reader act;
[Digital.gov](https://digital.gov/guides/plain-language/principles/short-simple)
and the
[Microsoft Writing Style Guide](https://learn.microsoft.com/en-us/style-guide/word-choice/use-simple-words-concise-sentences)
recommend removing words that add no substance.

Do not vary terminology merely to avoid repetition. Use one term for one
concept. Repeat a word deliberately when the repetition prevents ambiguity or
keeps parallel conditions explicit, as Google's
[global-audience guidance](https://developers.google.com/style/translation#use-helper-words-and-optional-words)
recommends.

State the point literally. Where a plain phrase says it, use that phrase
instead of a metaphor or flourish: figurative wording makes the reader
translate it back into the claim, and the translation can go wrong.

## Preserve the whole contract

A shorter version is wrong when it changes what the reader must know or do.
Keep all of the following when they carry meaning:

- normative force, scope, actors, and required actions;
- conditions, exceptions, alternatives, and ordering;
- thresholds, defaults, units, and other exact values;
- definitions and context needed to remove ambiguity;
- rationale needed to evaluate or maintain a decision; and
- examples needed to understand a concept or apply a rule.

Do not turn explicit content into an inference the reader must supply. W3C's
[supplemental cognitive-accessibility guidance](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o3p12-implicit-explained/)
recommends explaining implied or ambiguous information; it informs this clarity
judgment but is not conformance-required WCAG guidance.

## Shorten structure, not meaning

Prefer one point per sentence and one topic per paragraph. Split compound
thoughts, lead with the point or condition that governs what follows, and use a
list when several parallel items must remain distinct. Digital.gov's
[clear-and-short guidance](https://digital.gov/guides/plain-language/writing/clear-short)
and W3C's
[succinct-text pattern](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o3p05-succinct-text/)
use this structure to make information easier to process.

Length is a review trigger, not a target. A long sentence or paragraph deserves
a clarity check; keep it when splitting it would obscure a relationship, add
redundancy, or make the prose less natural. A short passage still fails when it
is incomplete, ambiguous, or abrupt.

## Sources

- [Digital.gov, "Short and simple"](https://digital.gov/guides/plain-language/principles/short-simple)
- [Digital.gov, "Clear and short"](https://digital.gov/guides/plain-language/writing/clear-short)
- [Microsoft Writing Style Guide, "Use simple words, concise sentences"](https://learn.microsoft.com/en-us/style-guide/word-choice/use-simple-words-concise-sentences)
- [Microsoft Learn style and voice quick start](https://learn.microsoft.com/en-us/contribute/content/style-quick-start)
- [Google developer documentation style guide, "Write for a global audience"](https://developers.google.com/style/translation)
- [W3C cognitive accessibility pattern, "Keep Text Succinct"](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o3p05-succinct-text/)
- [W3C cognitive accessibility pattern, "Explain Implied Content"](https://www.w3.org/WAI/WCAG2/supplemental/patterns/o3p12-implicit-explained/)
- [GOV.UK, "Publishing accessible documents"](https://www.gov.uk/guidance/publishing-accessible-documents)
- [ISO 24495-1:2023, *Plain language — Part 1: Governing principles and guidelines*](https://www.iso.org/standard/78907.html) <!-- ai-slop-ignore: em dash is part of the literal ISO standard title -->
