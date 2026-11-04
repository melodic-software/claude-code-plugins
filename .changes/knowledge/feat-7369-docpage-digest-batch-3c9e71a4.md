---
bump: minor
---

### Added

- `docpage-digest-batch` workflow ([#7369](https://github.com/melodic-software/claude-code-plugins/issues/7369)): digests several documentation pages with every Phase 3 digest agent, both Phase 4 verifier arms and each correction round dispatched by the workflow script, so no agent has to spawn another and no page skips verification. `/knowledge:docpage-digest` documents it as its Batch path and `/knowledge:map-corpus` launches it for a multi-page queue. Its stages run as the new `knowledge:digest-worker` agent.
- The workflow rejects a page URL that is not https on a public host, or that carries a quote, `$`, a backtick, whitespace or another shell metacharacter, before any agent sees it, and applies the same checks to the post-redirect canonical URL; it returns rejected and deferred pages with a reason each and a `verification` of `unverified: not run: <reason>`, which map-corpus records. The single-page path runs the same checks on the canonical URL before any shell command carries it. A profile's model mapping reaches a prompt only as `opus`, `sonnet`, `haiku` or a `claude-` model ID. The only accepted cross-vendor verifier B is `codex:codex-rescue`, briefed as a read-only foreground review.
- The checklist gains a `Verification status` line (`verified`, `unverified: <reason>`, `failed: <reason>`), copied into the interview handoff's first line and each map-corpus `queue.json` entry.
