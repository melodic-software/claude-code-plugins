---
bump: patch
---

### Changed

- Each read-runner lane (pr-unblock's fix-ci, its rung-up, address-feedback, review-dependency and resolve-conflicts; pr-refine's fix-docs; work-resolve-issue's resolve-issue) runs its activity once more, on the central fallback subscription token `FALLBACK_CLAUDE_CODE_OAUTH_TOKEN`, when the role's OAuth token also stops (a limit stop, a credit stop, or a 401 or 402). Each handoff job reads whether the secret is set and passes it as the second call's `fallback-ready`; a `<subscription>-handoff` job reads this run's jobs and `<first>-fallback` runs on the fallback token alone. With the secret empty, the second call stays the last and the lanes run as before.
