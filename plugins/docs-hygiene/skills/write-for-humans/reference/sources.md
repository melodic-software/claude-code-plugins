# Source records for the default layer set

The four layers this skill falls back to are **distilled paraphrases** of published standards, never
copies of them, and none of them is this plugin's own invention. Each carries a four-part drift
stamp so a later reader can tell what was claimed, on what basis, when it was last true, and what
event should send someone back to check.

Read this when you need to know how faithful a layer is, cite a layer to someone, or decide whether
a standard has moved since the port.

## Diátaxis — the mode layer

- **Claim.** The four modes, and the doing/understanding × learning/work compass that selects
  between them, are as the framework defines them.
- **Basis.** [diataxis.fr](https://diataxis.fr).
- **As of.** 2026-07-18.
- **Recheck trigger.** The framework publishes a revision that renames a mode or changes either
  compass axis.

## Google developer documentation style — the address layer

- **Claim.** The address rules paraphrase the guide's own highlights; they are a selection, not the
  guide, and the guide settles anything this file does not cover.
- **Basis.** [developers.google.com/style](https://developers.google.com/style).
- **As of.** 2026-07-18.
- **Recheck trigger.** The guide's Highlights page changes a rule stated in `sentence-rules.md`.

## ASD-STE100 Simplified Technical English — the load layer

- **Claim.** The load rules are the transferable core of the specification's writing rules. The
  numbered rules and the controlled dictionary live in the specification itself and are **not**
  reproduced here — this layer is a set of principles derived from the standard, and a document
  written to it is not thereby STE-conformant.
- **Basis.** [asd-ste100.org](https://asd-ste100.org), Issue 9 (2025).
- **As of.** 2026-07-18.
- **Recheck trigger.** A new Issue of the specification is published.

This caveat is load-bearing rather than boilerplate. Anyone claiming STE conformance for a document
needs the specification; anyone wanting sentences that load one idea at a time can use the
principles alone.

## Global English — the ambiguity layer

- **Claim.** The ambiguity rules paraphrase Kohl's guidelines for writing prose that survives
  non-native readers, translators, and machine parsers.
- **Basis.** Kohl, *The Global English Style Guide* (SAS Press).
- **As of.** 2026-07-18.
- **Recheck trigger.** A new edition is published.

## Why these four and not one

Each answers a different question, and no one of them answers another's. Diátaxis decides what kind
of document this is and says nothing about sentences. Google's guide decides how a sentence
addresses its reader and says nothing about how much it carries. STE decides how much one sentence
carries and says nothing about whether it can be read two ways. Global English decides that, and
says nothing about document shape. Dropping one leaves its question unanswered rather than answered
worse.
