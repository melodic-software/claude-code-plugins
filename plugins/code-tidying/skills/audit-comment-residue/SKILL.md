---
description: "Read-only classifier that flags residue in code comments: history narration, plan or session references, conversational asides, ticket or PR back-references, origin notes, and workarounds with no link or removal condition. Use when asked to 'audit code comments' or report which comments only make sense with the chat, plan, or ticket behind them, before a commit or on review. Edits nothing; deleting or rewriting comments is /code-tidying:remove-comments."
argument-hint: "[audit] [--added-since <base>] [target]"
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

## Next

- The findings are agreed and ready to apply: `/code-tidying:remove-comments` on the same target.
- The surviving comments restate the code rather than narrate its past: `/code-tidying:tidy`.
- An `unjustified-workaround` finding marks code whose cause is still unfixed: `/debugging:debug` or
  `/implementation:implement`.

## Gotchas

- A leading `audit` passed through unchanged reaches the audit action as a file target, so it is
  dropped before the call.
