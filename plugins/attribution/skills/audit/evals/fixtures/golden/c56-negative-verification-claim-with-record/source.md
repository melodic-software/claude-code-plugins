# Nettle documentation: helpers

Synthetic source page for the attribution golden set. Nettle is a fictional agent runtime
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/nettle/docs/helpers`.

## Supported frontmatter fields

| Field | Description |
| :- | :- |
| `turnLimit` | Most agent turns before the helper stops. At the limit Nettle returns the helper's output marked partial, which the caller can resume. The partial marking needs Nettle 6.4.0 or later. |
| `effort` | Effort level for the helper. |

Helpers shipped in a plugin ignore `hooks`, `servers` and `permissionMode`.

## Choose an effort level

A helper's `effort` applies unless the call that starts it sets its own.
