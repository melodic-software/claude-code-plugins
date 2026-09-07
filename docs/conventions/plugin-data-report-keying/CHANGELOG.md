# Plugin-data report keying — Changelog

Notable changes to the `${CLAUDE_PLUGIN_DATA}` keying, retention, and overwrite contract. The contract
is versioned by the `Version:` stamp in `README.md` (SemVer). A rule whose `[SPEC]` obligation
tightens is a major bump; a new rule or a new named example is a minor bump; wording and adoption-table
updates are a patch.

## 1.0.2 — 2026-09-07

Patch under this contract's own rule — adoption table only. No `[SPEC]` obligation tightens, no
rule is added, and no worked example is added or removed.

- **Two `claude-ops` writers join the adoption table** (#3576): `observability --write`
  (`reports/<state-key>/claude-observability-<date>.md`) and `known-issues check-all`
  (`check-all-output/<state-key>/`). Both were unkeyed, which is to say one artifact per machine.
  The `check-all` row is the first entry whose collision was **reproduced** rather than reasoned
  about: on the pre-fix script one project read the other project's registry rows out of the shared
  scratch directory and reported them as its own, which is rule 3's failure exactly.
- **Both rows record a fail-closed derivation**, a detail no earlier adopter states: when the state
  key cannot be derived the writer stops rather than falling back to the unkeyed path, because that
  fallback silently restores the collision the key exists to remove.

## 1.0.1 — 2026-08-28

Patch under this contract's own rule — wording only. No `[SPEC]` obligation tightens, no rule is
added, and no worked example is added or removed.

- **Rule 1c's two worked examples and rule 2's reference implementation stop pinning a location
  inside the cited file.** They read `plugins/bugs/skills/write/SKILL.md:97`,
  `plugins/claude-config/skills/unhobble/SKILL.md:53-62`, and "steps 6 and 7" of
  `plugins/machine-health/skills/audit/SKILL.md`. All three resolved when re-derived, so none was
  broken yet; the pin is the part that rots, and this contract has already lost one to rot —
  [`detector-findings` 2.7.1](../detector-findings/CHANGELOG.md) dropped a `:414` pin as a class
  after finding it had drifted onto a comment five lines past the check it named. Each of these
  three citations already quotes the content it is pointing at, so the pin was carrying nothing the
  sentence did not. The paths and the plugin name stay, the quotes stay, and the machine-health
  citation now names what its procedure does — renders the report, then updates state — instead of
  two step numbers that renumber on the next inserted step.
- **The citations themselves stay, and [ADR 0018](../../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md)'s
  amendment of the same date says why.** Each is evidence about this checkout — a worked example
  whose content is quoted inline — rather than the address a reader must visit to get a rule. The
  amendment states that test, which until now was applied without being written down.

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
