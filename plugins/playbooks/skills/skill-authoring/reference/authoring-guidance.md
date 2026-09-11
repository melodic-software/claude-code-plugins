# Authoring guidance: the best-practices page read against Claude Code

## Contents

- [Description contract](#description-contract)
- [Conciseness and the listing budget](#conciseness-and-the-listing-budget)
- [Degrees of freedom](#degrees-of-freedom)
- [Progressive disclosure](#progressive-disclosure)
- [Runtime model](#runtime-model)
- [MCP tool names](#mcp-tool-names)
- [Output templates and examples](#output-templates-and-examples)
- [Time-sensitive content](#time-sensitive-content)
- [Evaluation and iteration](#evaluation-and-iteration)
- [Model coverage](#model-coverage)

Locally-owned Melodic Software guidance (not part of the upstream playbook). Anthropic's
[Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
page is cross-product writing guidance; the Claude Code [Skills](https://code.claude.com/docs/en/skills)
page owns the harness mechanics. Each section states what the page says, what Claude Code enforces
or does differently, and the rule this marketplace applies, and ends in a **Record** line: basis
URL with anchor, as-of date, recheck trigger. A stamped date is a ceiling on how current
a claim can be, never authority; re-fetch the basis before acting on a number. The page is quoted
as guidance, not as an instruction to the reader.

## Description contract

One skill has one description, optionally extended by `when_to_use`, which Claude Code appends to
it in the skill listing. Put the key use case first: the listing truncates tail-first, and a
trigger phrase after the cut never reaches the model. Say what the skill does and when to use it,
with the nouns a user would type. The page asks for the third person ("Processes Excel files", not
"I can help you process"); apply that to new skills and leave the fleet's existing imperative
descriptions alone, since a voice rewrite changes trigger phrases for no measured gain.

Two caps apply at two layers:

| Cap | Layer | Over the cap |
|---|---|---|
| 1,024 characters, `description` alone | Agent Skills specification validation, enforced by the spec's `skills-ref` validator and stated as a Skills API upload requirement; Claude Code does not validate it | Fails validation outside Claude Code; `skill-quality:check` check 2b FAILs it here for portability |
| 1,536 characters, `description` plus `when_to_use` | Claude Code's skill listing (`skillListingMaxDescChars`) | The entry is cut at the cap; the skill still loads |

Beneath both sits the listing budget: the listing scales at 1% of the context window
(`skillListingBudgetFraction`), and on overflow Claude Code shortens descriptions starting with the
least-invoked skills while keeping every name. A short, specific description survives that
pressure; a long, vague one loses its trigger words first.

**Record.** 1,024: <https://agentskills.io/specification> (the `description` field) and
<https://platform.claude.com/docs/en/build-with-claude/skills-guide#creating-a-skill> (the
upload requirement). 1,536 and the 1% budget:
<https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short> and
<https://code.claude.com/docs/en/skills#frontmatter-reference> (`description` and `when_to_use`
rows), which is also where "key use case first" comes from. Third person:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#writing-effective-descriptions>.
Verified 2026-09-10. Recheck: either number changes on its owning page, or the Claude Code page
begins stating a validation cap of its own.

## Conciseness and the listing budget

The page calls the context window a public good: a skill shares it with the system prompt, the
conversation, every other skill's metadata, and the request. Claude Code adds the cost shape. The
description is paid for in every session; the body is paid for on every turn from invocation
onward, because the rendered SKILL.md enters the conversation once and stays; supporting files
cost nothing until read. So the page's challenge questions ("Does Claude really need this
explanation?", "Can I assume Claude knows this?", "Does this paragraph justify its token cost?")
bite hardest on the body, and the truncation rule above governs the description: conciseness there
is what keeps the trigger inside the budget.

**Record.** Public good and the challenge questions:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#concise-is-key>.
Cost shape: <https://code.claude.com/docs/en/skills#skill-content-lifecycle> and
<https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short>. Verified 2026-09-10. Recheck: the lifecycle section stops saying the body persists across
turns, or the listing section changes its truncation rule.

## Degrees of freedom

The page matches specificity to fragility; Claude Code gives each level a mechanism, and the
ladder runs from advisory to deterministic:

| Level | Use when | Body form | Claude Code mechanism |
|---|---|---|---|
| High | Several approaches are valid; context decides | Advisory prose: goals, heuristics, the reason beside each | Instructions only; the model adapts |
| Medium | A preferred pattern exists; some variation is acceptable | The pattern with named parameters | `$ARGUMENTS` or named `arguments`; a script with flags |
| Low | The operation is fragile, or a sequence is mandatory | The exact command plus "do not modify the command or add flags" | `${CLAUDE_SKILL_DIR}/scripts/...` with a matching `allowed-tools` Bash rule; or a hook, under the hook-budget rule |

Copyable checklists (a fenced `- [ ]` block the model copies into its response and ticks off)
belong to low-freedom procedures only. That is how the page's checklist pattern and tip 4 of the
playbook (avoid railroading) coexist: a fragile sequence earns the checklist, an open-field task
gets information plus room to adapt. Decide the level per section, not per skill.

The body states the gate ("Only proceed when validation passes"); it cannot enforce it. When the
cost of a skipped gate is high, a hook is the escalation: deterministic, independent of what the
model read, and charged to the marketplace's hook budget (`.claude/rules/hook-budget.md`), which
is why it is the exception rather than the default.

**Record.** Levels:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#set-appropriate-degrees-of-freedom>.
The exact-command `allowed-tools` pattern:
<https://code.claude.com/docs/en/skills#frontmatter-reference>. Verified
2026-09-10. Recheck: the page renames the levels, or the frontmatter reference drops the example.

## Progressive disclosure

- **500 lines.** Advisory on every surface: the page says body, the Claude Code Tip says the whole
  file, the Agent Skills specification recommends under 500 lines and under 5,000 tokens, and a
  `--plugin-dir` load probe on Claude Code 2.1.263 loaded and invoked a 608-line SKILL.md. This
  marketplace FAILs at 500 whole-file lines through `skill-quality:check` (check 4), the stricter
  reading, and WARNs above 200 (check 10). Split when approaching the cap, not at it.
- **One level deep.** Every reference file links directly from SKILL.md. The basis is the Agent
  Skills specification; the page's reason is that a nested file may get only a partial read.
  Claude Code states no depth rule.
- **A `## Contents` block** at the top of a reference file over 300 lines, listing its H2 anchors,
  so a partial read still shows the file's scope. The page says 100 lines; the bundled
  skill-creator guidance says 300. `skill-quality:check` WARNs over 300 (check 26); the 100-to-300
  band is the awareness tier of `docs-hygiene:audit-progressive-disclosure`, where installed.
- **Placement under compaction.** Auto-compaction re-attaches only the first 5,000 tokens of each
  invoked skill, within a 25,000-token shared budget, so a workflow or checklist block sits first
  after the frontmatter; a loop-back ("return to Step 2") past the cut is gone after compaction.
- **Pointer shape.** Each spoke pointer says what the file holds and when to read it. A bare "see
  X" link is the missed-connection signal the evaluation section watches for.

**Record.** 500:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#progressive-disclosure-patterns>
and the same page at `#token-budgets`; <https://code.claude.com/docs/en/skills#add-supporting-files>
(Tip); <https://agentskills.io/specification>; load probe run 2026-09-11 (`claude -p` with
`--plugin-dir`, Claude Code 2.1.263). One level deep: <https://agentskills.io/specification>. TOC
over 300: <https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md>; over
100: the best-practices page at `#structure-longer-reference-files-with-table-of-contents`.
5,000 and 25,000: <https://code.claude.com/docs/en/skills#skill-content-lifecycle>. Verified
2026-09-10. Recheck: any number changes on its owning surface, or a Claude Code release rejects a
long file.

## Runtime model

The page describes a filesystem: metadata pre-loaded, files read on demand through bash, scripts
run with only their output entering context. Claude Code differs on the first file: the rendered
SKILL.md is injected once, as a single message, on invocation, and is not re-read on later turns;
the on-demand read applies to the supporting files it points to. So standing rules belong in the
body and bulky material in the files the body names.

Scripts run through the Bash tool and only their output costs tokens, so a bundled script beats
generated code for any deterministic operation. Write the pointer as
`${CLAUDE_SKILL_DIR}/scripts/<name>` (or `${CLAUDE_PLUGIN_ROOT}/...` for a plugin's own tree) so
it resolves at personal, project, and plugin scope, and state the intent with the verb: "Run
`${CLAUDE_SKILL_DIR}/scripts/validate.sh` to check the plan" (execute, the common case) or "See
`scripts/validate.sh` for the field rules" (read as reference). Every path uses forward slashes: a
backslash in a plugin component path is rejected at load on macOS and Linux, and
`skill-quality:check` FAILs one in a skill-internal pointer (check 5).

Dependencies: state the install command and check before use ("Install into the project
environment with `pip install pypdf` inside its virtualenv; the script exits 2 with an install hint
when it is missing"), never "use the pdf library". Claude Code skills have full network access and
install packages on the user's machine, so there is no pre-installed list to verify against, and the
install must stay local to the project (a virtualenv, a project `node_modules`, a `--user` install),
never global, so the skill does not alter the user's computer. The other surfaces differ: the Claude
API sandbox has no network and no runtime installs, so a package must be on the code execution
tool's pre-installed list, and claude.ai's network access varies with admin settings. That is why
the page tells authors to list packages explicitly.

**Record.** Inject-once lifecycle: <https://code.claude.com/docs/en/skills#skill-content-lifecycle>;
`${CLAUDE_SKILL_DIR}` and `allowed-tools`: <https://code.claude.com/docs/en/skills#frontmatter-reference>.
Backslash rejection: <https://code.claude.com/docs/en/plugins-reference#path-traversal-limitations>.
Network, local-not-global installs, and the per-surface table:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#runtime-environment-constraints>
(the Claude Code row, both bullets). Package listing:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#package-dependencies>.
Verified 2026-09-10 (overview table re-read 2026-09-11). Recheck: the lifecycle section changes
the inject-once claim, or the overview's runtime table changes any row.

## MCP tool names

Reference an MCP tool by its fully qualified Claude Code name, in the body, in `allowed-tools`, in
permission rules, in a subagent's `tools`, and in hook matchers: `mcp__<server>__<tool>` for a
server the user or project configured (for example `mcp__github__get_me`), and
`mcp__plugin_<plugin>_<server>__<tool>` for a server a plugin bundles. The page's
`ServerName:tool_name` form is for other surfaces and is not written here; a bare server key or a
colon form matches no Claude Code tool. `docs-hygiene:audit-progressive-disclosure` carries the
same two forms as a pointer-quality criterion, where installed.

**Record.** <https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers>;
<https://code.claude.com/docs/en/permissions#mcp>;
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#mcp-tool-references>
(the `ServerName:tool_name` form). Verified 2026-09-10. Recheck: any of the three changes the name
form.

## Output templates and examples

When a skill produces a structured artifact, put the shape in the body and say how strict it is,
because the framing sentence is the only strictness control the pattern offers: "ALWAYS use this
exact template structure:" for data formats and machine-read output; "Here is a sensible default
format, but use your best judgment:" plus an explicit release line ("Adjust sections as needed")
where adaptation is wanted. Omit the release only when the structure is fixed.

Where output quality depends on style (commit messages, report prose), give two or three labelled
input/output pairs and close with one line naming the rule the pairs illustrate. The pairs carry
the style; the closing line names it.

Where several tools could do a job, name one default and at most one escape hatch with its trigger
condition, in the shape "Use A for B. For C, use D instead." A menu of alternatives is a decision
the model has to make mid-task. The page's "unless necessary" means environment-dependent
availability: a real menu is justified when the right choice depends on something discoverable
only at run time, and the body then says what that something is.

**Record.**
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#common-patterns>
and the same page at `#anti-patterns-to-avoid`. Verified 2026-09-10. Recheck: the page changes
either framing sentence or drops the escape-hatch example.

## Time-sensitive content

No date-conditional guidance in a body ("before August, use the old API"): state the current
method only. The page keeps superseded guidance in an in-body "Old patterns" section inside a
collapsed `<details>` block; this marketplace does not use that section in skill bodies. History
routes to the plugin `CHANGELOG.md`, the commit message, and `docs/adr/`, and a volatile specific
the body must restate carries the four-part record instead. The reason is the cost model above: a
collapsed block is still tokens on every turn after invocation, while a separate reference file is
free until read, so history that must travel with the skill goes in a spoke. The owning rule is
`.claude/rules/skill-bodies-state-current-rules.md`.

**Record.**
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#avoid-time-sensitive-information>
(the "Old patterns" example). Verified 2026-09-10. Recheck: the page drops or changes that section.

## Evaluation and iteration

Write the evals before the body. The page's order: run Claude on representative tasks without a
skill and note the gaps, build scenarios that test those gaps, measure a baseline, write the
minimum instructions that pass, iterate. Claude Code adds the condition that makes the baseline
honest: run each prompt in a fresh session with the skill disabled, then again with it enabled,
because leftover context from authoring the skill masks gaps in the written instructions. Measure
two things separately: whether the skill triggers on the prompts it should (and stays quiet on the
ones it should not), and whether the output is right when it does. A trigger proves discovery, not
correctness.

`evals/evals.json` in this repository follows the runner's shape: `skill_name`, then `evals[]`
with `id`, `prompt`, `expected_output`, `files`, and `expectations` (upstream calls it
`assertions`; the bundled schema accepts either). The page's `query` and `expected_behavior` record
is illustrative, not the file format. `/skill-quality:check validate-evals <skill>` checks the file
against the schema and runs the eval-quality lint.

The two-instance loop: author with one session, test with a fresh one that has only the skill
loaded, carry specific observed failures (not impressions) back to the authoring session, and read
the test transcript for four navigation signals: files read in an unexpected order, a reference
never followed, one file read repeatedly (promote it into the body), a bundled file never read (cut
it or signal it better). Where the bundled skill-creator plugin is installed, its eval modes run
this loop with a subagent per case. Where `/skill-doctor` is available (Claude Code v2.1.252 or
later, in a session that fetches feature flags, run in the terminal rather than over Remote
Control), it answers "does it activate" from usage data, not "is the output right". A
`claude plugin eval` subcommand exists in the binary but is undocumented, so nothing here depends
on it.

When a rule is being missed, two fixes are on the table: directive wording ("MUST filter test
accounts") and reasoning-based wording ("filter test accounts because they inflate every metric").
The page offers the first; the runner's linked guidance prefers the second. The evals settle it.

**Record.** Fresh-session baseline and skill-creator modes:
<https://code.claude.com/docs/en/skills#evaluate-and-iterate-on-a-skill>; `/skill-doctor`, its
version floor and feature-flag gate: <https://code.claude.com/docs/en/skills#find-unused-skills>
(the CHANGELOG lists the command under 2.1.261, so treat the docs' 2.1.252 as "or later"). Eval
file shape: <https://agentskills.io/skill-creation/evaluating-skills> and
`plugins/skill-quality/reference/evals.schema.json`. The loop and the four signals:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#evaluation-and-iteration>.
Verified 2026-09-10. Recheck: the Claude Code page documents `claude plugin eval`, changes the
`/skill-doctor` gate, or the runner changes its record shape.

## Model coverage

The page says to test a skill on every model it will run on, with a question per tier: enough
guidance on the fastest, clarity on the balanced, no over-explaining on the strongest. No runner
enforces this, so the checklist carries it as an attestation: the author states which of the
harness aliases (`haiku`, `sonnet`, `opus`, `fable`) the skill was exercised on. A skill that runs
under a `model` override or inside a subagent has more than one target, and the attestation names
them all or says which are untested.

**Record.** Alias list: <https://code.claude.com/docs/en/sub-agents#choose-a-model>. The per-tier
questions:
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#test-with-all-models-you-plan-to-use>.
Verified 2026-09-10. Recheck: the alias list changes.
