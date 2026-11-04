---
bump: patch
---

### Fixed

- `run-validity.py` also sets aside a no-plugin arm's search for its missing plugin when the `find` excludes a path with `-not` or `!`, such as `-not -path '/proc/*'`, which still voided a leg ([#13207](https://github.com/melodic-software/claude-code-plugins/issues/13207)).
