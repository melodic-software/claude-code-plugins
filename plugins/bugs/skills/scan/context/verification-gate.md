# The verification gate: the precision stage of `/bugs:scan`

Loaded on demand by `/bugs:scan` Step 4. The gate is **one separate fresh-context subagent per
candidate**, dispatched by the scan skill on the gate role its sizing table names, never the hunter
that produced the candidate.

Why separate and fresh: a model re-checking its own work rubber-stamps it. The gate must arrive with
no memory of why the candidate looked convincing, carrying only the candidate, the code, and a mandate
to kill it.

## The rule and the prompt

The rule for running the scanned repository's code, the evidence labels and the gate prompt are in
[`run-reviewed-code.md`](../../../reference/run-reviewed-code.md) in the plugin's `reference/` directory,
this plugin's copy of the marketplace contract. Give the gate every block of its "The gate prompt"
section verbatim, with the candidate as the finding it judges. The scan's main thread decides
whether a proposed check runs by that file's "Who counts as unattended" and "Asking for a check"
sections; neither is part of the gate prompt.

A verification subagent can return a verdict without having done the work. The gate therefore
opens the cited file and reads the surrounding code, attempts each falsification route, and states
which routes it tried and what each one showed; a verdict that names no route is not a verdict.

## What the gate receives

- The single candidate: symptom, `path:line`, evidence quote, claimed fault, claimed trigger, impact.
- Read access to the repository.
- Nothing else: no other candidates, no hunter rationale, no prior verdicts. Blackbox verification is
  cheap precisely because context transfer is minimal.

## Labels in the scan

A surviving candidate is `reproduced` or `verified-by-reading`, by the contract's table. A refuted
candidate goes to the report's refuted tail with its refuting argument, and a candidate whose gate
a verification level skipped is `unverified` (SKILL.md Step 4). `/bugs:scan` writes no
`not-attempted` label: every gated-set candidate is gated.

## Retained-refuted output contract

Refuted candidates are **returned, never dropped**. An adversarial gate of this kind kills the large
majority of candidates, and some of those kills are wrong; silently discarding them denies a human the
chance to overturn one and lets the same dead candidate resurface next run. The gate returns every
candidate in one of the two shapes the contract's "The gate prompt" names.

## Boundaries

- Read-only, as the contract's gate boundaries say.
- One candidate per dispatch. The scan skill owns comparing and deduplicating candidates.
- A better bug the gate noticed while reading is one line with its `path:line`; the scan records it
  in the report's side observations, and the next hunt wave can pick it up.
