---
bump: patch
---

### Fixed

- `docpage-digest` treats a "Concurrent subagent limit reached" refusal as a wait, not a subagent death, and keeps one copy of the death ladder in `context/pipeline-hardening.md`; the inline rung is skipped for a unit the profile maps to another model.
- The gate scripts and test suites no longer write `__pycache__` into the installed `scripts/` directory.
- Helper and scratch files go under `<work-root>/scratch/`, Phase 3 notes the shared subagent limit, the handoff leads with a decisions section, the live-doc checks are listed and assigned to Verifier A when Verifier B has no network, and the profile dispositions the raw-markdown banner and adds a response-field pair.
