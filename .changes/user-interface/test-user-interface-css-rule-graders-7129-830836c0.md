---
bump: patch
---

### Changed

- An explicit request for an exit that accelerates away now wins over the `ease-in` rule in `write-css`: the exit uses `ease-in` and the reply warns that its slow start can read as lag. The review script and `audit-animation` still report that `ease-in`, and `write-css` says the finding is expected. The default is unchanged.
- The `css-rule-ease-in` eval passes an honored explicit request with the trade-off named, and counts `write-animation` firing as well as `write-css`.
- The `css-rule-logical` eval no longer fails a reply whose prose names a physical property in inline code, such as a right-to-left note offering `text-align: left` or quoting a whole rule; physical declarations in the CSS still fail it.
