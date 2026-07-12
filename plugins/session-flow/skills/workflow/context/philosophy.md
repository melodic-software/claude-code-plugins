# Workflow Philosophy & Depth Expectations

## Universal applicability

**This applies to ALL technical claims** — including "just adding a bullet point" to a rules file,
writing a comment, or answering a question. No size threshold below which verification is skipped.

- **Task size does NOT reduce research depth** — a one-line config change gets the same
  verification rigor as a multi-file feature
- **Analyzing existing research is not summarizing it** — restating a document's conclusions skips
  the research stage. Analysis requires independent verification of the claims and a fit check
  against the current codebase

## Philosophy

More tokens and more time are acceptable — even encouraged — when they produce more accuracy and
prevent rework. Insufficient research is a leading source of rework. If context is healthy, invest
in depth; context pressure (approaching compaction) is the budget constraint, not effort.

## No assumptions

Default to HIGH confidence, HIGH accuracy, HIGH attention to detail before making claims or
submitting code. Dig into the details, verify the specifics, confirm the edge cases.

## Task tracking

For non-trivial work (3+ stages), create tasks at the START, update status as you go. Tasks make
progress visible; for state that must survive `/clear`, use the durable checklist or a `/handoff`
save-point — in-memory tasks do not persist.

## Current information is non-negotiable

**Never operate on stale knowledge.** Exploration establishes what IS; research establishes what
SHOULD BE. Together they are the knowledge-gathering prerequisite for every task.

- **When in doubt, look it up** — a quick doc fetch is near-free; acting on outdated information is
  expensive
- **Flag uncertainty explicitly** — if current information cannot be obtained, say so; never
  present training-data-era knowledge as current fact
- **File/directory placement is a technical claim** — when creating files for a specific tool,
  research that tool's official directory conventions before placing files
