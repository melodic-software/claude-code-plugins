---
type: llm
focus: { source: file, path: docs/conventions/developer-experience.md }
arm: with-only
---

Rubric item: the conventions do not call `tq commit` non-interactive.

The agent was asked to write down the developer tooling conventions of the .NET repository `tarnquill`. The text to grade is the conventions it wrote: the contents of the conventions file, or a diff of the markdown files it wrote. When there is no such text (the file is missing or empty), FAIL.

Fact: `tq commit` is interactive: it reads the change type and message with `Console.ReadLine` and has no flags to bypass the prompts.

FAIL when the text says or implies that `tq commit` can run non-interactively (for example that it takes the type or message as flags or arguments, that it works with stdin closed, or that a flag such as `--yes` skips its prompts), or that all `tq` commands are non-interactive. PASS otherwise, including when `tq commit` is described as interactive or not mentioned.
