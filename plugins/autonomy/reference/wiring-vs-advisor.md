# Wiring vs advisor

Normative principle governing how guided setup (and every capability slice that extends it)
lands change in an adopting org.

## WIRE

Setup WIRES a target — writes the change itself — when the surface is machine-editable, local,
and reviewable: repository files, settings files, pipeline definitions, infrastructure code.
Wiring always lands as reviewable changes; silent mutation of any surface is a defect.

## ADVISE

Setup ADVISES — emits the steps and surfaces the cost, but does not write — when the surface
is org-external, entitlement-gated, paid, or GUI-only.

## Paid is always advisory first

Anything that costs money is advisory + explicit opt-in first, regardless of wireability. The
cost is surfaced before the opt-in question is asked; a declined opt-in falls back to the free
default, never to silence.
