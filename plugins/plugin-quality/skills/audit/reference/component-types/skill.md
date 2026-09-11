# Auditing a skill

When the audited component is a skill, also run `skill-quality:check` (its static
contract gate) when installed, and lean on its findings; absent, this file is the manual fallback.

## Read first

- `SKILL.md` frontmatter (`description`, invocation-control fields) and body.
- Any `reference/` files and whether the hub points at them with "load when" guidance.

## Check

- **Triggering**: is the `description` the sole auto-discovery driver, front-loaded with real use
  cases and trigger phrases, within the listing budget? Under- vs over-triggering; negative
  boundaries stated for adjacent intents.
- **Progressive disclosure**: hub thin; detail in `reference/`; each reference linked with a
  one-line load-when pointer. Does the hub stay thin as coverage grows?
- **Composition**: if it orchestrates other skills, is each loaded inline or forked
  (`context: fork` runs the skill body as the prompt for a subagent, which does not get the
  conversation history), and does that match what the step needs? Are the named skills real? Are
  absent-seam fallbacks stated?
- **Scope correctness**: user vs project vs plugin; does it wrongly depend on
  project-specific skills that bias a generic task?
- **Cloud caveat**: if it must run in cloud or routine contexts, note that user-scoped
  `~/.claude/skills/` is not read there. What those sessions do read is the cloned repository's
  `.claude/skills/` and plugins the repository's own `.claude/settings.json` declares; a plugin
  enabled only in user settings does not transfer.
- **Determinism vs prose**: does it rely on the model obeying instructions where a deterministic
  mechanism (script) would be more reliable?
- **Gotcha harvest**: what did the evidence packet's real usage hit that the skill's own docs do
  not carry (improvised workarounds, undocumented escapes, repeatable failure triggers)? General,
  non-situational ones are candidate doc additions; name where each belongs.

The `context: fork` and cloud-scoping claims above are verified 2026-09-06 against Claude Code
2.1.263 and the skills page (<https://code.claude.com/docs/en/skills>, "Run skills in a subagent"
and "Skills in Cowork and cloud sessions"). Recheck when either section stops carrying its
statement, or when a release note names `context: fork` or skill loading in cloud sessions.

## Reproduce

Invoke it on a realistic prompt; confirm it triggers when it should and follows its own workflow.
