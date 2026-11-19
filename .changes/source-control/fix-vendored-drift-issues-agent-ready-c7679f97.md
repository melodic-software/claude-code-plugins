---
bump: minor
---

### Changed

- The babysit merge gate trusts a vendored-copy upstream-drift issue as it trusts a hex-pin one: github-actions[bot] wrote it, nobody else last edited it, its title is `Upstream drift: <id>` and its first body line is the filer's vendored-copy lead for that id. It counts only for a pull request whose changed files, renames' old paths included, are markdown under the `skills/` of the plugin that id's row in the default branch's `scripts/upstream-drift-vendored-report.sh` names, markdown, `.jsonc` or `LICENSE` files in a `vendor/` baseline there, or fragments directly under that plugin's `.changes/`, with no `scripts`, `hooks`, `lib`, `.claude-plugin`, `.mcp.json` or `evals` path segment, and whose `SKILL.md` files outside `vendor/` change no frontmatter but the sync stamps and no `` !` `` line or fenced ```` ```! ```` block, and that touch no skill's `actions/update.md` and no file of the plugin's `update` skill outside `vendor/`, matching pr-verify's `driftSpec`. An id no row names, that two plugins claim, or with a row lacking the `files-only` mark (its update may install a package) is not trusted.
