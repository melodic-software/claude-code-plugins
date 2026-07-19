---
name: setup
description: "Verify the playwright plugin's runtime prerequisites — the playwright-cli binary and a resolvable browser — for this machine. Use when: 'set up playwright', 'configure playwright', 'is playwright working', 'install playwright-cli', a browser flow reports the CLI is missing, or before a first E2E run. Actions: check (read-only verification, default) | apply (resolve what check found; apply install-cli performs the global CLI install). Re-runnable and safe."
argument-hint: "check | apply [install-cli]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration and no `userConfig` — it
recommends `@playwright/cli`'s own defaults — so the only tunable prerequisite is the CLI
binary itself. `apply` is guidance-and-verify with exactly one write path: the explicitly
invoked `apply install-cli` global npm install described below.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers the resolution for each finding; `apply install-cli` additionally authorizes the global
CLI install. All are non-interactive — never prompt when the action is given.

## `check` (read-only)

The main skill and its reference files are the single source of truth for what the CLI
requires: `${CLAUDE_PLUGIN_ROOT}/skills/playwright/SKILL.md` (Prerequisite + quick start) and
`${CLAUDE_PLUGIN_ROOT}/skills/playwright/reference/` (`commands.md`, `windows-quirks.md`).
**Read them first** — probe what they actually require, don't recite this file. Then run each
probe via Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not
modify anything.

1. **`playwright-cli` binary** — `command -v playwright-cli` (the binary name the skill drives;
   the npm package is `@playwright/cli`). FAIL if absent — remediation is `apply install-cli`
   below. When present, report the version (`playwright-cli --version`).
2. **Browser availability** — the CLI needs a browser beyond its own install. Per the plugin's
   own `reference/windows-quirks.md`, local sessions on Windows/macOS/Linux auto-detect system
   Chrome, while a sandboxed/cloud session must run `playwright-cli install-browser` and that
   download can be egress-blocked. INFO: state whether a system browser is resolvable on this
   host and, when it is not, surface the `playwright-cli install-browser` step and the
   sandbox-egress caveat from that reference — do not assert a browser requirement the shipped
   docs do not; read them and report what they say.
3. **Artifact directory** — INFO: artifacts land in `.playwright-cli/` relative to the working
   directory; note whether it is gitignored in the current project (the skill recommends
   adding it). No write — reporting only.

## `apply` (idempotent)

Run `check`, then for each FAIL offer the resolution. `apply install-cli` is the one write
path — state the change before running it:

- **CLI absent** — `apply install-cli` runs `npm install -g @playwright/cli`. This is a
  **global install that mutates the user's machine** (the global npm prefix), stated before it
  runs; without the `install-cli` argument, `apply` only prints this command for the user to
  run. After the install, re-run `command -v playwright-cli` and report the actual result —
  never claim success on npm's exit code alone.
- **browser not resolvable** — point at `playwright-cli install-browser` per the plugin's
  reference, and note the sandbox-egress caveat when relevant. Guidance only — this skill does
  not provision browsers.
- **`.playwright-cli/` not gitignored** — suggest adding it to the project `.gitignore`;
  guidance only, no edit.

The vendored-baseline update flow (`/playwright:playwright update`) is **not** this skill's
job — point at it, do not wrap it. Re-running `apply` when everything already passes changes
nothing and reports "already configured".

## What this skill does NOT do

- Write anything other than the one explicitly invoked `apply install-cli` global npm install;
  it never edits project files, settings, or the plugin cache.
- Provision browsers, run E2E flows, or take screenshots — that is `/playwright:playwright`.
- Run or wrap the maintainer update flow (`/playwright:playwright update`).
