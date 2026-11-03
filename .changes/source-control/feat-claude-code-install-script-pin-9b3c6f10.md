---
bump: minor
---

### Changed

- babysit-prs: the Dependabot fix rule (`package_json_refusal`) admits a lanes App fix commit that
  renames one `allowScripts` key `@anthropic-ai/claude-code@<old>` to
  `@anthropic-ai/claude-code@<v>`, value kept, where `<v>` is the exact version the manifest
  pins in the commit before the fix (Dependabot's) and still pins after it. A downgrade or any
  other manifest move, a name-only or wildcard key, another package's pin, an added or dropped
  key, or a range in the manifest still refuses, as in the pr-unblock lane's
  `dependency-classify.mjs`.
