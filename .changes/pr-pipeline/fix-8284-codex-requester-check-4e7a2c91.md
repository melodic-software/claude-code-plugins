---
bump: patch
---

### Fixed

- A thread a `review-threads.reviewer-ids` bot opened, with no trusted person's direction on it, is
  worked only when the `@codex` request behind that bot's review came from a person on the
  trusted-actor list. Anyone can comment `@codex` on a public repository. The request is looked for
  in issue comments, review comments and review bodies posted since the same bot's previous review.
  The bot's own text does not count. Any untrusted request in that window, by creation or last
  edit, leaves the thread for a person. So does no trusted request, which covers an automatic
  review on open or ready. The skip is logged as `codex-request-untrusted` or
  `codex-request-not-found`. The select job, the reply job's re-read, `fix-ci-context.mjs` and
  `pr-feedback-dispatch.yml` all apply the same check. `chatgpt-codex-connector[bot]` stays on
  `reviewer-ids`, and the trusted-actor list is unchanged.
