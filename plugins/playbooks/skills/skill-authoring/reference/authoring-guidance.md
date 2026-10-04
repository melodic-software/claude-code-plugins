# Authoring guidance: the best-practices page read against Claude Code

## Contents

- [Description contract](#description-contract)
- [Conciseness and the listing budget](#conciseness-and-the-listing-budget)
- [Degrees of freedom](#degrees-of-freedom)
- [Progressive disclosure](#progressive-disclosure)
- [Runtime model](#runtime-model)
- [Argument surface](#argument-surface)
- [MCP tool names](#mcp-tool-names)
- [Output templates and examples](#output-templates-and-examples)
- [Time-sensitive content](#time-sensitive-content)
- [Evaluation and iteration](#evaluation-and-iteration)
- [Model coverage](#model-coverage)
- [Agent model](#agent-model)

Locally-owned Melodic Software guidance (not part of the upstream playbook). Anthropic's
[Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
page is cross-product writing guidance; the Claude Code [Skills](https://code.claude.com/docs/en/skills)
page owns the harness mechanics. Each section states the rule this marketplace applies, in our
words, and ends in a **Record**: a pointer to the exact upstream section, an as-of date, and a
recheck trigger. Neither page is restated here; read the pointer for what it says. A stamped date
is a ceiling on how current a rule's basis can be, never authority; re-fetch the pointer before
acting on a number.

## Description contract

One skill has one description, optionally extended by `when_to_use`, which Claude Code appends to
it in the skill listing. Lead with the main use case: the listing truncates from the end, and a
trigger phrase past the cut never reaches the model. State the skill's job and the occasions for
it, in the nouns a user would type. Keep first and second person out of the description prose.
This marketplace writes descriptions in the imperative ("Audit the hook config"); third-person
singular ("Audits the hook config") also conforms. Name the user, the session, or the repository
where a clause would otherwise address the reader. A quoted trigger phrase is a user utterance and
keeps whatever voice the user would type ('audit my .claude folder').

Our checks enforce three limits:

| Our check | Limit we enforce | Owning layer |
|---|---|---|
| `skill-quality:check` check 2b FAILs | 1,024 codepoints, `description` alone, for portability outside Claude Code | Agent Skills specification and the Skills API upload requirement; Claude Code does not validate it |
| `skill-quality:check` check 2 | 1,536 characters, `description` plus `when_to_use` | Claude Code's skill listing (`skillListingMaxDescChars`) |
| `skill-quality:check listing-budget` estimate | 1% of the context window, shared across every listed skill | Claude Code's listing budget (`skillListingBudgetFraction`) |

Keep descriptions short and specific, so the trigger words survive when the shared listing budget
overflows.

**Record.** Pointer: for the 1,024 limit, see the `description` field in
<https://agentskills.io/specification> and
[Creating a Skill](https://platform.claude.com/docs/en/build-with-claude/skills-guide#creating-a-skill);
for the 1,536 limit, the listing budget, and tail-first cutting, see
[Skill descriptions are cut short](https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short)
and the `description` and `when_to_use` rows of
[Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference); for the voice
rule, see
[Writing effective descriptions](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#writing-effective-descriptions)
and the skill-creator's own frontmatter at
<https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md>. As of: 2026-09-10
(voice rule re-read 2026-09-11). Recheck trigger: either limit changes on its owning page, the
Claude Code page begins stating a validation cap of its own, or the best-practices page changes
its voice rule.

## Conciseness and the listing budget

Spend the most care on the body. The description is paid for in every session, the rendered
SKILL.md body on every turn from invocation onward, and supporting files only when read. Hold every
body paragraph to the best-practices page's challenge questions, and hold the description to the
listing limits above.

**Record.** Pointer: for the challenge questions, see
[Concise is key](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#concise-is-key);
for the cost shape, see
[Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle) and
[Skill descriptions are cut short](https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short).
As of: 2026-09-10. Recheck trigger: the lifecycle section stops saying the body persists across
turns, or the listing section changes its truncation rule.

## Degrees of freedom

Match specificity to fragility, and give each level a Claude Code mechanism; the ladder runs from
advisory to deterministic:

| Level | Use when | Body form | Claude Code mechanism |
|---|---|---|---|
| High | Several approaches are valid; context decides | Advisory prose: goals and heuristics, each written as what to do | Instructions only; the model adapts |
| Medium | One pattern is best, but a deviation does no harm | The pattern with named parameters | `$ARGUMENTS`, parsed in prose per [Argument surface](#argument-surface); a script with flags |
| Low | The operation is fragile, or a sequence is mandatory | The exact command plus an instruction not to alter it | `${CLAUDE_SKILL_DIR}/scripts/...` with a matching `allowed-tools` Bash rule; or a hook, under the hook-budget rule |

Copyable checklists (a fenced `- [ ]` block the model copies into its response and ticks off)
belong to low-freedom procedures only. That is how a checklist and tip 4 of the playbook (avoid
railroading) coexist: a fragile sequence earns the checklist, an open-field task gets information
plus room to adapt. Decide the level per section, not per skill.

At every level, write the instruction as the action. A reason earns a place beside it in two cases:
a required step that reads as optional without one, and a narrow rule that would otherwise be
applied everywhere. Background that changes no action (how the rule came about, who was bothered)
is left out. When a rule stated this way is still missed, [Evaluation and iteration](#evaluation-and-iteration)
covers testing a reasoned wording against it.

The body states the gate between a validator and the next step; it cannot enforce it. When the
cost of a skipped gate is high, a hook is the escalation: deterministic, independent of what the
model read, and charged to the marketplace's hook budget
(`docs/conventions/hook-budget/README.md`), which is why it is the exception rather than the
default.

**Record.** Pointer: for the levels, see
[Set appropriate degrees of freedom](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#set-appropriate-degrees-of-freedom);
for the exact-command `allowed-tools` pattern, see
[Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference). As of:
2026-09-10. Recheck trigger: the page renames the levels, or the frontmatter reference drops the
example.

## Progressive disclosure

- **500 lines.** This marketplace FAILs at 500 whole-file lines through `skill-quality:check`
  (check 4), the strictest reading across the surfaces, and WARNs above 200 (check 10). Our
  `--plugin-dir` load probe on Claude Code 2.1.263 loaded and invoked a 608-line SKILL.md, so the
  cap is ours, not a load failure. Split when approaching the cap, not at it.
- **One level deep.** Every reference file links directly from SKILL.md. Claude Code states no
  depth rule; we follow the specification.
- **A `## Contents` block** at the top of a reference file over 300 lines, listing its H2 anchors,
  so a partial read still shows the file's scope. `skill-quality:check` WARNs over 300 (check 26);
  the band below that is the awareness tier of `docs-hygiene:audit-progressive-disclosure`, where
  installed. The best-practices page and the bundled skill-creator set different thresholds; read
  them at the pointers.
- **Placement under compaction.** Put a workflow or checklist block first after the frontmatter,
  because auto-compaction re-attaches only the start of each invoked skill; a loop-back past the
  cut is gone after compaction. The budgets are at the pointer.
- **Pointer shape.** Each spoke pointer says what the file holds and when to read it. A bare "see
  X" link is the missed-connection signal the evaluation section watches for.

**Record.** Pointer: for line limits, see
[Progressive disclosure patterns](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#progressive-disclosure-patterns),
[Token budgets](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#token-budgets),
[Add supporting files](https://code.claude.com/docs/en/skills#add-supporting-files), and
<https://agentskills.io/specification>; the load probe is ours, run 2026-09-11 (`claude -p` with
`--plugin-dir`, Claude Code 2.1.263). For one level deep, see <https://agentskills.io/specification>
and
[Avoid deeply nested references](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#avoid-deeply-nested-references).
For the table-of-contents thresholds, see
<https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md> and
[Structure longer reference files with table of contents](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#structure-longer-reference-files-with-table-of-contents).
For compaction budgets, see
[Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle). As of:
2026-09-10. Recheck trigger: any number changes on its owning surface, or a Claude Code release
rejects a long file.

## Runtime model

Put standing rules in the SKILL.md body and bulky material in the files the body names: Claude Code
injects the rendered body once, on invocation, and reads supporting files on demand.

Forked execution (`context: fork`) is a Claude Code extension. What a fork changes, whether it
pays, the anti-candidate classes, and this fleet's `background: false` default live in the
[invocation-context rubric](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/invocation-context/README.md);
this section does not restate them.

Prefer a bundled script to generated code for any deterministic operation, because only a script's
output costs tokens. Write the pointer as `${CLAUDE_SKILL_DIR}/scripts/<name>` (or
`${CLAUDE_PLUGIN_ROOT}/...` for a plugin's own tree) so it resolves at personal, project, and
plugin scope, and state the intent with the verb: "Run `${CLAUDE_SKILL_DIR}/scripts/validate.sh`
to check the plan" (execute, the common case) or "See `scripts/validate.sh` for the field rules"
(read as reference). Every skill-internal path uses forward slashes; `skill-quality:check` FAILs a
backslash in a skill-internal pointer (check 5).

Dependencies: state the install command and check before use ("Install into the project
environment with `pip install pypdf` inside its virtualenv; the script exits 2 with an install hint
when it is missing"), never "use the pdf library". Keep every install local to the project (a
project virtualenv, a project `node_modules`, an explicitly project-scoped target directory), never
global and never the shared user site (a `pip install --user` persists across projects), so the
skill does not alter the user's computer. List packages explicitly, because other surfaces than
Claude Code constrain installs differently.

**Record.** Pointer: for the inject-once lifecycle, see
[Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle); for
`${CLAUDE_SKILL_DIR}` and `allowed-tools`, see
[Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference); for plugin
path rules, see <https://code.claude.com/docs/en/plugins-reference>; for network and install
constraints per surface, see
[Runtime environment constraints](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview#runtime-environment-constraints)
and
[Package dependencies](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#package-dependencies).
As of: 2026-09-10 (overview re-read 2026-09-11). Recheck trigger: the lifecycle section changes the
inject-once behavior, or the overview's runtime constraints change for Claude Code. Forked context
(`context: fork`) is not restated here: the in-repo owner is
`docs/conventions/invocation-context/README.md`.

## Argument surface

Shape the surface as `/plugin:skill [action] [--modifier ...] [<subject>]` with at most one subject,
give a token a `--flag` only when it passes the earned-flag test, and write `argument-hint` in the
same order and notation. A `--flag` is a token in `$ARGUMENTS` that the body reads in prose. The
[skill argument shape convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/skill-argument-shape/README.md)
owns the rule, the earned-flag test, how the body reads `$ARGUMENTS` and when a positional
binding is safe, the worked fits, and the decisions to decline `arguments:` and to defer a
`skill-quality` lint for the shape.

**Record.** Pointer: the convention's Record table holds the record for each harness behavior this
rule depends on, against
[Available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions)
and [Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference). As of:
2026-09-28. Recheck trigger: either section changes, or Claude Code ships argument validation for
skills.

## MCP tool names

Reference an MCP tool by its fully qualified Claude Code name, in the body, in `allowed-tools`, in
permission rules, in a subagent's `tools`, and in hook matchers: `mcp__<server>__<tool>` for a
server the user or project configured (for example `mcp__github__get_me`), and
`mcp__plugin_<plugin>_<server>__<tool>` for a server a plugin bundles. Never write the
best-practices page's cross-surface form, a bare server key, or a colon form in a Claude Code
skill. `docs-hygiene:audit-progressive-disclosure` carries the same two forms as a pointer-quality
criterion, where installed.

**Record.** Pointer: for the Claude Code forms, see
[Plugin-provided MCP servers](https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers) and
[MCP permissions](https://code.claude.com/docs/en/permissions#mcp); for the cross-surface form, see
[MCP tool references](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#mcp-tool-references).
As of: 2026-09-10. Recheck trigger: any of the three changes the name form.

## Output templates and examples

When a skill produces a structured artifact, put the shape in the body and say how strict it is:
the framing sentence is the only strictness control the pattern offers. Frame data formats and
machine-read output as an exact template the model must follow; frame adaptable output as a
sensible default with an explicit release line. Omit the release only when the structure is
fixed. The page's example framing sentences are at the pointer.

Where output quality depends on style (commit messages, report prose), give two or three labeled
input/output pairs and close with one line naming the rule the pairs illustrate. The pairs carry
the style; the closing line names it.

Where several tools could do a job, name one default and at most one escape hatch with its trigger
condition, in the shape "Use A for B. For C, use D instead." A menu of alternatives is a decision
the model has to make mid-task. Offer a real menu only when the right choice depends on something
discoverable only at run time, and then say what that something is.

**Record.** Pointer: for the patterns, see
[Common patterns](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#common-patterns)
and
[Anti-patterns to avoid](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#anti-patterns-to-avoid).
As of: 2026-09-10. Recheck trigger: the page changes either framing or drops the escape-hatch
example.

## Time-sensitive content

No date-conditional guidance in a body ("before August, use the old API"): state the current
method only. This marketplace does not keep superseded guidance in an in-body section, collapsed
or not, apart from the one exception below. History routes to the plugin `CHANGELOG.md`, the
commit message, and `docs/adr/`, and a volatile specific the body depends on is replaced by a
links-only record: our decision in our words, a pointer to the exact upstream section, an as-of
date, and a recheck trigger, with no upstream text. The reason is the cost model above: a collapsed
block is still tokens on every turn after invocation, while a separate reference file is free until
read, so history that must travel with the skill goes in a spoke. The record shape is the
upstream-drift convention's `docs/conventions/upstream-drift/README.md#required-parts`, and
`.claude/rules/skill-bodies-state-current-rules.md` applies it to skill and agent bodies.

The exception: a skill whose users still meet renamed API or interface names may keep an "Old
patterns" section holding a table that maps each old name to its current one. The table carries
names only, never a description of behavior, and the section ends in its own record. Where the
section may sit and what it may hold are owned by
`docs/conventions/upstream-drift/README.md#old-patterns-mapping-tables`; read the limits there.

**Record.** Pointer: for the page's treatment of superseded guidance and of an "Old patterns"
section, see
[Avoid time-sensitive information](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#avoid-time-sensitive-information).
As of: 2026-10-02. Recheck trigger: the page drops or changes that section; then re-read the
upstream-drift carve-out, which depends on the same section.

## Evaluation and iteration

Write the evals before the body: note the gaps Claude shows on representative tasks without the
skill, build scenarios that test those gaps, measure a baseline, write the minimum instructions
that pass, and iterate. Run every prompt twice, each time in a new session, once without the skill
and once with it: the session that wrote the skill already knows what its text leaves out. Score
triggering and output separately: does the skill fire where it belongs and stay silent elsewhere,
and is the result right when it fires. A trigger proves discovery, not correctness.

`evals/evals.json` in this repository follows the runner's shape: `skill_name`, then `evals[]`
with `id`, `prompt`, `expected_output`, `files`, and `expectations` (the bundled schema also accepts
`assertions`). The best-practices page's evaluation record is illustrative, not the file format.
`/skill-quality:check validate-evals <skill>` checks the file against the schema and runs the
eval-quality lint.

The two-instance loop: author with one session, test with a fresh one that has only the skill
loaded, carry specific observed failures (not impressions) back to the authoring session, and read
the test transcript for four navigation signals: files read in an unexpected order, a reference
never followed, one file read repeatedly (promote it into the body), a bundled file never read (cut
it or signal it better). Where the bundled skill-creator plugin is installed, its eval modes run
this loop with a subagent per case. Use `/skill-doctor`, where it resolves, to answer "does it
activate" from usage data, never "is the output right"; its version floor and availability are at
the pointer. Run this loop for a skill's eval file; route a plugin measured as a plugin to
`claude plugin eval`, whose case format is separate from `evals/evals.json`. For a
`claude plugin eval` case, put everything the case depends on in the hub `SKILL.md`, not a spoke.

Carrying a failure back: read the whole failure first (the case's input, the output, and the
grader's failure text), then write the general cause into the skill in your own words. Never copy
a case's prompt, output, or distinctive phrasing into the skill, and never draw a change from
held-back test cases.

Re-run the evals whenever a skill's description or body changes: a description change re-measures
triggering (`/skill-quality:check measure-invocation`), a body change re-measures output (the loop
above, or `/evals:plugin-eval` for a plugin suite). Runs are on demand; no CI workflow in this
marketplace runs model-graded evals.

When a rule is being missed, try both directive wording (a capitalized must) and reasoning-based
wording (the rule plus the reason it exists). The evals settle it.

**Record.** Pointer: for the fresh-session baseline and skill-creator modes, see
[Evaluate and iterate on a skill](https://code.claude.com/docs/en/skills#evaluate-and-iterate-on-a-skill);
for `/skill-doctor`, see [Find unused skills](https://code.claude.com/docs/en/skills#find-unused-skills);
for the eval file shape, see <https://agentskills.io/skill-creation/evaluating-skills> and
`plugins/skill-quality/reference/evals.schema.json`; for the loop and the four signals, see
[Evaluation and iteration](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#evaluation-and-iteration);
for `claude plugin eval` and its format separation, see
[Test plugins with evals](https://code.claude.com/docs/en/plugin-evals); for keeping a case's
dependencies in the hub, see the hub-only record that `/evals:plugin-eval` carries, with its own
evidence and trigger. For carrying a failure back as a general cause, see
[Iterating on the skill](https://agentskills.io/skill-creation/evaluating-skills#iterating-on-the-skill);
for keeping held-back test cases out of a change, see
[eval-hillclimb.md Step 4](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#step-4-the-loop)
and
[Failure modes to avoid](https://github.com/anthropics/skills/blob/8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4/skills/claude-api/shared/evals/eval-hillclimb.md#failure-modes-to-avoid)
at the pinned commit (correlate with
<https://claude.dev/blog/automating-eval-design-and-hillclimbing#overfitting>). As of: 2026-09-10
(plugin-evals read 2026-09-12; hub-only record, failure carry-back and held-back pointers
2026-10-02). Recheck trigger: the plugin-evals page drops the format separation or its runner
starts reading `evals/evals.json`, the skills page changes the `/skill-doctor` gate, the loop, or
the skill-creator modes, the best-practices page changes the four signals, the runner changes its
record shape, the `/evals:plugin-eval` hub-only record's trigger fires, the agentskills.io
iterating section changes, or a commit to `anthropics/skills` changes Step 4 or the failure modes
of `eval-hillclimb.md` (then move the pin).

## Model coverage

Test a skill on every model it will run on. No runner enforces this, so the checklist carries it
as an attestation: the author states which of the harness aliases (`haiku`, `sonnet`, `opus`,
`fable`) the skill was exercised on. A skill that runs under a `model` override or inside a
subagent has more than one target, and the attestation names them all or says which are untested.

**Record.** Pointer: for the alias list, see
[Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model); for the per-tier
questions, see
[Test with all models you plan to use](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#test-with-all-models-you-plan-to-use).
As of: 2026-09-10. Recheck trigger: the alias list changes.

## Skill model

Set frontmatter `model` on a skill only for work that needs it for the rest of the invoking turn,
and use `inherit` to leave the session's model in place. With `context: fork`, the field picks the
model of the forked run rather than the invoking turn. Read the auto-mode exception at the pointer
before relying on a `model` value in an auto-mode session.

**Record.** Pointer: for the `model` row, see
[Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference). As of:
2026-09-28. Recheck trigger: that row changes the turn scope, the auto-mode exception, or the
`context: fork` rule.

## Agent model

A plugin agent definition names its `model` in frontmatter. `inherit` is reserved for an agent that
must run on the orchestrator's model, and it says why in a trailing comment on the same line:
`model: inherit  # reason: <why>`. We pin because a definition that omits the field falls back to
the orchestrator's model wherever no override is set, which costs the same as `inherit` with
nothing to show it was chosen. The pin is the default; a dispatching skill overrides it per run
with the per-call `model`, which replaces the pin in either direction. In the claude-code-plugins
marketplace, `scripts/validate-plugin-contracts.mjs` fails an agent definition that breaks either
rule.

**Record.** Pointer: for the resolution order and the omitted-field fallback, see
[Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model). As of: 2026-09-27.
Recheck trigger: the page changes the order, or a release note names subagent model resolution.
