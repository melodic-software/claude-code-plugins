---
description: "Inline recheck of one tsconfig pinned to TypeScript 5.4.5: a deprecated flag (gap), strict off with an ADR (deliberate divergence), and an unexplained useDefineForClassFields (undocumented divergence). The run has no network and SKILL.md lines 34-35 forbid comparing from recall, so the prompt gives the TypeScript 5.4 tsconfig reference entries for the three options as data fetched this session; a fetch attempt still hits the sandbox's no-network rule, so the case is tagged no-network. both-options-stated (legacy recheck-against-upstream 3 expectation 2) needs both resolutions named for useDefineForClassFields: adopt the default, or record the rationale. Needs --scaffold --allow-tools Bash WebFetch Edit"
tags: [discipline, recheck-against-upstream, outcome, scaffold, no-network]
max_turns: 15
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep, Bash, WebFetch, Edit]
expected_outcome: "Names the pinned 5.4 line, classifies importsNotUsedAsValues as a deprecation gap and removes it from tsconfig.json, strict false as a deliberate ADR-backed divergence left in place, and useDefineForClassFields as undocumented and the human's call between adopting the default and recording the rationale."
---

/discipline:recheck-against-upstream tsconfig.json

This session has no network, so I fetched the TypeScript 5.4 tsconfig reference entries for you; treat them as the current upstream state:

- `importsNotUsedAsValues`: deprecated in TypeScript 5.0 in favor of `verbatimModuleSyntax`; it stops working in TypeScript 5.5.
- `useDefineForClassFields`: defaults to `true` when `target` is ES2022 or higher, including ESNext.
- `strict`: defaults to `false`; recommended `true`.
