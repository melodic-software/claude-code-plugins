---
bump: minor
---

### Changed

- Shared `view-builder.mjs` and `html-escape.mjs` synced: an interactive page's policy adds `img-src data:` and `font-src data:`, and both validator profiles admit a base64 `data:` URL in two places only, a PNG or JPEG as the `.rv-logo` rule's one `background-image`, and a WOFF2, WOFF, TTF or OTF font inside `@font-face`. Every other `url(`, scheme and URL-bearing attribute is still refused. Pages built today look the same; no other change to this plugin.
