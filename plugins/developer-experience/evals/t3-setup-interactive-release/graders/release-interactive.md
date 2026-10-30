---
type: llm
focus: { source: file, path: docs/conventions/developer-experience.md }
arm: with-only
---

The text to grade is the developer tooling conventions that setup wrote for the Python repo `brackenfold`: the contents of the conventions file, or a diff of the markdown files it wrote. Fact: `bfk release <version>` asks for confirmation with `input()`. The Makefile `release` target and `scripts/release.ps1` both run `bfk release`.

When there is no such text (the file is missing or empty), FAIL. Otherwise, PASS when the text describes `bfk release` (or `make release` / `scripts/release.ps1`, which run it) as interactive / prompting for confirmation, or does not mention it at all. FAIL when it mentions `bfk release` (or a wrapper of it) without saying it prompts, or describes it as non-interactive.
