# Auditing a skill

Growable stub. When the audited component is a skill, also run `skill-quality:check` (its static
contract gate) when installed, and lean on its findings; absent, this file is the manual fallback.

## Read first

- `SKILL.md` frontmatter (`name`, `description`, invocation-control fields) and body.
- Any `references/` files and whether the hub points at them with "load when" guidance.

## Check

- **Triggering** — is the `description` the sole auto-discovery driver, front-loaded with real use
  cases and trigger phrases, within the listing budget? Under- vs over-triggering; negative
  boundaries stated for adjacent intents.
- **Progressive disclosure** — hub thin; detail in `references/`; each reference linked with a
  one-line load-when pointer. Does the hub stay thin as coverage grows?
- **Composition** — if it orchestrates other skills, are they loaded inline (not forked, which
  loses history)? Are the named skills real? Are absent-seam fallbacks stated?
- **Scope correctness** — user vs project vs plugin; does it wrongly depend on
  project-specific skills that bias a generic task?
- **Cloud caveat** — if it must run in cloud/routine contexts, note that user-scoped
  `~/.claude/skills/` is not read there; plugin or repo skills are.
- **Determinism vs prose** — does it rely on the model obeying instructions where a deterministic
  mechanism (script) would be more reliable?

## Reproduce

Invoke it on a realistic prompt; confirm it triggers when it should and follows its own workflow.
