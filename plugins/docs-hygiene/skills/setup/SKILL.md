---
description: "Verify that markdownlint-cli2, the lint gate /docs-hygiene:compress requires, resolves and runs for this repository. Use when: 'set up docs-hygiene', 'is docs-hygiene ready', 'compress stopped because markdownlint-cli2 is missing', or before the first compress run. Check-only: verifies, reports the remediation, installs nothing. Re-runnable and safe."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
shell: bash
---

## Purpose

Check-only setup under the Check-only carve-out (`docs/plugin-philosophy.md`, "Setup is explicit
and repeatable", in the marketplace repository). This plugin owns no consumer-project configuration
and declares no plugin options, so there is no artifact `apply` could write. Its one external
prerequisite is `markdownlint-cli2`, which `/docs-hygiene:compress` runs as its post-edit ship gate
and stops without. `check` resolves the binary, runs it, and reports the remediation. Installing is the
operator's.

Action routing: no argument or `check` runs the check. Non-interactive, never prompts.

## `check` (read-only)

Report a PASS/FAIL table with one remediation line per FAIL. Modify nothing.

1. **Resolve `markdownlint-cli2`** the way `compress` does: first `command -v markdownlint-cli2`
   (on `PATH`), then `node_modules/.bin/markdownlint-cli2` under the repository root. Report which
   one resolved. FAIL when neither does.
2. **Run it.** Execute the resolved binary with `--version`. A shim can resolve and still be broken
   (a missing Node interpreter, a dangling target), so resolution without a clean exit is FAIL, with
   the error text in the remediation line.

Remediation for a FAIL: install it explicitly, `npm install --save-dev markdownlint-cli2` in the
repository or a global install, then rerun `check`. Without it `/docs-hygiene:compress` stops at its
entry point before touching a file. No other skill in this plugin needs the binary.

## Next

`/docs-hygiene:compress`

## Gotchas

- **A missing binary is not a lint failure.** `compress` never ships unverified output, so absence
  stops it; `check` is how to see why before that happens.
- **Never install on the operator's behalf.** This skill runs no `npm`, no `npx`, and no download.

## What this skill does NOT do

- Run `markdownlint-cli2` over repository files. The only execution is the `--version` liveness probe.
- Check the consuming repository's markdownlint configuration. Which rules a repository adopts is its
  own decision.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`.
