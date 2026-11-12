# Source records for the default layer set

The four layers this skill falls back to are this plugin's selections from published standards,
never copies of them and never this plugin's own invention. Each carries a record in the
links-only shape (our decision and a pointer): what we took and where
to read the standard live.

Read this to judge how faithful a layer is, to cite a layer, or to decide whether a standard has
moved since the selection was made.

## Diátaxis: the mode layer

We use the framework's four modes, and the compass that selects between them, as the framework
defines them; the framework settles any mode question this skill does not cover.

- **Pointer**: for the modes and the compass, see [diataxis.fr](https://diataxis.fr).

## Google developer documentation style: the address layer

The address rules are our selection from the guide's highlights, not the guide; the guide settles
anything this file does not cover.

- **Pointer**: for the guide and its highlights, see
  [developers.google.com/style](https://developers.google.com/style).

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

Claiming STE conformance for a document needs the specification; sentences that load one idea at a
time need only the principles.

### AI-checked STE is plausible, not verified

We treat an AI checker's STE verdict, and this skill's own output, as plausible and unverified:
the text can be plain and short with nobody having verified conformance, and the dictionary rules
cannot be checked without the specification, which this plugin does not bundle. Never describe
model-written or model-checked text as STE-conformant.

### Instruction length is a target

The instruction-length rule is a target, not a hard cap: a sentence may run over when splitting it
would cut one action or its condition into fragments. For the guidance behind this choice, see the
pointer below.

- **Pointer**: [Prompting Claude Fable 5.2: review instructions written for earlier models](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-2#review-instructions-written-for-earlier-models).
- **Recheck trigger**: that section changes its advice on hard style limits, or a new model's
  prompting guide addresses sentence-length rules.

## Global English: the ambiguity layer

The ambiguity rules are our selection from Kohl's guidelines for prose that survives non-native
readers, translators, and machine parsers.

- **Pointer**: for the guidelines, see Kohl, *The Global English Style Guide* (SAS Press).

## Why these four and not one

Each answers a different question, and none answers another's. Diátaxis decides what kind of
document this is, not sentences. Google's guide decides how a sentence addresses its reader, not
how much it carries. STE decides how much one sentence carries, not whether it can be read two
ways. Global English decides that, not document shape. Dropping one leaves its question
unanswered.
