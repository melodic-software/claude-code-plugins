---
type: llm
focus: { source: file, path: docs/conventions/developer-experience.md }
arm: with-only
---

The judged file is the developer tooling conventions file that setup wrote for the Python repo `brackenfold`. Fact: `bfk release <version>` asks for confirmation with `input()` and has no flag (such as `--yes`) to skip it.

A missing or empty file fails. Otherwise, FAIL when any sentence outside a `## Not yet` section says or implies that `bfk release` accepts a flag that makes it non-interactive (such as `--yes`, `-y`, `--force`), or that all commands accept such flags. A rule that NEW commands must offer such a flag is not a claim about `bfk release`. Piping an answer into stdin is not a flag. PASS otherwise.
