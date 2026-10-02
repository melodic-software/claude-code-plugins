# widget-service

## Build and test

Run `make test` before every commit. CI runs the same target.

## Pull requests

Open every pull request as a draft. Title it in Conventional Commits form.

## Claude Code hooks

The `PreToolUse` hook in `.claude/settings.json` blocks writes under `generated/`. Never edit
files there by hand; regenerate them with `make codegen`.
