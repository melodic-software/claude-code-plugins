---
name: use-your-skills
description: "Re-anchor the discipline of actually using the skills available to you — scan the in-context skill listing, map the conversation and the task to the skills that fit, and invoke them instead of reinventing their procedure from scratch. Then audit the work in flight for a skill that should have fired and did not, and route forward — invoke it now, and name the relevant skills when delegating to a subagent. Use when: 'use your skills', 'you have a skill for that', 'did you check your skills', 'there's a skill for this', 'you reinvented that', 'you skipped the skill', 'invoke your skills', or at conversation start to set the posture that available skills get used."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: core  # every session carries a skill listing to act on
  discipline-batch-rank: 10
---

# Use your skills

A drift corrector for skill-use discipline: the skills are in context to be
used, not ignored. The method — re-anchor, audit the work in flight, correct
forward, report, and the tone that firing this is not an accusation — lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to discovering and invoking the
skills already available.

## The discipline this re-anchors

A skill listing is loaded into context so the model knows what is available:
every **model-invocable** skill's name (always) and its description (subject to
the listing budget), with the full body loading only when the skill is invoked
([Skills docs](https://code.claude.com/docs/en/skills), fetched 2026-07-20).
The listing covers only what the MODEL can reach — a skill set to
`disable-model-invocation: true` is **manual-only**: its description is not in
the model's context and the model never auto-invokes it, so it surfaces only
when a user types `/name` (the inverse, `user-invocable: false`, stays in the
model's listing but is hidden from the `/` menu). This corrector therefore
audits only what the model could actually have reached: a **model-visible**
skill that sat in the listing and went unused, its procedure reinvented — or
skipped — instead of invoked. It does not fault the model for not
auto-firing a manual-only skill that was never in its listing. Over a long
session the listing loses salience the same way a standing rule does; this
re-anchors the habit of consulting it.

The discipline, at each of the three surfaces where skills apply:

- **This conversation.** Before doing multi-step or specialized work, scan the
  in-context listing for a skill that already owns it, and invoke that skill
  rather than improvising the procedure. A skill's description is written to
  say when it applies — read it as a routing signal, not decoration.
- **The current task.** Map the task's shape to the skills that fit it — often
  more than one across a task's phases (research, plan, implement, review) —
  and invoke each at its moment rather than carrying the whole task by hand.
- **Delegated (subagent) work.** A fresh non-fork subagent does **not** inherit
  your skill listing — it discovers project, user, and plugin skills on disk
  through the Skill tool during execution
  ([Subagents docs](https://code.claude.com/docs/en/sub-agents), fetched
  2026-07-20). So **name the relevant skills in the delegation prompt** so the
  subagent knows to reach for them. For a custom subagent that should always
  carry a discipline, recommend its `skills:` frontmatter, which **preloads the
  full skill content** into the subagent at startup (preload, not access — the
  Skill tool is already available to the subagent unless removed via `tools` /
  `disallowedTools`). One caveat, doc-confirmed: `skills:` can preload only a
  **model-invocable** skill; a skill set to `disable-model-invocation: true`
  cannot be preloaded (Claude Code skips it and logs a warning), because
  preloading draws from the same set the model can invoke — for a manual-only
  discipline, put its guidance in the prompt directly rather than expecting a
  preload. This is guidance, not a config change the skill performs.

## Audit — what to look for

Name concrete, located findings (per the method doc's step 2):

- a multi-step or specialized task carried by hand where a skill in the
  listing already owns that exact procedure;
- a procedure reinvented from scratch that a listed skill would have supplied;
- a task phase (research, planning, review, verification) done ad hoc where a
  fitting skill went unconsulted;
- a delegation prompt to a subagent that names no skills, leaving the subagent
  to rediscover — or miss — a discipline it should have carried;
- a custom subagent that repeatedly needs a discipline but does not preload it
  via `skills:`.

Correct each forward now: **invoke the skill this turn** and let it govern the
work rather than merely noting it existed; re-issue the delegation prompt with
the relevant skills named; and where a subagent should always carry a
discipline, recommend the `skills:` preload. Where the audit finds the right
skills were in fact used, say so — a clean audit is a correct outcome.

## Out of scope — routed, not owned

This skill corrects session behavior — *what should have fired and didn't*. It
does **not** own the levers that decide whether a skill *can* surface. Route
those:

- **A skill's description quality** — key use case first, natural trigger
  keywords, within the per-entry character cap — is skill-authoring QA. Route
  to `/skill-quality:check` (degrade to prose guidance when not installed).
- **The listing budget across all installed skills** — the listing is capped
  at a fraction of the context window, and on overflow descriptions are dropped
  from the least-invoked skills first, so a real skill can silently lose its
  triggering keywords. That machine-level overflow is a configuration concern;
  route to `/claude-config:audit` (degrade to prose). `/doctor` estimates the
  listing's cost.

The dividing line: if a skill was in the listing and simply went unused, that
is this skill. If a skill could not surface because its description was thin or
the listing overflowed its budget, that is the routed territory above.

## Deferred — a per-prompt routing hook

A soft re-anchor is a standing instruction: it persists across turns and
raises the habit of consulting the listing, but it does not *deterministically*
route every prompt to its skills. Deterministic per-prompt routing needs a
`UserPromptSubmit` hook that injects the mapping as additional context on every
message — a heavier, always-on mechanism with a per-prompt token cost. This is
**deliberately deferred**, not built here. Trigger to revisit: audits of this
skill repeatedly show "the skill existed, the description never surfaced it," or
skills are repeatedly not firing despite the soft re-anchor. The hook seam is
owned by a hooks-capable plugin (the `claude-ops` hook-ownership precedent), not
by this corrector.

## What this skill does NOT do

- **Does not tune descriptions or budgets.** Description hygiene routes to
  `/skill-quality:check`; listing-budget overflow routes to
  `/claude-config:audit`. This skill audits use, not surfaceability.
- **Does not force-invoke an ill-fitting skill.** The goal is to use the skill
  that *fits*, not to fire one for its own sake; "no skill fits, proceeding
  directly" is a valid outcome.
- **Does not mutate config or frontmatter at runtime.** The subagent `skills:`
  preload and hook options are recommendations routed to the user, not changes
  the skill makes.
- **Does not fabricate a finding.** Work that already invoked the fitting
  skills audits clean; say so.

## Gotchas

- The listing carries every skill *name* always, but when many skills are
  installed the *descriptions* can be trimmed to fit the budget — so a skill
  whose description looks absent may be budget-dropped, not missing. That is a
  routed concern (above), not evidence the skill does not exist.
- A subagent's silence on skills is easy to miss: it will not error, it will
  just do the work without the discipline the parent took for granted. The fix
  lives in the *delegation prompt* (name the skills) or the *agent definition*
  (`skills:` preload), not in the subagent's own run.
- Invoking a skill IS the re-anchor — reading its description and then
  improvising the procedure anyway is the exact drift this corrects.
