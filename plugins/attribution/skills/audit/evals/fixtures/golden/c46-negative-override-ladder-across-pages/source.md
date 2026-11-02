# Corvid documentation: model configuration

Synthetic source page for the attribution golden set. Corvid is a fictional agent framework
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/corvid/docs/model-config`.

## Environment variables

Set `CORVID_HELPER_MODEL` to choose the default model for helpers that set none.

Set `CORVID_DEFAULT_LARGE_MODEL`, `CORVID_DEFAULT_MEDIUM_MODEL`, `CORVID_DEFAULT_SMALL_MODEL` and
`CORVID_DEFAULT_TINY_MODEL` to fix the model behind each alias.

## Restrict models

An `allowedModels` list limits which models a session may select.
