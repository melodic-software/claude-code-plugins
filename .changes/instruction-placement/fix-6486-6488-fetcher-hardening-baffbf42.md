---
bump: patch
---

### Security

- `scripts/fetch-docs.sh` runs curl with `-q`, so a `~/.curlrc` option such as `insecure` or
  `proxy` no longer reaches its requests, and takes `--public-only`, which refuses a host that
  resolves to a non-global address and pins the request to the checked one
  ([#6488](https://github.com/melodic-software/claude-code-plugins/issues/6488),
  [#6486](https://github.com/melodic-software/claude-code-plugins/issues/6486)).
