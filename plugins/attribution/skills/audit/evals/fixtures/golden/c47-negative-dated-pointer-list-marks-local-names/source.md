# Pellet documentation: authentication

Synthetic source page for the attribution golden set. Pellet is a fictional model gateway
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/pellet/docs/authentication`.

## Authentication precedence

Pellet picks the first credential it finds, in this order.

Cloud provider credentials head the list when `PELLET_USE_NIMBUS`, `PELLET_USE_STRATA` or
`PELLET_USE_FJORD` is set, and a signed-in Pellet hub session outranks them. After those come an
API key in the environment and, last, the stored sign-in.
