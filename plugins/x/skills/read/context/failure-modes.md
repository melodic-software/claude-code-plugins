# Failure modes and observed behavior

Reference detail for `/x:read`. Load when a call fails, returns something unexpected, or you need to
classify a response.

## Step 1 — xtomd status handling

`-sS` alone prints no status. Append `-w '\n%{http_code}'` (or `-o <file> -w '%{http_code}'`) so the
code is observable rather than inferred from body shape.

| Code | Meaning | Action |
|---|---|---|
| `400` | malformed or missing URL | Report. The gate should have caught it — say so. |
| `502` | X unreachable: private, protected, or deleted | Report and stop. Never retry in a loop. |
| `500` | vendor-side error | Report. At most one retry. |
| `429` or timeout | rate-limited or hung | Report and stop. Do not hammer. |
| `200` with no `markdown` field, or an HTML body | not a conversion — a stub or bot-challenge page | Treat as failure, not content. |

A `200` is not by itself success: confirm the response actually carries converted content before
reporting it. Any other outcome — DNS failure, connection reset, empty body — is a failed fetch,
never an empty post.

## Step 2 — Thread Reader App miss detection

A `200` does not mean a hit. Treat as a miss when *either* holds:

- the final URL ends in `/error`; or
- the page carries no unrolled post content — a landing page, rate-limit notice, or challenge page
  also returns `200`.

Confirm positively that the page contains the thread's posts. Absence of `/error` is not evidence of
success.

Two limits, reported rather than worked around:

- The page exists only if someone requested that unroll. Nothing guarantees one.
- The path id must be the **root** post. A mid-chain reply URL carries its own id, which will miss.

## Gotchas

Observed during empirical verification (2026-07-24):

- **A GET to `/api/markdown` returns HTTP `200`.** Not a success — the body is a self-describing
  stub reading `"method":"POST"`.
- **A Thread Reader App miss also returns HTTP `200`**, redirecting to `.../thread/<id>/error`.
- **Length is not evidence of a chain.** `isNoteTweet` is the discriminator: a genuine 12-post chain
  returned `isNoteTweet: false` with a 346-character root, while a long single post returns
  `isNoteTweet: true` and is already complete.
- **`replies` in the `/api/fetch` payload is an integer** — an engagement count. Nothing in that
  schema carries sibling or child posts.
- **xtomd's docs advertise an `@xtomd/mcp-server` npm package that does not exist** (registry `404`).
  The name is unregistered and claimable by anyone — treat any package that later appears under it
  as untrusted.
- **A URL with an apostrophe breaks out of the request body.** Verified against a real `argv` dump:
  the payload contributed a second unconstrained URL and an `-o` arbitrary-write flag to the
  receiving process. This is why the gate rebuilds from captures instead of escaping — hand-escaping
  is the failure mode, not the fix.
