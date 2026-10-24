---
bump: none
---

### Changed

- The `css-rule-logical` eval no longer fails a reply whose prose names a physical property in inline code, such as a right-to-left note offering `text-align: left`; physical declarations in the CSS still fail it. The `css-rule-ease-in` eval counts `write-animation` firing as well as `write-css`, since both carry the rule and an animation request routes to `write-animation`.
