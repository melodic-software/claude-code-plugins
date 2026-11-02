# Session bridge

## Preflight checks

| Check | What it reads | Fails when |
|---|---|---|
| Channel | the session's channel setting | the channel needs a sign-in the provider lacks |
| Provider | `PELLET_USE_NIMBUS`, `PELLET_USE_STRATA`, `PELLET_USE_FJORD`, `PELLET_USE_FJORD_EU`, `PELLET_USE_STRATA_GOV` | more than one is set |

Which checks run, and in what order, is our design. The upstream facts behind them, located as of
2026-10-11:

- Channels that need a sign-in, and providers that cannot give one: the first note on the
  [channels page](https://example.invalid/pellet/docs/channels), which has no anchor of its own.
  The variable names in the table are this repository's, not that note's.
- The credential a session picks when a cloud provider variable is set: cloud provider credentials
  head the list when `PELLET_USE_NIMBUS`, `PELLET_USE_STRATA` or `PELLET_USE_FJORD` is set, and a
  signed-in Pellet hub session outranks them:
  [authentication precedence](https://example.invalid/pellet/docs/authentication#authentication-precedence),
  checked 2026-10-30. Only those three variables appear on the page; `_FJORD_EU` and `_STRATA_GOV`
  in the table are local. Look again if the page reorders the list or changes which variables it
  names.
