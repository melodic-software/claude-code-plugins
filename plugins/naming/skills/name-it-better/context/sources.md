# Method sources — name-it-better

The naming CRITERIA are owned elsewhere (the consuming org's conventions —
see the skill body). This file grounds the skill's METHOD: how candidates
are generated, why generators run blind, and what the `tournament` mode is
actually adapted from. Read it only when judging a method question or
extending the skill. Tiers: PRIMARY = author's own words / official
spec; AUTHORITATIVE = faithful canonical write-up by the originators or
their collaborators; SECONDARY = derivative.

## Naming as a process (staged refinement)

The backbone of the default pass's distinct lenses. A name is refined
through stages rather than guessed in one shot: from missing/misleading,
to obvious-nonsense, to honest, to completely-honest, to
does-the-right-thing, to intent-revealing, to domain-abstraction. The
"responsibility-literal → moment-of-use → domain-lore" lenses map onto
the honest → intent → domain-abstraction progression.

- Origin, Arlo Belshee ("Read by Refactoring"): [belshee-origin] — PRIMARY.
  Flag: this host was DNS-unreachable during research, so Belshee's exact
  per-stage prose is corroborated by the Deep Roots rewrite below rather
  than quoted from the origin.
- Canonical rewrite, Tim Ottinger + Llewellyn Falco: [deeproots-series]
  and [deeproots-path] — AUTHORITATIVE. Confirm the ordered stages and the
  three-phase structure.

## Naming criteria lineage (Ottinger / Clean Code)

Backs the scoring rubric's shape (the authoritative criteria source of
truth is the consuming org's conventions).

- Ottinger's Rules: [ottinger-rules] — AUTHORITATIVE. Intention-revealing,
  avoid disinformation, pronounceable, no encodings, one word per concept,
  meaningful in context.
- Clean Code, ch. 2 "Meaningful Names" (Martin, with Ottinger):
  [clean-code-ch2] — PRIMARY.

## Domain language

Backs the domain-lore lens and the "name from the shared domain
vocabulary" criterion.

- DDD Reference (Eric Evans): [ddd-reference] — PRIMARY.
- Ubiquitous Language (Fowler): [fowler-ubiquitous] — AUTHORITATIVE.

## Blind generation → human convergence (anti-anchoring)

Why generators run BLIND to the conversation and the human always makes
the final pick: diverge widely from independent perspectives, then
converge once — and keep the first-seen suggestion from anchoring the
choice.

- Double Diamond (diverge/converge), UK Design Council: [double-diamond]
  — AUTHORITATIVE.
- Anchoring bias, Tversky & Kahneman (1974), "Judgment under Uncertainty":
  [tk-1974] (open PDF: [tk-1974-pdf]) — PRIMARY. First value seen biases
  the final judgment; independent-before-shared review reduces it.

## `tournament` mode — adapted, NOT a documented naming technique

HONEST FLAG: there is no primary source describing a "naming tournament"
or "naming bracket" method for choosing identifiers. The mode is an
ADAPTATION, presented as a local convergence mechanism, not an
established naming standard. It borrows two documented, unrelated things:

- Elimination brackets (single/double elimination): [elim-bracket] —
  SECONDARY (generic, not naming).
- Pairwise social-choice aggregation (Condorcet / Copeland / Minimax) for
  turning head-to-head judgements into a ranking: [condorcet] — the
  rigorous basis if judges score candidates pairwise.

## Framework / style-guide naming (supporting)

- .NET naming guidelines (Microsoft): [dotnet-naming] — PRIMARY.
- Kevlin Henney, "Seven Ineffective Coding Habits" (naming): [henney] —
  PRIMARY. Meaning over word-count; "adding words is not adding meaning".
- Google style guides (per-language naming): [google-style] — PRIMARY.

[belshee-origin]: https://arlobelshee.com/good-naming-is-a-process-not-a-single-step/
[deeproots-series]: https://www.digdeeproots.com/articles/naming-process/naming-as-a-process/
[deeproots-path]: https://www.digdeeproots.com/articles/naming-process/naming-as-a-process-learning-path/
[ottinger-rules]: https://exelearning.org/wiki/OttingersNaming/
[clean-code-ch2]: https://www.oreilly.com/library/view/clean-code-a/9780136083238/chapter02.xhtml
[ddd-reference]: https://www.domainlanguage.com/wp-content/uploads/2016/05/DDD_Reference_2015-03.pdf
[fowler-ubiquitous]: https://martinfowler.com/bliki/UbiquitousLanguage.html
[double-diamond]: https://en.wikipedia.org/wiki/Double_Diamond_(design_process_model)
[tk-1974]: https://www.science.org/doi/10.1126/science.185.4157.1124
[tk-1974-pdf]: https://www.cs.tufts.edu/comp/150AIH/pdf/TverskyKa74.pdf
[elim-bracket]: https://en.wikipedia.org/wiki/Double-elimination_tournament
[condorcet]: https://en.wikipedia.org/wiki/Condorcet_method
[dotnet-naming]: https://learn.microsoft.com/en-us/dotnet/standard/design-guidelines/naming-guidelines
[henney]: https://www.infoq.com/presentations/7-ineffective-coding-habits/
[google-style]: https://google.github.io/styleguide/
