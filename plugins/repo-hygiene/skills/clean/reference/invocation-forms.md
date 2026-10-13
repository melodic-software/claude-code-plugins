# clean invocation forms: the two-form split

`/repo-hygiene:clean` carries two bundled-script invocation forms on purpose. Converting the
`context/*.md` files to a `${…}` token is not a fix.

## Paired form: `SKILL.md` + `allowed-tools`

`SKILL.md` and its `allowed-tools` frontmatter use the paired form:

- Body: direct, unquoted `${CLAUDE_SKILL_DIR}/scripts/<name>.sh`
- Rule: `Bash(${CLAUDE_SKILL_DIR}/scripts/<name>.sh:*)`

The pairing relies on Claude Code substituting `${CLAUDE_SKILL_DIR}` in both the body and the
`allowed-tools` rules. The five grants for scripts that delete nothing (`resolve-clean-action.sh`,
`scan.sh`, `preflight.sh`, `git-branch-audit.sh`, `git-stash-audit.sh`) are fully paired through
this surface.

- **Pointer**: where the token is substituted is in
  [Available string substitutions](https://code.claude.com/docs/en/skills#available-string-substitutions).
  **As of**: 2026-10-11. **Recheck trigger**: that section stops naming `allowed-tools` rules or
  the skill body among the places it substitutes, or a release note names string substitution in
  skills.

## Interpreter-led form: bundled `context/*.md`

The six routed detail files invoke through the interpreter-led form:

```bash
bash <skill-dir>/scripts/<name>.sh
```

Files: `context/action-router.md`, `context/clean-batch.md`, `context/git-branch-cleanup.md`,
`context/git-tree-reset.md`, `context/git-tree-reset-batch.md`, `context/preflight.md`.

They load on demand when `SKILL.md` routes into a step and reach the model through the Read tool as
plain bytes, so no `${…}` token in them is substituted. A token there would reach the Bash tool
unexpanded: `${CLAUDE_SKILL_DIR}` expands from an unset environment variable to `/scripts/x.sh`,
and `${CLAUDE_PLUGIN_ROOT}` to a path that resolves against nothing. They write the skill directory as
the `<skill-dir>` placeholder, which `SKILL.md`'s `## Spoke paths` section defines, and Claude puts
that path in before running the command.

## Commands a script runs itself

`clean-batch.sh --fleet` runs `ghq list -p` and `chezmoi source-path` inside the script. Claude
never issues them, so they need no `allowed-tools` grant, and `clean-batch.sh` stays ungranted
(it is a mutating script). Add a grant only for a command the skill body tells Claude to run.

## The rule

Keep `context/*.md` on the `<skill-dir>` placeholder form. A command the model takes from a
`context/*.md` does not match the paired `allowed-tools` rules and will prompt or fall to the
classifier. That is expected, because every granted script is also invoked from `SKILL.md`.

`scripts/allowed-tools-pairing.test.sh` pins both halves: the paired contract on `SKILL.md`, and a
guard that `context/*.md` never carry a `${…}` token for a script path.

## The host permission layer above the ack

`CLEAN_GUARD_ACK=1` satisfies only this skill's own PreToolUse guard. Claude Code evaluates its
permission layer independently of that guard, so a confirmed apply can still be denied or prompt:

- A matching permission rule is not lifted by this guard's ack, and how rules are ordered and how a
  hook's decision interacts with them is the permissions page's to state.
- In auto mode the classifier reviews the command as well. It denied hand-rolled bulk removals and
  batched worktree scripts on the audited machine
  ([why](../context/clean-batch.md#why-this-exists)), and its default block list is upstream's.
- An allow rule such as `Bash(<script>:*)` cannot be counted on to match a command that starts with
  `CLEAN_GUARD_ACK=1` and a space: the page does not list `CLEAN_GUARD_ACK` among the assignments it
  strips before matching. The skill's own `allowed-tools` grants cover only scripts that delete
  nothing, which never take the prefix.

When the confirmed apply is denied or prompts, tell the user which layer stopped it and let them
decide. Never work around it with a hand-rolled `rm` or another script.

- **Pointer**: rule evaluation order is in
  [Manage permissions](https://code.claude.com/docs/en/permissions#manage-permissions), and what a
  hook decision can override is in
  [Extend permissions with hooks](https://code.claude.com/docs/en/permissions#extend-permissions-with-hooks).
  **As of**: 2026-10-11. **Recheck trigger**: either section changes the evaluation order or what
  a hook decision can override, or is renamed.
- **Pointer**: which leading assignments a rule matches past is in
  [Wrappers](https://code.claude.com/docs/en/permissions#process-wrappers). **As of**: 2026-10-11.
  **Recheck trigger**: that section lists the known-safe variables, changes how allow and deny
  rules treat a leading assignment, or is renamed.
- **Pointer**: the classifier's default block list is in
  [What the classifier blocks by default](https://code.claude.com/docs/en/permission-modes#what-the-classifier-blocks-by-default).
  **As of**: 2026-10-11. **Recheck trigger**: that list stops covering stash discards and similar
  removals, `claude auto-mode defaults` shows otherwise, or the section is renamed.
