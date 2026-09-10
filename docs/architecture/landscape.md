# System Landscape

Generated on 2026-09-10 from an explicit repository list (`--repos`). Every fact
below traces to the file named in `portfolio.md`; nothing was fetched, and the
date reflects the local HEAD of each checkout.

```mermaid
C4Context
  title System Landscape
  System(claude_code_plugins, "claude-code-plugins", "shell; tooling: node, python")
```

One repository, one owner (`melodic-software`), so no enterprise boundary is
drawn and no relationship line exists: an edge needs a fact in one repository
that names another, and there is no second repository here to name.

This checkout references nineteen other repositories in its tracked files, and
none of them appear above, because the current skill draws an edge only when the
other repository is itself in the charted set. Charting the reference graph is
the redesign tracked in
[#4033](https://github.com/melodic-software/claude-code-plugins/issues/4033).
