---
bump: patch
---

### Fixed

- **`/corrections:codify` runs the action you named when the action word ends in punctuation.** A dictated `taste.`, `rules,` or `note:` now selects that action once a trailing `.`, `,`, `:`, `;`, `!` or `?` is stripped, for every action, and the flags after it (`note`'s `--applied`, `reviews`' `--pr` and `--repo`, `issues`' `--label` and `--limit`, `count-checks`' `--since`, `--until` and `--bucket`) are still read. A quoted description that starts with an action word still runs the default action. Two new eval cases cover `rules.` and `note. --applied` ([#17031](https://github.com/melodic-software/claude-code-plugins/issues/17031)).
