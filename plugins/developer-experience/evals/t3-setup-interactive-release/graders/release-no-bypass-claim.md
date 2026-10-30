---
type: llm
focus: { source: file, path: docs/conventions/developer-experience.md }
arm: with-only
---

The text to grade is the developer tooling conventions that setup wrote for the Python repo `brackenfold`: the contents of the conventions file, or a diff of the markdown files it wrote. Fact: `bfk release <version>` asks for confirmation with `input()` and has no flag (such as `--yes`) to skip it.

When there is no such text (the file is missing or empty), FAIL. Otherwise, FAIL when any sentence outside a `## Not yet` section says or implies that `bfk release` accepts a flag that makes it non-interactive (such as `--yes`, `-y`, `--force`), or that all commands accept such flags. A rule that NEW commands must offer such a flag is not a claim about `bfk release`. Piping an answer into stdin is not a flag. PASS otherwise.
