# Verification loops in skills

## Contents

- [Three routes to create the skill, not two](#three-routes-to-create-the-skill-not-two)
- [Attaching a check to a skill you do not own](#attaching-a-check-to-a-skill-you-do-not-own)
- [When the embedded step does not run](#when-the-embedded-step-does-not-run)
- [Validator preference and plan-validate-execute](#validator-preference-and-plan-validate-execute)

Locally-owned Melodic Software guidance (not part of the upstream playbook). It covers four
questions the playbook leaves open once a skill's job is *checking* work: which route creates the
skill, how to attach a check to a skill you do not own, what to do when an embedded check
silently does not run, and which kind of validator the check should use.

It does not restate skill syntax, frontmatter, or invocation rules. The authoritative references
are [Skills](https://code.claude.com/docs/en/skills) (harness) and
[Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
(platform). Read those for the schema.

Each section is our decision, followed by a pointer to the page section behind it. Where no docs
page covers a point and only Anthropic's verification-loops blog post does, the section says so
and links the post as a correlate note, never as the pointer.

## Three routes to create the skill, not two

| Route | Pointer | Use it when |
|---|---|---|
| **Hand-write `SKILL.md`** | [Create your first skill](https://code.claude.com/docs/en/skills#create-your-first-skill) | Default. You know the shape you want. |
| **Ask Claude directly** | [Develop Skills iteratively with Claude](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#develop-skills-iteratively-with-claude) | You want a draft from a description, with no plugin dependency. |
| **`skill-creator` plugin** | The plugin's own README and `SKILL.md` for creation; [Run evals with skill-creator](https://code.claude.com/docs/en/skills#run-evals-with-skill-creator) for its eval loop | You want the plugin to interview you and elicit the procedure. |

Prefer the middle route before adding a dependency, not because the plugin is undocumented, but
because a dependency should earn itself.

- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of a pointed section no longer documents that route.

### Write the invocation namespaced

Write the plugin route `/skill-creator:skill-creator`, not the bare `/skill-creator`. The qualified
form resolves whatever else claims the bare name, and which other commands claim it is a condition
you do not control and cannot see from inside your own repo. The bare form is not wrong; it is
contingent. For a directory-scoped skill (`apps/web:deploy`), write the qualified form when you mean
the nested variant.

- **Pointer**: for how a skill's command name resolves, see
  [How a skill gets its command name](https://code.claude.com/docs/en/skills#how-a-skill-gets-its-command-name)
  and
  [Resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name).
- **As of**: 2026-08-31
- **Recheck trigger**: a re-read of either section no longer supporting the qualified form as
  unconditional.

## Attaching a check to a skill you do not own

Editing the producing skill's body is the simplest way to make a check fire automatically, but only
where you own the file. Two cases where you do not, and they have different answers:

- **Plugin-managed skills.** Do not edit: the plugin root is replaced on update.
- **Bundled skills.** Two options, not one: chain a wrapper after the bundled skill, or shadow it
  with a same-name skill at project or personal level. Read the pointer for what shadowing does
  and does not replace.

Shadowing replaces, it does not extend. You inherit maintenance of the whole behavior, and you
stop receiving upstream improvements to the bundled version. That is the trade against chaining,
which leaves the original intact and adds a wrapper around it. Pick shadowing when you want the
bundled behavior *changed*; pick chaining when you want it *followed by* something.

When you write "chaining", say which of three things you mean: one skill's body invoking another at
its end, several skills invoked in one user message
([Commands](https://code.claude.com/docs/en/commands)), or several Skills combined for one
multi-step task
([Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)).

- **Pointer**: for same-name skills and bundled skills, see
  [Resolve skills that share a name](https://code.claude.com/docs/en/skills#resolve-skills-that-share-a-name)
  (correlate with <https://claude.com/blog/building-verification-loops-in-claude-code-with-skills>
  for the chaining approach).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of that section no longer supporting shadowing a bundled skill.

## When the embedded step does not run

Verify an embed by running the producing skill and confirming the added step actually fires, on
**a real task, not one built for the test**. A contrived case exercises the step you are watching
for and hides the salience problem that only shows up when the skill is competing with a real
task's context.

When the step does not fire, work this diagnosis order:

1. **Prominence and wording.** Move the step earlier, phrase it as a requirement, or reorganize
   the section it sits in.
2. **Reference not followed.** If the step lives in a linked file rather than inline, say plainly
   in the body when to open that file, and put the link where it is seen.
3. **Description or earlier instructions not pulling the check in.** No docs page covers this
   diagnosis; it is a second hypothesis, not the first move.

Leading with (3) misdirects: it sends you to the frontmatter when the cause is usually the body.
Work 1 and 2, then 3.

**Do not confuse this with a skill that never surfaced at all.** An appended step that did not run is
a skill that *did* load and skipped an instruction. A skill that did not trigger is a different
failure with more than one owner: a description that does not match how the work is phrased is
skill-authoring QA (`/skill-quality:check`, if installed), a listing entry dropped by the shared
description budget is a configuration question (`/harness-config:audit`, if installed), and the habit
of consulting the listing at all has its own corrector (`/discipline:use-your-skills`, if
installed). Different failure, different remedy, and each diagnostic resolves only where its
plugin is present.

- **Pointer**: for real-work testing and steps 1 and 2, see
  [Develop Skills iteratively with Claude](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#develop-skills-iteratively-with-claude)
  and
  [Observe how Claude navigates Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#observe-how-claude-navigates-skills);
  for step 3, no docs page covered it as of the date below
  (correlate with <https://claude.com/blog/building-verification-loops-in-claude-code-with-skills>).
- **As of**: 2026-08-04
- **Recheck trigger**: a re-read of either section no longer supporting steps 1 and 2, or a docs
  page covering step 3.

## Validator preference and plan-validate-execute

A loop of run validator, fix errors, repeat needs a validator, and two kinds exist. Prefer them in
this order:

1. **A script with pass/fail output.** Claude Code runs it through bash and only its output enters
   context, so the loop closes on a signal the model can read ("OK" or a list of errors) and the
   same script can gate CI. Make each error name what failed and list the valid choices ("Unknown
   label 'prio-high'. Known labels: priority:high, priority:low"), because the message is what the
   model fixes from.
2. **A reference document the model reads and compares against.** It serves where no script fits
   (style, tone, structure), but it has no machine-readable outcome and no second consumer. Convert
   it to a script wherever the check is deterministic; where it is not, give the document a
   concrete checklist so "compare" has something to compare against.

Either way the body states the gate between the validator and the next irreversible step, and names
the step a failed validation loops back to. A body cannot enforce its own gate; a hook can, and is the escalation for a high-cost skip.

**Plan-validate-execute** is how we run work that touches many files, deletes things, or is costly
to get wrong. The model first writes down every intended edit in a machine-readable file; a script
checks that file and reports each problem with the valid choices; the model revises the file until
the script passes; only then does it apply the edits and check the outcome. Nothing real changes
while the plan is still being corrected. The checking script is the same kind as item 1 above,
aimed at the plan instead of the output.

- **Pointer**: for verifying work, see
  [Give Claude a way to verify its work](https://code.claude.com/docs/en/best-practices#give-claude-a-way-to-verify-its-work);
  for feedback loops and executable code in skills, see
  [Workflows and feedback loops](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#workflows-and-feedback-loops)
  and
  [Advanced: Skills with executable code](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#advanced-skills-with-executable-code).
- **As of**: 2026-09-10
- **Recheck trigger**: either page changes the pattern's steps or drops the pass/fail framing.
