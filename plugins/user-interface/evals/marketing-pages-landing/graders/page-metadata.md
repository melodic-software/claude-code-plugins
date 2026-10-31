---
type: llm
arm: both
---
PASS only if the reply's code gives the landing page both a title and a description as page
metadata: a Next.js `metadata` export or a `generateMetadata` return whose object sets `title` and
`description` (quoted keys and the `{ title, description }` shorthand count, with or without
semicolons), or a `<title>` element plus a `<meta name="description">` tag in any attribute order.
FAIL if the page metadata sets a title but no description, even when a `description` key appears
elsewhere in the code (feature or pricing data, an `openGraph` block alone), if the description
appears only in prose, or if the reply contains no code.
