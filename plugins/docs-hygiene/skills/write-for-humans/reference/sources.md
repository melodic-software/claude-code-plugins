# Source records for the default layer set

The four layers this skill falls back to are this plugin's selections from published standards,
never copies of them, and none of them is this plugin's own invention. Each carries a record in
the links-only shape (our decision, a pointer, an as-of date, a recheck trigger) so a later reader
can tell what we took, where to read the standard live, when the selection was last checked, and
what event should send someone back to check.

Read this when you need to know how faithful a layer is, cite a layer to someone, or decide whether
a standard has moved since the selection was made.

## Diátaxis: the mode layer

We use the framework's four modes, and the compass that selects between them, as the framework
defines them; the framework settles any mode question this skill does not cover.

- **Pointer**: for the modes and the compass, see [diataxis.fr](https://diataxis.fr).
- **As of**: 2026-07-18
- **Recheck trigger**: the framework publishes a revision that renames a mode or changes either
  compass axis.

## Google developer documentation style: the address layer

The address rules are our selection from the guide's highlights, not the guide; the guide settles
anything this file does not cover.

- **Pointer**: for the guide and its highlights, see
  [developers.google.com/style](https://developers.google.com/style).
- **As of**: 2026-07-18
- **Recheck trigger**: the guide's Highlights page changes a rule stated in `sentence-rules.md`.

## ASD-STE100 Simplified Technical English: the load layer

The load rules are principles we derive from the specification's writing rules. The numbered rules
and the controlled dictionary live in the specification and are **not** reproduced here, and a
document written to this layer is not thereby STE-conformant.

- **Pointer**: for the specification, Issue 9 (2025), see [asd-ste100.org](https://asd-ste100.org);
  its writing rules on instruction length, verb forms and paragraph length are rules 5.1, 3.2, 6.5
  and 6.6. For the STEMG position on AI, see the
  [white paper](https://www.asd-ste100.org/assets/files/WhitePaper-ASD-STE100_and_AI.pdf) and the
  entry "White Paper: Simplified Technical English and Artificial Intelligence" on the
  [STE downloads page](https://www.asd-ste100.org/STE_downloads.html).
- **As of**: 2026-10-02
- **Recheck trigger**: a new Issue of the specification is published, or STEMG revises its paper on
  AI.

This caveat is a real constraint, not boilerplate. Anyone claiming STE conformance for a document
needs the specification; anyone wanting sentences that load one idea at a time can use the
principles alone.

### AI-checked STE is plausible, not verified

We treat an AI checker's STE verdict, and this skill's own output, as plausible and unverified. The
text can be plain and short, and nobody has verified conformance. The dictionary rules cannot be
checked without the specification, which this plugin does not bundle. Never describe model-written
or model-checked text as STE-conformant.

## Global English: the ambiguity layer

The ambiguity rules are our selection from Kohl's guidelines for prose that survives non-native
readers, translators, and machine parsers.

- **Pointer**: for the guidelines, see Kohl, *The Global English Style Guide* (SAS Press).
- **As of**: 2026-07-18
- **Recheck trigger**: a new edition is published.

## Why these four and not one

Each answers a different question, and no one of them answers another's. Diátaxis decides what kind
of document this is and says nothing about sentences. Google's guide decides how a sentence
addresses its reader and says nothing about how much it carries. STE decides how much one sentence
carries and says nothing about whether it can be read two ways. Global English decides that, and
says nothing about document shape. Dropping one leaves its question unanswered rather than answered
worse.
