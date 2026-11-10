---
bump: patch
---

### Changed

- `/playbooks:skill-authoring`: restated Claude Code behavior in `SKILL.md`, `skill-criteria.md`, `precompute-context.md` and `verification-loops-in-skills.md` is replaced by pointers to the live docs sections, each with an as-of date and a recheck trigger. No instruction, gate or command changes.
- `/playbooks:skill-authoring`: Composing Skills now says a plugin can declare the plugins it needs in its manifest, in place of the claim that no dependency management exists; the Sources entry for the vendored playbook points at `/playbooks:update --check` instead of a stale hash.
- `/playbooks:repo-sweep`: the conflicting-PR stop in `next` points at the GitHub `pull_request` section by anchor.
- `/playbooks:boris`: the `--bare` row names the 10x figure as Boris's and points at the bare-mode docs section; Section 77's docs line becomes a pointer record.
