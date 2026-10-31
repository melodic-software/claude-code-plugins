---
bump: patch
---

### Fixed

- A thread a `review-threads.reviewer-ids` bot opened, with no trusted person's direction on it, is
  worked only when a trusted actor asked for that bot's review. Anyone can comment `@codex` on a
  public repository.
  - **An explicit request** is a `@codex` comment in an issue comment, a review comment or a review
    body, posted since the same bot's previous review. It must come from a person on the
    trusted-actor list. The bot's own text does not count.
  - **An automatic review** has no `@codex` comment and counts as asked for by whoever triggered it.
    That is the pull request's author on opening, or the actor of a ready-for-review event. Every
    such event in the window must be a trusted person's or the lanes App's.
  - Any untrusted request or event in the window leaves the thread for a person, and so does none
    that can be read. The skip is logged as `codex-request-untrusted` or `codex-request-not-found`.
  - The select job, the reply job's re-read, `fix-ci-context.mjs` and `pr-feedback-dispatch.yml`
    apply the same check. `chatgpt-codex-connector[bot]` stays on `reviewer-ids`, and the
    trusted-actor list is unchanged.
