---
description: "Draft an `autoMode` classifier block for Claude Code by interviewing you about what should and should not be auto-approved, then printing a paste-ready JSON block to stdout. Entries follow the shape the classifier actually reads well — a label, bulleted COVERED / NOT COVERED, one line of rationale — and every section keeps `\"$defaults\"` so customizing does not discard the built-in rules. Use when: 'help me write auto mode rules', 'draft an autoMode block', 'set up auto mode', 'add an auto-mode rule for X', 'my auto mode rules are too vague', 'rewrite this classifier entry', or after an audit shows rules being dropped or ignored. Prints only — never writes any settings file."
argument-hint: "[section] — environment | allow | soft_deny | hard_deny to focus the interview"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Interview and draft a paste-ready autoMode block, never writing settings
---

## Purpose

The `autoMode` block is a natural-language prompt for a classifier, not a rule list the harness
matches — so it fails in ways a config file does not. `claude auto-mode critique`, run against a real
66 KB hand-authored block, found the pattern: the classifier is "an LLM doing a single pass under a
'default is ALLOW' instruction", so "buried conditions in paragraph position 40 will be missed at a
materially higher rate than conditions in a bullet list."

This skill applies that finding at authoring time instead of reporting it afterwards.

## Report-only, permanently

**This skill writes nothing, in any scope, under any flag.** It prints a block; you paste it. Editing
a consumer's settings file would be making a permission decision on their behalf, which is the one
thing this plugin exists not to do.

## Scope boundary (route out)

- What is in effect now, what auto mode drops, what a section discards →
  `claude-config:audit-permission-state`. **Run it first** — drafting against rules you have not read
  is how a block ends up contradicting itself.
- Grant portability and auto-mode durability → `claude-config:audit-permission-grants`.
- Whether an existing block is any good → `claude auto-mode critique`, surfaced by
  `audit-permission-state --critique`. It owns the semantic judgment; this skill owns composition.

## Inputs, and one deliberate omission

The draft is built from **the interview plus the effective merge** (`audit-permission-state`), and
nothing else.

An earlier design read "the repo's observed prompt and denial history". That was dropped: it named no
actual location, and an unnamed read surface in a skill shipped to consumers is unreviewable. Do not
reintroduce a history input without re-opening that decision.

## Phase 1: Read what already exists

Before asking anything, run the audit sibling and read its output:

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-state/scripts/automode-block-lint.sh"
```

Three things there change what you should ask:

- A section missing `"$defaults"` means built-in rules are **already** discarded. Say so before adding
  to that section.
- A `C2b-contradiction` or `C3-shadowed` finding means the block already disagrees with itself.
  Resolving that comes before adding an entry that would deepen it.
- A `status=skipped` or `status=unavailable` result means you could **not** read the block. Draft
  anyway if asked, but say plainly that you are drafting blind.

## Phase 2: Interview

<!-- fresh-eyes-exempt: external-input -- the material judged here is the consumer's stated intent and their own existing configuration; no step judges output this skill authored -->

Ask about one entry at a time. For each, you need four things, and the fourth is where drafts fail:

1. **Which section.** `allow` (auto-approve), `soft_deny` (block, overridable), `hard_deny` (never),
   `environment` (facts the classifier needs — organization, repositories, trusted domains).
2. **A short label** — the subject, two or three words. It is what a reader scans for.
3. **What is covered, and what is explicitly not.** Both. An entry with no stated exclusions is one
   the classifier will over-apply.
4. **A condition visible in the transcript.** This is the one that matters. The critique's finding was
   that "uncheckable conditions are the biggest weakness" — entries state preconditions the classifier
   cannot evaluate from the command text, so it either allows blindly (the condition is decorative) or
   blocks (the grant is inoperable), with no stated disposition.

   When an answer names something the classifier cannot see — a person's intent, a fact about the
   build server, whether a change was reviewed — **say so and ask for the observable form instead**.
   "Only when the deploy is approved" is not checkable; "only when the command names the staging
   endpoint" is.

Stop when they say stop. A short correct block beats a long vague one.

## Phase 3: Compose

Feed the answers to the drafter, one record per line:

```text
section allow
label Test Execution
covered running the repository's own test suite via its documented runner
not installing new dependencies as a side effect
why the runner is named in the command text
```

```shell
bash "${CLAUDE_PLUGIN_ROOT}/skills/draft-auto-mode-rules/scripts/draft-automode-block.sh" < answers
```

It prints a JSON object carrying only the sections that got entries. **An unknown section name
is a hard failure** — exit 2, nothing on stdout — rather than a warning beside partial output,
because a caller capturing both streams together would otherwise get unparsable JSON. **Every section opens with
`"$defaults"`** — customizing a section replaces the built-in list rather than adding to it, so
omitting the token silently discards every shipped rule in that section.

## Phase 4: Hand it over

Print the block, say exactly where it goes — the `autoMode` key of
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json` — and stop.

Two things to say while handing it over, because both are load-bearing:

- **Project and local settings will not work.** The classifier reads `autoMode` from user settings,
  managed settings, and inline `--settings`/SDK JSON only. A block pasted into `.claude/settings.json`
  is silently inert.
- **Merging into an existing block is theirs to do.** If they already have an `autoMode` section, the
  drafted sections replace what they paste over. Point them at the audit sibling to confirm the result
  rather than assuming it merged.

## Gotchas

- **Do not offer to write the file.** Not with `--fix`, not "shall I apply this", not as a follow-up.
  The no-write posture is the skill's contract, not a default someone can opt out of.
- **A drafted block is not a reviewed block.** After they paste it, `claude auto-mode critique` is what
  judges it. Say that rather than implying the draft is validated.
- **`claude auto-mode reset` is never run.** It strips the `autoMode` section from user settings, and
  on a chezmoi-managed home that loss is not recoverable from the settings file alone.
- **Prose provenance does not belong in an entry.** Dates, issue numbers, and prior-draft archaeology
  cost classifier attention and buy nothing; the critique names stripping them explicitly. Version
  control owns that history.
