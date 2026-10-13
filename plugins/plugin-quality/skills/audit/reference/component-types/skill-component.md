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
  (`context: fork`), and does what a forked skill can see match what the step needs? Are the named
  skills real? Are absent-seam fallbacks stated?
- **Scope correctness**: user vs project vs plugin; does it wrongly depend on
  project-specific skills that bias a generic task?
- **Cloud caveat**: if it must run in cloud or routine contexts, check that it resolves from a
  source those sessions read, not only from the author's own machine.
- **Determinism vs prose**: does it rely on the model obeying instructions where a deterministic
  mechanism (script) would be more reliable?
- **Gotcha harvest**: what did the evidence packet's real usage hit that the skill's own docs do
  not carry (improvised workarounds, undocumented escapes, repeatable failure triggers)? General,
  non-situational ones are candidate doc additions; name where each belongs.

- **Pointer**: when grading what a forked skill sees, fetch
  [Run skills in a subagent](https://code.claude.com/docs/en/skills#run-skills-in-a-subagent) live;
  when grading which skills and plugins a cloud session reads, fetch
  [Skills in Cowork and cloud sessions](https://code.claude.com/docs/en/skills#skills-in-cowork-and-cloud-sessions)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: either section changes what it states, or a release note names
  `context: fork` or skill loading in cloud sessions.

## Categories

- **Errors:** a step that does not do what the skill text says, or a false result the skill reported.
- **Improvements:** behavior the skills page or this skill's own contract implies and the skill does not do.
- **Quality of life:** friction while invoking or reading the result (a command the session cannot run, a report that hides the detail the operator needs).
- **Standards:** the `invocation-mode`, `seam-phrasing`, and `untrusted-content` probes.
- **Emitted findings:** when the skill is an audit, review, or scan that reports findings to a user, sample those findings and grade each.

## Reproduce

Invoke it on a realistic prompt; confirm it triggers when it should and follows its own workflow.
