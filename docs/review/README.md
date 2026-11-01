# Review criteria

This repository's review rules that CI does not enforce, one file per concern. Each bullet in a
file names one rule; the linked source states it in full. Read the files whose concern your change
touches.

| File | Applies when |
|---|---|
| [`REVIEW.md`](../../REVIEW.md) | always: org-wide criteria, synced from `melodic-software/standards` |
| [`skills-and-agents.md`](skills-and-agents.md) | the change edits skill or agent text, cites a skill from any file, or adds a standing instruction |
| [`cost-claims.md`](cost-claims.md) | the change states a cost or price in a skill, agent, reference doc, doc or prompt |
| [`evals.md`](evals.md) | the change edits an eval case |
| [`hooks.md`](hooks.md) | the change edits a hooks module or fixes a hook false positive |
| [`untrusted-content.md`](untrusted-content.md) | the change makes a skill, agent or reference ingest text from a surface it does not control |
| [`pull-requests.md`](pull-requests.md) | the session works on an open pull request |
