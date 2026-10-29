---
type: llm
focus: { source: file, path: docs/conventions/developer-experience.md }
arm: with-only
---

The judged file is the developer tooling conventions file that setup wrote for the Python repo `brackenfold`. Fact: `bfk release <version>` asks for confirmation with `input()`. The Makefile `release` target and `scripts/release.ps1` both run `bfk release`.

A missing or empty file fails. Otherwise, PASS when the text describes `bfk release` (or `make release` / `scripts/release.ps1`, which run it) as interactive / prompting for confirmation, or does not mention it at all. FAIL when it mentions `bfk release` (or a wrapper of it) without saying it prompts, or describes it as non-interactive.
