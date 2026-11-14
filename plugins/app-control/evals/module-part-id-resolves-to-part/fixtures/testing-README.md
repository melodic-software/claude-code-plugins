# testing

The skills of the testing plugin. Each one is driven by its slash command.

## Parts

- `plan`: Classify changes by required test type.
- `run-e2e`: Start the app, drive real flows, capture evidence.
- `write`: Write tests with TDD cadence.

## Sub-features

none

## Entry points

- `/testing:<skill> <args>` in print mode | driven
- The same skill in a desktop client | not driven: no desktop client on the runner

## Reset

Nothing to reset.

## Drive

1. Run `/testing:<skill>` with `<skill>` from Parts. Result: the skill's first reply names its job.
2. **Proof.** Result: the reply names the skill. Captures: logs

## Gotchas

- None seen yet.
