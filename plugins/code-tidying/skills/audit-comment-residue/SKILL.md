---
description: "Read-only classifier: flags residue in code comments (history narration, plan or session references, conversational asides, ticket/PR back-references, origin notes, workarounds with no link or removal condition). No edits. Use when: 'audit code comments' or report chat/ticket comments on commit/review. Not for edits: /code-tidying:remove-comments."
argument-hint: "[audit] [--added-since <base>] [target] [--repo <repo> ...]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Skill"]
metadata:
  workflow-stage: review
  summary: Classify code comments for history narration and session-reference residue
---

## Run it

Arguments: `$ARGUMENTS`

Drop one leading `audit` token from the arguments if they start with it. Then use the Skill tool to
run `/code-tidying:remove-comments audit` followed by what remains, and report what it returns. It
edits nothing and never asks; do not edit or delete a comment here.

A target form from [`${CLAUDE_PLUGIN_ROOT}/reference/target-scope.md`](../../reference/target-scope.md)
"Target forms" (`--repo`, `--repos-from`, `--owner`, `--fleet`, `--skip`, or the same request in
words) goes through with the rest of the arguments, so the audit runs once per repository as
`/code-tidying:remove-comments` "Over several repositories" says. With no target form, the audit
covers this checkout, as it always has.

## Next

- The findings are agreed and ready to apply: `/code-tidying:remove-comments` on the same target.
- The surviving comments restate the code rather than narrate its past: `/code-tidying:tidy`.
- An `unjustified-workaround` finding marks a bug whose cause is unknown: `/debugging:debug`.
- An `unjustified-workaround` finding marks a known cause ready to fix: `/implementation:implement`.

## Gotchas

- A leading `audit` passed through unchanged reaches the audit action as a file target, so it is
  dropped before the call.
