---
bump: patch
---

### Fixed

- The `ed-controls-everything-default` eval's `manifest-element`, `manifest-groups` and
  `runtime-inlined` graders now pass a page that a build script assembles. The script is a `.mjs`,
  `.cjs`, `.js` or `.py` file, written with Write, that calls a file write, names an `.html` file
  and holds the grader's text: the manifest element, the three groups, or the runtime's path or
  defining line. A later Bash command must run it with `node`, `bun` or `python`. A script that
  builds no controls or leaves out a group still fails. Each grader has pass and fail samples of
  the build-script shape
  ([#17350](https://github.com/melodic-software/claude-code-plugins/issues/17350)).
