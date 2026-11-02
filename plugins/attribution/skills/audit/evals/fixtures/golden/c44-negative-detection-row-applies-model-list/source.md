# Lumen API documentation: reasoning

Synthetic source page for the attribution golden set. Lumen is a fictional model API
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/lumen/docs/build/reasoning`.

## Turning reasoning off

On most models you can set `reasoning: {mode: "off"}` to skip the reasoning step.

`reasoning: {mode: "off"}` fails no matter the effort on Lumen Atlas 4.1, Lumen Atlas 4, Lumen Brook
4.1, Lumen Brook 4 and Lumen Brook Preview: it is rejected with a validation error at every effort level. Use a lower
effort instead.

## Lumen Atlas 4.5

Lumen Atlas 4.5 also rejects `reasoning: {mode: "off"}`. For the closest behavior, set effort to
`minimal`.

## Lumen Atlas 3

On Lumen Atlas 3, `reasoning: {mode: "off"}` is accepted only at `low` effort; at higher effort it
is rejected.
