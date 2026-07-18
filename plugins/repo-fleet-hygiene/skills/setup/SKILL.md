---
name: setup
description: "Configure repo-fleet-hygiene for a consumer project by creating or updating the optional .claude/repo-fleet-hygiene.conf: add bounded fleet roots, exact repositories, and remote-keyed canonical checkout overrides. Re-runnable and preserves unrelated entries. Use when: set up repo fleet audit, configure fleet roots, canonical repo override, dotfiles-manager checkout."
user-invocable: true
disable-model-invocation: true
argument-hint: "[--config <path>] [--root <dir>]... [--repo <dir>]... [--canonical <github.com/owner/repo=path>]..."
---

## Purpose

Create or update the audit's optional Git-format configuration. Setup owns only this file; it never
edits Claude Code settings, `pluginConfigs`, Git remotes, branches, worktrees, or the installed plugin.

Default config path: `${CLAUDE_PROJECT_DIR}/.claude/repo-fleet-hygiene.conf`. An explicit `--config`
may choose another path. Resolve relative roots/repos/canonical paths from the config file directory.

## Workflow

1. Parse only the declared argument grammar. Validate every root/repository/canonical path with
   read-only filesystem and `git rev-parse` checks. Normalize canonical keys to
   `github.com/owner/repository` (lowercase host, case-preserving owner/name is acceptable).
2. If the config exists, read it with `git config --file <path> --list --show-origin`. Preserve every
   unrelated entry. Never source it.
3. Show the proposed additions/updates. With complete arguments, proceed non-interactively; otherwise
   ask only for missing values. An empty invocation may create the minimal current-project config:

   ```gitconfig
   [fleet]
       repo = ..
       maxDepth = 5
   ```

   (`..` is relative to `.claude/` and therefore names `${CLAUDE_PROJECT_DIR}`.)
4. Write/update with an ordinary file edit, not `git config --file ... --add`: the file may be tracked
   and the user must see a deterministic diff. Preserve comments and unrelated sections.
5. Validate the final file without mutation:

   ```bash
   git config --file "<config-path>" --list >/dev/null
   bash "${CLAUDE_PLUGIN_ROOT}/skills/audit/scripts/audit-fleet.sh" --config "<config-path>"
   ```

6. Report path, inferred/explicit entries, preserved entries, and the read-only audit result.

## Configuration grammar

```gitconfig
[fleet]
    root = ../../repos/github.com   # repeatable discovery root
    repo = ../../special/repo      # repeatable exact target
    maxDepth = 5                   # integer 1..12

[canonical "github.com/owner/repository"]
    path = ../../../canonical-checkout
```

Resolution priority is explicit audit CLI override, canonical config entry, then discovered checkout's
`git rev-parse --show-toplevel`. Never add a canonical override merely because two directory names look
similar; verify the normalized GitHub remote identity on both sides first.
