---
description: "Ported from plugins/knowledge/skills/distill/evals/evals.json id 1 (same expectation at MB as book-distill id 1). Written from MB:plugins/knowledge/skills/book-distill/SKILL.md:14,34,65, MB:plugins/knowledge/skills/book-distill/context/templates.md:7 and MB:plugins/knowledge/skills/book-distill/templates/checklist.md:3. Covers lost sentences 19, 30, 32, 38 (progress key) and 28, 29 (placeholder substitution). Grades the per-book state path shape both versions produce under the plugin data directory, the session-root basename slug plus - plus 8 hex, then the target slug (testing), on the EPUB cache, progress or checklist path, never the mechanism (sha recipe at base, work-root.mjs --progress-key at head); and that no write path or shell command carries a literal <plugin-data>, <plugin-root> or {...-slug} placeholder. Prompt adapted: written in natural language so both arms can route it (the slash command is book-distill at MB and distill at head); the source is books/unit-testing.epub, not ~/books/unit-testing.pdf (the scaffold cannot place a file in the run's home, and no PDF fixture exists), so the page-offset expectation is dropped; the rights and Phase-1-only lines keep the run bounded. Visibility: head's gate (distill SKILL.md:14-25) must read local before any write, so the scaffold runs git init with no remote; it also seeds the existing testing skill the prompt names. Limitation: a run that uses the bare basename passes falsely only if the sandbox cwd basename itself ends in - plus 8 hex (UNVERIFIED)."
tags: [knowledge, distill, outcome, scaffold, progress-key]
max_turns: 30
timeout_seconds: 900
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "Phase 1 runs on the EPUB: per-book state (the EPUB cache, the progress file, the checklist) goes under the plugin data directory at <basename-slug>-<8 hex>/testing/, a Write creates the progress or checklist file there, and no write path or shell command holds an unsubstituted <plugin-data>, <plugin-root> or {project-slug} style placeholder."
---

Distill the book at books/unit-testing.epub into our testing skill (.claude/skills/testing).

I wrote this book and hold its rights. Run Phase 1 setup only, then stop and report what you set up.
