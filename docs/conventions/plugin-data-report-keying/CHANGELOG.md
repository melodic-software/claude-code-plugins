# Plugin-data report keying — Changelog

Notable changes to the `${CLAUDE_PLUGIN_DATA}` keying, retention, and overwrite contract. The contract
is versioned by the `Version:` stamp in `README.md` (SemVer). A rule whose `[SPEC]` obligation
tightens is a major bump; a new rule or a new named example is a minor bump; wording and adoption-table
updates are a patch.

## 1.0.0 — 2026-08-12

Initial published contract. Written because the hazard was already understood inside the fleet and
applied inconsistently *within one plugin* — the signature of a missing rule rather than a per-skill
oversight. `docs/conventions/` carried eighteen entries and none governed how a plugin names what it
writes under `${CLAUDE_PLUGIN_DATA}`; the nearest governing text (`docs/MIGRATION-PLAYBOOK.md` seam 4)
scopes *what may live there*, not how it is named.

- **Rule 1 [SPEC]** — every write is keyed `<component>/<state-key>/<filename>`, with `<state-key>` =
  `<repo-identity>/<worktree-discriminator>`. The scheme is `claude-config:audit-pass`'s, reused
  rather than reinvented, and ships as the shared `lib/state-key.sh` registered in
  `scripts/cross-plugin-source-registry.txt`.
- **Rule 1a [SPEC]** — derive the key by running commands, never as a condition over
  `${CLAUDE_PROJECT_DIR}` "when set". That placeholder substitutes inline in skill and agent content,
  so the literal token never reaches the model and the condition is not its to evaluate.
- **Rule 1b [SPEC]** — a key becomes directory components, so validate it as one and hash anything
  outside the accepted segment shape. A remote of `../../../etc` would otherwise walk the artifact out
  of the plugin's namespace; an unvalidated version of this derivation was caught doing exactly that
  in review.
- **Rule 1c** — the "looks scoped but isn't" case named with its worked example
  (`bug-report:write`'s kebab-cased project-root basename), so the next writer does not repeat it.
  Recorded as context, explicitly not filed as a `bug-report` defect.
- **Rule 2 [SPEC]** — retention is chosen by whether the artifact is read back, and the two failure
  modes are separated: keying closes *collision* (project B served project A's content), retention
  closes *overwrite* (yesterday's artifact gone). A non-destructive history does not close collision,
  because serving the newest is not serving this project's.
- **Rule 3 [SPEC]** — never serve or derive from an artifact that cannot be attributed to a project.
  This governs migration too: a legacy unkeyed file has no project segment, so adopting it into a key
  invents the attribution keying exists to remove.
- **Rule 4** — state the uninstall fragility where the keyed artifact is the only durable copy; the
  data directory is deleted on uninstall from the last scope unless `--keep-data` is passed.
- Adoption table records four conformant writers, one basename-keyed writer, one verification-based
  alternative (`claude-config:unhobble`), one slug-keyed instance of the gap
  (`docs/conventions/topic-docs/`'s non-repo fallback), and one deliberate non-adopter
  (`machine-health:audit`).
