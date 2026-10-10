---
bump: patch
---

### Fixed

- **The generated rules index no longer says deferred surfaces load only on read.** The preamble `render-index.sh` writes into every consuming repo's always-loaded file said each surface "enters context automatically when Claude reads a file it covers", which has been false for path-scoped rules and nested `CLAUDE.md` since Claude Code 2.1.288. It now says a surface loads once a file it covers triggers it, and links the Claude Code memory docs sections for rules and nested `CLAUDE.md` and for `AGENTS.md` instead of listing the triggers, so the next release that adds a trigger does not make every consuming repo's index wrong again. Re-run `render-index.sh write` (or `/instruction-placement:realign`) to pick up the new wording.
- **The realign skill, the README and the adherence experiment state the same trigger correctly.** The realign skill's "the rule fires on read", the README's "a read happens to match it", and the adherence experiment's and results record's read-only trigger wording now point at `context/verified-mechanics.md` for the triggers by version. The recorded adherence results are unchanged, and creation-governing content is still denied the path-scoped destination. The migrate skill's verification guide no longer says a nested `AGENTS.md` attaches only on a Read, and it records that the changelog and the memory docs disagree on what attaches one.
