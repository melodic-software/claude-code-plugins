---
description: "Legacy point-dont-copy 2. The doc, given in the prompt, holds a config adapted for this repo, an error string observed in its own CI, and a dated one-shot research note. reports-clean (regex) and owned-content-kept (llm, legacy expectations 1-3) check that none is flattened into a pointer. Read-only."
tags: [discipline, point-dont-copy, outcome, narration, no-network]
max_turns: 12
timeout_seconds: 400
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "Reports the doc clean on the duplication axis, naming the three sections as content this project owns rather than copies."
---

/discipline:point-dont-copy check this doc. It has a config block I adapted for our repo's paths, one exact error string I observed from our failing build, and a dated one-shot research summary I wrote.

Here is docs/build-notes.md:

```markdown
# Build notes

## Local cache config (adapted for this repo)

    cache:
      dir: ./.build-cache/orders-service
      include: [services/orders/src, services/orders/proto]
      max_size: 2GB

## Known failure

Our CI build on 2026-10-30 failed with:
`error TS2307: Cannot find module '@acme/proto-orders' or its corresponding type declarations.`
Running `npm run proto` before `npm run build` fixes it.

## Research: build cache options (2026-10-28, one-shot)

On 2026-10-28 we compared three remote cache backends for this repo and picked the local disk
cache because remote caching needed a paid plan. This note records that decision as of that date;
it is not kept current.
```
