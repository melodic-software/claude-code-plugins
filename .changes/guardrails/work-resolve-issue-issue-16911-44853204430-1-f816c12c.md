---
bump: patch
---

### Changed

- **The vendored git-hook installer renders a format and lint pair as one piped lefthook group.** `lib/git-hooks/install.mjs` now returns a plugin's pre-commit `format` and `lint` entries as one `lefthook-config` decision, carrying `entries`, so lint runs after format even under `parallel: true`. This plugin's own entries render as before ([#16911](https://github.com/melodic-software/claude-code-plugins/issues/16911)).
