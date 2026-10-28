# discipline/wait-what

Explains the previous reply again in Simplified Technical English, with the context the reader lacked.

## Parts

- Goes back to the last point the reader followed and explains again from there.
- Uses the project's own domain terms, from its glossary when one exists.

## Sub-features

none

## Entry points

- `/discipline:wait-what` typed at the prompt of the terminal session, after a reply | driven
- `/discipline:wait-what` as the `logs` prompt, in print mode | not driven: a print-mode run has no previous reply to explain
- A request in plain words | not driven: `disable-model-invocation: true` keeps the model from picking it
- The same skill in Claude Desktop | not driven: terms

## Reset

None: the skill only answers in the transcript.

## Drive

1. Drive it as the driving tool's `skills/invoke` feature: first type any question and wait for the
   reply, then type `/discipline:wait-what`.

## Gotchas

- The skill needs a previous reply in the same session; only the terminal session has one.
