# Skill criteria

The house standard for writing a skill or a plugin agent in this marketplace. Cite it as
`/playbooks:skill-authoring` plus a heading below; the headings are stable.

Precedence: official Anthropic guidance wins. Where it is silent, follow the concise style of
Pocock's skills. Every upstream figure below is a record of what a source said on a date ("per X,
as of D"), never our own rule; [Sources](#sources) holds each pointer and recheck trigger. Where a
cap is enforced, `/skill-quality:check` enforces it and its script holds the constant. A house
setting is named as one: a `/skill-quality:check` setting, or a choice of this page's protocol.

The deletion test governs every line, in the description, the body, a reference file or an agent:
could the model already know this, or do the job without it? If so, cut it. Cruft is not length:
never justify a deletion by character count alone, and never keep a line because it is short
(per the `claude-api` skill's prompt audit, as of 2026-10-06).

## Frontmatter

- Write `disable-model-invocation` explicitly on every skill (`/skill-quality:check` enforces the
  key) and decide it against the
  [invocation-mode rubric](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/invocation-mode/README.md).
  Per the Claude Code skills docs, as of 2026-10-06, `user-invocable` defaults to true and
  `disable-model-invocation` to false.
- Shape arguments and `argument-hint` per the
  [skill argument shape convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/skill-argument-shape/README.md)
  and the [argument-hint house style](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/argument-hint/README.md);
  a skill with no arguments omits the key.
- Set `model` only for work that needs it for the rest of the invoking turn; the hub's Skill
  `model` section carries the record.
- Default to inline execution. Set `context: fork` only when the
  [invocation-context rubric](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/invocation-context/README.md)
  says it pays, and give a forked skill `background: false` unless a skill-specific confirmation
  chooses async.
- Grant an exact command through `allowed-tools` with a matching Bash rule, never a broad
  interpreter wildcard.
- `metadata` holds only the keys [Metadata](#metadata) allows.

## Descriptions

- **Model-invoked:** what it is, then "Use when" with one trigger per branch of what the skill
  does: `Noun phrase. Use when <branch>, <branch>.` (Pocock's shape, as of 2026-10-06). Enumerating
  every phrasing a user might type is the trigger-case defect the prompt audit flags. Use the
  nouns a user would type, and lead with the main use case: the listing truncates from the end.
- **User-invoked** (`disable-model-invocation: true`): a one-line summary, no trigger list. Per
  the Claude Code skills docs, as of 2026-10-06, its description is not in the model's context.
- Third person. No first or second person in the prose; a quoted user utterance keeps the user's
  voice. Trigger text may keep calibrated urgency.
- Name a sibling skill only when probes show the two are confused (see [Measurement](#measurement)).
- Length records: per the platform best practices, `description` alone is at most 1,024
  characters (an Agent Skills specification and upload limit; Claude Code does not validate it);
  per the Claude Code skills docs, `description` plus `when_to_use` is truncated at 1,536 characters
  in the listing, `when_to_use` extends the one description, and an overflowing listing (about 1%
  of the context window) drops the least-invoked skills' descriptions first. Per our measure of
  Pocock's skills, descriptions run median 130 and max 419 characters. All as of 2026-10-06.
  `/skill-quality:check` enforces both caps and estimates the shared budget (`listing-budget`).

## Body

- Apply the deletion test, then the prompt audit's flags: trigger-case enumeration, step
  choreography for a judgment task, history narratives (see
  [History and provenance](#history-and-provenance)), and restated volatile specifics, which
  become a pointer record instead.
- **Degrees of freedom.** A judgment task gets the goal, the constraints and the reason beside
  each, not a step script. A fragile or mandatory sequence gets the exact command (a bundled
  script) and an instruction not to alter it; only such a sequence earns a copyable checklist.
  Decide per section. When a skipped gate is costly, a hook is the escalation, charged to the
  hook budget (`docs/conventions/hook-budget/README.md`).
- Standing rules go in the body; bulk goes in reference files. Put a workflow or checklist first
  after the frontmatter: compaction re-attaches only the start of an invoked skill.
- For structured output, the framing sentence sets strictness: an exact template for
  machine-read output, a default with a release line otherwise. Where style matters, give two or
  three labeled input/output pairs and one line naming the rule. Name one default tool and at most
  one escape hatch with its trigger.
- Deterministic work goes in a bundled script. SKILL.md cites it as
  `${CLAUDE_SKILL_DIR}/scripts/<name>` with the verb ("Run" to execute, "See" to read), forward
  slashes only. State each dependency's install command, kept local to the project.
- Name MCP tools fully: `mcp__<server>__<tool>`, or `mcp__plugin_<plugin>_<server>__<tool>` for a
  plugin-bundled server.
- Keep a gotchas surface (`## Gotchas` or a gotchas spoke) and a `## Next` section per
  `.claude/rules/skill-bodies-state-current-rules.md`.
- Length records: per the platform best practices, SKILL.md stays under 500 lines; per our measure
  of Pocock's skills, bodies run median 70 and max 160 lines (as of 2026-10-06).
  `/skill-quality:check` enforces the hard cap. Length is the symptom; the deletion test is the
  remedy.

## Reference files

- One level deep: every reference file links from SKILL.md (per the platform best practices).
- Each pointer says what the file holds and when to read it; a bare "see X" is a missed
  connection.
- A spoke is read, not rendered, so no substitution variable resolves in it: cite
  `<skill-dir>/scripts/<name>`. `scripts/check-spoke-plugin-root.sh` gates the plugin-root
  variable in this marketplace.
- A long spoke opens with a `## Contents` block; `/skill-quality:check` warns when a spoke over
  its own line setting lacks one.
- A spoke is free until read and then costs like the body: the deletion test applies in full.

## Metadata

`metadata` holds only keys an agent or a named script consumes. `/skill-quality:check` owns the
registry of allowed keys, each with its consumer; a new key lands there with the consumer that
reads it. A key nothing reads is cut.

## History and provenance

- No PR or issue numbers, "added in" notes, incident narratives or date-conditional guidance in a
  skill. Git, the CHANGELOG, issues and ADRs hold history.
- Exempt: pointer records (pointer, as-of date, recheck trigger, per the
  [upstream-drift convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#required-parts))
  and cross-repo `owner/repo#N` pointers to an upstream bug.
- A skill whose users still meet renamed names may keep a names-only "Old patterns" table, within
  the upstream-drift convention's limits.
- Attribution lives outside the skill: README, LICENSE or NOTICE, CHANGELOG.

## Agents

- `agents/*.md` bodies follow the same deletion test, history and degrees-of-freedom rules.
  `/harness-config:audit-instructions` audits them; `/skill-quality:check` does not.
- The `description` says when to delegate to the agent, in the same one-trigger-per-branch shape.
- Grant only the tools the agent needs.
- Pin `model` in frontmatter. `inherit` only for an agent that must run on the orchestrator's
  model, with the reason on the same line: `model: inherit  # reason: <why>`. An omitted field
  falls back to the orchestrator's model with nothing to show it was chosen; a dispatching skill
  overrides per call. `scripts/validate-plugin-contracts.mjs` fails a definition that breaks
  either rule.

## Measurement

**Authoring a new skill.** Write the evals before the body: note what Claude gets wrong without
the skill, build cases for those gaps, measure a baseline, write the minimum that passes. Test in
a fresh session (the authoring session knows what the text leaves out), once without the skill and
once with it. Score triggering and output separately. Read the test transcript for four signals:
files read out of order, a reference never followed, one file read repeatedly (promote it), a
bundled file never read (cut it). Carry a failure back as its general cause in your own words;
never copy a case's text and never use held-back cases.

**Rewriting an existing skill.**

1. Snapshot the before state: description, body, eval results.
2. Freeze a probe set of 16 to 20 queries (this protocol's house setting), written by a fresh
   agent from the before description,
   including near-misses aimed at same-plugin competitors.
3. Measure before and after: the model-graded trigger rate on the probes
   (`/skill-quality:check measure-invocation`) and the plugin's eval cases.
4. Diff meaning with `/docs-hygiene:compress compare`, labelled by a fresh agent.
5. Ship on non-inferiority: no lost trigger, case or directive. A deterministic lexical score is a
   tripwire only, never the verdict.

Re-run on any change: a description change re-measures triggering, a body change re-measures
output (`/evals:plugin-eval` for a plugin suite). `evals/evals.json` follows the runner's shape;
`/skill-quality:check validate-evals <skill>` checks it.

**Pre-share checklist.** Each row is mechanical (a `/skill-quality:check` check decides it),
judgment (a reviewer reads) or attestation (the author states it).

- Frontmatter and body: description caps (mechanical, checks 2 and 2b); "Use when" phrasing
  (mechanical, check 12); SKILL.md line cap (mechanical, check 4); skill-internal paths resolve
  with forward slashes (mechanical, check 5); spoke directories referenced from the hub
  (mechanical, check 15); `## Contents` on a long spoke (mechanical, check 26); explicit
  `disable-model-invocation` (mechanical, check 24); gotchas surface (mechanical, check 11);
  arguments follow the skill argument shape (judgment); every other rule on this page
  (judgment).
- Scripts: `scripts/*.test.sh` pass (mechanical, check 7); no committed cache or build artifacts
  (mechanical, check 13); injected `!` commands portable with a fallback (mechanical, checks 19
  and 20); output names what the script did, including on failure (judgment).
- Evals and testing: `evals/evals.json` present (mechanical, check 14) and valid
  (`validate-evals`); fresh-session baseline captured (attestation); models exercised, from
  `haiku`, `sonnet`, `opus`, `fable` (attestation); a skill run under a `model` override or
  inside a subagent names every target model, or says which are untested (attestation).

Close with `/skill-quality:check <skill>`: it answers the mechanical rows, and its WARN lines are
the reviewer's reading list for the rest.

## Sources

Each record: pointer, as-of date, recheck trigger. Re-read the pointer before acting on a figure.

- **Claude Code skills docs**: listing cap and budget at
  [Skill descriptions are cut short](https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short);
  invocation defaults at
  [Frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference); the
  user-invoked context rule at
  [Control who invokes a skill](https://code.claude.com/docs/en/skills#control-who-invokes-a-skill);
  compaction at
  [Skill content lifecycle](https://code.claude.com/docs/en/skills#skill-content-lifecycle); the
  fresh-session loop at
  [Evaluate and iterate on a skill](https://code.claude.com/docs/en/skills#evaluate-and-iterate-on-a-skill).
  As of 2026-10-06. Recheck: the listing cap, the listing budget, an invocation default, or the
  user-invoked context rule changes.
- **Platform best practices**: description cap at
  [YAML frontmatter requirements](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#yaml-frontmatter-requirements);
  voice at
  [Writing effective descriptions](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#writing-effective-descriptions);
  [Set appropriate degrees of freedom](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#set-appropriate-degrees-of-freedom);
  line limit at
  [Progressive disclosure patterns](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#progressive-disclosure-patterns);
  [Avoid deeply nested references](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#avoid-deeply-nested-references);
  [Evaluation and iteration](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#evaluation-and-iteration);
  [Checklist for effective Skills](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#checklist-for-effective-skills).
  As of 2026-10-06. Recheck: the description cap, the voice rule, the line limit, the nesting
  rule, or a checklist item changes.
- **Agent Skills specification**: the portable `description` limit at
  [description field](https://agentskills.io/specification#description-field). As of 2026-10-06.
  Recheck: that field's limit changes.
- **Prompt audit**, `shared/prompt-audit.md` in the `claude-api` skill bundled with Claude Code
  (read at 2.1.292). As of 2026-10-06. Recheck: a Claude Code release changes that file.
- **Subagent docs**: [Choose a model](https://code.claude.com/docs/en/sub-agents#choose-a-model)
  and [Available tools](https://code.claude.com/docs/en/sub-agents#available-tools). As of 2026-10-06. Recheck: the model resolution order or the omitted-field fallback
  changes.
- **Pocock's skills**, <https://github.com/mattpocock/skills> at commit `6fd9479`, measured by us
  over 38 skills. As of 2026-10-06. Recheck: a re-measure at a newer commit moves a median or a
  shape.
- **Skill-creator**, <https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md>
  (eval modes, description voice). As of 2026-10-06. Recheck: its eval modes or frontmatter
  voice change.
- **Vendored playbook**, `vendor/upstream-skill.md`, maintained by `/playbooks:update`. Drift check
  2026-10-07: frontmatter version 1.0.0 matches upstream; content SHA256 differs (vendored copy
  7b0923d8…, upstream 05b4e6b7…), sync pending. Recheck: the next `/playbooks:update` run.
