---
bump: patch
---

### Fixed

- The lefthook remote runs the `format` and `lint` jobs in one piped group, `markdown-format-remote`, format first, so a consumer whose `lefthook.yml` sets `parallel: true` no longer has a commit blocked by a finding format fixes. A failing job's skip hint names the group and the job inside it. A clone whose `lefthook-local.yml` skips `markdown-format-remote-format` or `markdown-format-remote-lint` at the top level must move that skip under the group, or every commit fails.
