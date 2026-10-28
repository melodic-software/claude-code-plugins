# discipline/tighten-your-output

Tightens the prose or code it is given, or the work in flight, without losing meaning.

## Parts

- Rewrites the text passed as its argument in fewer words.
- With no argument, audits the session's own recent output for avoidable verbosity.
- Reports what it cut and what it kept.

## Sub-features

none

## Entry points

- `/discipline:tighten-your-output <text>` as the `logs` prompt, in print mode | driven
- `/discipline:tighten-your-output <text>`, typed at the prompt of the terminal session | driven
- A request in plain words to say a text in fewer words, typed at the prompt | driven
- The same skill in Claude Desktop | not driven: terms

## Reset

None: the skill only answers in the transcript.

## Drive

1. Capture `logs` with the prompt
   `/discipline:tighten-your-output In order to be able to run the tests, you will first need to install all of the dependencies.`
2. For a terminal-session entry point, drive it as the driving tool's `skills/invoke` feature with
   the same prompt.

## Gotchas

- The skill reads `plugins/discipline/context/re-anchor-audit-correct.md`, so start the run from the
  repository root. Where the restricted launch lets file tools read: the `--restricted` row of
  <https://code.claude.com/docs/en/cli-reference#cli-flags> (as of 2026-10-28; recheck when that
  row changes where file tools may read).
