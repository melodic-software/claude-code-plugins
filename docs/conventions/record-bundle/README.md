# Record Bundle Convention

A record bundle is one folder holding a markdown record and the diagrams and media the
record cites. It keeps a record and its sources together so they move, review, and
diff as one unit, and it keeps every rendered view of the record out. The
[rendered-views convention](../rendered-views/README.md) owns what a view is and how it
is emitted; this convention owns where the record and its sources live.

## What goes in a bundle

```text
<bundle>/
  <record>.md      the markdown record, exactly one, at the bundle root
  diagrams/        diagram sources the record cites (Mermaid `.mmd`, hand-authored `.svg`)
  media/           images and recordings the record cites as evidence
```

- **The record.** Exactly one markdown file at the bundle root. Its producer names it.
  It is readable on its own: a reader who opens only the record misses nothing a view
  would have told them.
- **Diagrams.** The source of every diagram the record cites, when the diagram is not
  inline in the record as a fenced block. A hand-authored SVG is a source and belongs
  here. An SVG that came from a pull request, another repository, or the web is K2 under
  the rendered-views content classes: a view that inlines it passes the builder's SVG
  allowlist and is a K2 page.
- **Media.** Material the record depends on that cannot be regenerated from it:
  screenshots, a test-run recording, an image a person supplied.
- **Links are relative and stay inside the bundle.** The record cites diagrams and
  media by a path relative to the bundle root (`diagrams/flow.mmd`,
  `media/login-failure.png`), so the bundle can move without breaking a link. A link
  has no `..` segment and no absolute path, and no file in the bundle is a symlink, so
  a view built from the bundle reads nothing outside it.
- `diagrams/` and `media/` exist only when the record cites something in them.

## What never goes in a bundle

A view of the record. The test is whether the file can be regenerated from the
bundle: if it can, it is a view and is written outside the bundle.

- HTML pages, published or local.
- Video renders and narrated audio, with their timing files.
- An SVG pre-rendered from a diagram source in `diagrams/`. The source stays in the
  bundle; the rendered SVG goes with the view that uses it.

A producer writes its views to its own view location outside the bundle, as the
rendered-views convention's residence rules say (untracked by default). A view may link
back to its record; the record never depends on a view.

## Where a bundle lives

The bundle does not change where a record lives. A record kept in a memory-tier
directory, a plugin data directory, or a tracked docs path keeps that home; the bundle
is the folder at that home instead of a lone file. A record that cites no diagram or
media may stay a single markdown file: a bundle of one file adds nothing.

## Format changes

A bundle carries no format version. When the layout changes, the change migrates every
producer and every reader of the old layout at once and updates this document in the
same pull request.
