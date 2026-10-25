---
description: "Reaches the docpage-digest Anthropic docs profile's applicability filter on eight invented blog claim rows against two small fake docs corpora; each grader's name states the row outcome it checks"
tags: [knowledge, docpage-digest, outcome, scaffold]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Each row's tag, markers and cited evidence follow the profile's applicability filter, in the requested line shape."
---

Apply the knowledge plugin's docpage-digest skill only for its Anthropic docs publisher profile:
tag the claim rows in `source/blog-post.md` per that profile's Claude-Code-applicability rules.
Do not run the digest pipeline: no fetch, no network, no work root, and no files written. The files
in this directory are the whole corpus.

- `source/blog-post.md`: a vendor blog post at
  https://claude.com/blog/field-notes-on-agent-setups, published 2026-10-14, fetched 2026-10-20.
  Its rows R1 to R8 are the claims to tag.
- `corpus/harness/`: the code.claude.com docs corpus; `corpus/harness/llms.txt` is its page index.
- `corpus/platform/`: the platform.claude.com docs corpus; `corpus/platform/llms.txt` is its page
  index.

Reply with plain lines, not a table, one line per output row, each id appearing once:

ROW <id> | <tag> | <markers, or none> | <note: evidence, citing docs pages as <file>:<line>>

Every source row gets at least one output line. A source row that needs more than one output line
uses ids `<id>a`, `<id>b`, and so on, in the order its text appears in the source; otherwise use the
source id. Write each absence statement (a statement that the docs do not state something) on its
own line in this shape:

ABSENCE | <row ids> | <statement>
