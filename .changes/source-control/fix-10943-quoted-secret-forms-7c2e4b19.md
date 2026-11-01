---
bump: patch
---

### Fixed

- The babysit risk scorer now reads a quoted `secrets: inherit` (`secrets: "inherit"`, `secrets: 'inherit'`, `'secrets': inherit`) as the bare form. Such a line in a workflow now rates HIGH as `secret-exposure-review` and puts the workflow in the `gate` floor class. A quoted `id-token` key (`"id-token": write`, `'id-token': write`) now gates the workflow too ([#10943](https://github.com/melodic-software/claude-code-plugins/issues/10943)).
