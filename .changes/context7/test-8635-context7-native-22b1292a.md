---
bump: patch
---

### Changed

- The lookup and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Six of the nine legacy cases become the new cases `lk-library-question-fires`, `lk-uncovered-bounded-fallback`, `su-apply-install-cli-redetects`, `su-apply-key-not-written`, `su-apply-refuses-ctx7-setup` and `su-apply-mcp-request-guidance-only`. The other three were already covered by `lk-resolve-then-docs`, `lk-no-secret-in-query` and `su-check-default`. The setup cases now run `apply`, because bare `/context7:setup` is the read-only check. Both `evals.json` files are deleted.
