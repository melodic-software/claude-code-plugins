---
name: setup
description: "Configure the repository-owned artifact convention used by discovery, planning, and implementation skills. Use when asked to set up planning, choose where lifecycle artifacts land, or reconcile an existing work-artifact convention. Re-runnable and idempotent."
argument-hint: "[--artifacts-dir <repo-relative-directory>]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Establish one portable, repository-owned base directory for lifecycle artifacts. This setup never edits
`pluginConfigs`, plugin files, or user-global settings. Personal plugin configuration is not a safe
coordination surface for files shared by a repository.

## Protocol

Read `${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md` before proposing or writing configuration.

## Workflow

1. Find the repository root with `git rev-parse --show-toplevel`. Stop visibly if the current directory
   is not in a repository.
2. Read the repository's loaded project instructions: root `CLAUDE.md`, `AGENTS.md`, `.claude/CLAUDE.md`,
   and `.claude/rules/*.md`. Look for an explicit lifecycle/work-artifact base directory.
3. Inspect existing candidate directories only for evidence. Never infer from a machine-absolute path,
   a gitignored personal directory, or a plugin cache path.
4. Resolve a proposal in this order:
   - `$ARGUMENTS` supplies `--artifacts-dir`: validate and propose that value.
   - The repository already declares a convention: preserve it unless the user requests a change.
   - Otherwise recommend `.work`.
5. Validate the proposed base: it must be repository-relative, must not contain a `..` segment, and its
   normalized path must remain under the repository root. Reject invalid values with a visible reason.
6. Present the single proposed value and the exact file/edit that would record it. Write nothing until
   the user accepts.
7. Persist the accepted convention in an existing project-instruction surface when one clearly owns
   work-artifact conventions. Otherwise create `.claude/rules/work-artifacts.md` with this concise rule:

   ```markdown
   # Work artifacts

   Discovery, planning, and implementation artifacts use `<artifact-base>/<topic-slug>/`.
   The repository artifact base is `<accepted-value>`.
   ```

8. Preserve unrelated content, confirm the instruction file is tracked rather than gitignored, and
   summarize the effective base. Re-running reads the existing declaration first and does not rewrite an
   equivalent value.

## Output

The accepted repository instruction change plus a one-line summary. If the user declines persistence,
report that invocations may still use `--artifacts-dir` and that the default remains `.work`.
