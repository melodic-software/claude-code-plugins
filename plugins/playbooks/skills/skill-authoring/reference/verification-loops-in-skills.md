# Verification loops in skills

Locally-owned Melodic Software guidance (not part of the upstream playbook). It covers three
questions the playbook leaves open once a skill's job is *checking* work: which route creates the
skill, how to attach a check to a skill you do not own, and what to do when an embedded check
silently does not run.

It does not restate skill syntax, frontmatter, or invocation rules — the authoritative references
are [Skills](https://code.claude.com/docs/en/skills) (harness) and
[Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
(platform). Read those for the schema.

Provenance, as this file uses the term: a claim is called **vendor-claimed** here when Anthropic's
[verification-loops blog post](https://claude.com/blog/building-verification-loops-in-claude-code-with-skills)
states it and the harness and platform reference pages do not, checked 2026-08-04. That is a local
reading convention for this file, not a repo-wide marker. Treat such lines as vendor guidance worth
adopting as convention, not as documented harness behavior. First-party sources outside those two
reference properties — a plugin's own README, for instance — are cited where they settle a point and
named as what they are.

## Three routes to create the skill, not two

| Route | Status | Use it when |
|---|---|---|
| **Hand-write `SKILL.md`** | Documented end to end — locations, frontmatter, walkthrough ([Skills](https://code.claude.com/docs/en/skills)) | Default. You know the shape you want. |
| **Ask Claude directly** | Documented. The platform states Claude generates a properly structured `SKILL.md` natively and explicitly disclaims needing a dedicated skill-writing skill ([Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)) | You want a draft from a description, with no plugin dependency. |
| **`skill-creator` plugin** | Creation, including the interview flow, is documented first-party by the plugin's own README and `SKILL.md`, which carries an "Interview and Research" step. The harness *skills page* covers only its eval loop ([Skills — run evals with skill-creator](https://code.claude.com/docs/en/skills#run-evals-with-skill-creator)) | You want the plugin to interview you and elicit the procedure. |

The blog reaches for the plugin first. The middle route needs no install, so prefer it before adding
a dependency — not because the plugin is undocumented, but because a dependency should earn itself.

### Write the invocation namespaced

Write the plugin route `/skill-creator:skill-creator` rather than the bare `/skill-creator` the blog
shows — but for a narrower reason than it first appears.

**Both forms bare-resolve. The difference is that one is conditional:**

- **Plugin namespace** (`plugin-name:skill-name`): the qualified form always works, and the bare name
  *also* invokes the skill **unless another command already uses that name**. Where a name is taken,
  the bare token keeps belonging to the incumbent and the namespaced form becomes the plugin skill's
  only command — which is why namespacing means plugin skills cannot collide, and why a plugin copy
  and a same-named original both stay reachable rather than one overriding the other
  ([Skills — how a skill gets its command name](https://code.claude.com/docs/en/skills#how-a-skill-gets-its-command-name),
  [Plugins](https://code.claude.com/docs/en/plugins)). Note this is current behavior: before
  v2.1.216 a frontmatter `name` replaced the whole command name.
- **Directory-scoped namespace** (`apps/web:deploy`): the bare name resolves to the project-root
  variant, and the qualified form reaches the nested one
  ([Skills — where skills live](https://code.claude.com/docs/en/skills#where-skills-live)).

So the bare plugin form is not wrong — it is **contingent on no other command claiming the name**,
which is a condition you do not control and cannot see from inside your own repo. Write the
qualified form because it is unconditional, not because the bare one fails.

## Attaching a check to a skill you do not own

Editing the producing skill's body is the simplest way to make a check fire automatically — but only
where you own the file. Two cases where you do not, and they have different answers:

- **Plugin-managed skills.** Edits are lost: the plugin root is replaced on update. Do not edit.
- **Bundled skills.** The blog calls these off-limits and offers chaining as the only alternative.
  **That is incomplete.** A same-name skill at project or personal level *replaces* a bundled one —
  a `code-review` skill in `.claude/skills/` replaces the bundled `/code-review`
  ([Skills](https://code.claude.com/docs/en/skills)).

Shadowing **replaces, it does not extend**. You inherit maintenance of the whole behavior, and you
stop receiving upstream improvements to the bundled version. That is the trade against chaining,
which leaves the original intact and adds a wrapper around it. Pick shadowing when you want the
bundled behavior *changed*; pick chaining when you want it *followed by* something.

"Chaining" names three different things across first-party sources — the blog's sense (one skill's
body invoking another at its end), the harness's sense (several skills invoked in one user message,
[Slash commands](https://code.claude.com/docs/en/commands)), and the platform's combining of Skills
for one multi-step task ([Agent Skills overview](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview)).
Say which you mean.

## When the embedded step does not run

Verify an embed by running the producing skill and confirming the added step actually fires — on
**real work, not a test scenario**, which is the platform's own instruction and the sharper form of
the blog's "invoke it on a new task"
([Skill authoring best practices — "Develop Skills iteratively with Claude"](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)).
A contrived case exercises the step you are watching for and hides the salience problem that only
shows up when the skill is competing with a real task's context.

When the step does not fire, work the documented diagnosis first:

1. **Prominence and wording** — the platform's own answer. A rule the skill states but Claude skips
   is treated as not prominent enough or not strong enough: reorganize so it stands out, strengthen
   the language, or restructure the surrounding section (same page and section).
2. **Reference not followed** — if the step lives in a linked file rather than inline, the link
   itself may need to be more explicit or prominent (same page, "Observe how Claude navigates
   Skills").
3. **Description or earlier instructions not pulling the check in** — *vendor-claimed*. The blog
   attributes a non-firing embed to the skill's description or its earlier instructions. No
   reference page states this diagnosis; it is a second hypothesis, not the first move.

Leading with (3) misdirects: it sends you to the frontmatter when the documented cause is usually the
body. Work 1 and 2, then 3.

**Do not confuse this with a skill that never surfaced at all.** An appended step that did not run is
a skill that *did* load and skipped an instruction. A skill that did not trigger is a different
failure with more than one owner: a description that does not match how the work is phrased is
skill-authoring QA (`/skill-quality:check`, if installed), a listing entry dropped by the shared
description budget is a configuration question (`/claude-config:audit`, if installed), and the habit
of consulting the listing at all has its own corrector (`/discipline:use-your-skills`, if
installed). Different failure, different remedy — and each diagnostic resolves only where its
plugin is present.
