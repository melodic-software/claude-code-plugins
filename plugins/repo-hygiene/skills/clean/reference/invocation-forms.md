# clean invocation forms: the two-form split

`/repo-hygiene:clean` carries two bundled-script invocation forms on purpose. Converting the
`context/*.md` files to a `${…}` token is not a fix.

## Paired form: `SKILL.md` + `allowed-tools`

`SKILL.md` and its `allowed-tools` frontmatter use the paired form:

- Body: direct, unquoted `${CLAUDE_SKILL_DIR}/scripts/<name>.sh`
- Rule: `Bash(${CLAUDE_SKILL_DIR}/scripts/<name>.sh:*)`

Claude Code substitutes `${CLAUDE_SKILL_DIR}` in two places, the skill's markdown content and Bash
rules in `allowed-tools`
([skills docs](https://code.claude.com/docs/en/skills#available-string-substitutions)), verified
2026-09-06 against Claude Code 2.1.263 and that page as fetched that day. Recheck when that page
names a third place, drops the two-place wording, or when a release note names string substitution
in skills. The five
grants for scripts that delete nothing (`resolve-clean-action.sh`, `scan.sh`, `preflight.sh`, `git-branch-audit.sh`,
`git-stash-audit.sh`) are fully paired through this surface.

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
and the plugin-root variable to a path that resolves against nothing. They write the skill directory as
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

- Permission rules run deny, then ask, then allow, and the first match decides. A PreToolUse hook
  cannot override a matching deny or ask rule.
- In auto mode the classifier reviews the command as well. It blocks `git stash drop` and similar
  discards by default, and it denied hand-rolled bulk removals and batched worktree scripts on the
  audited machine ([why](../context/clean-batch.md#why-this-exists)).
- An allow rule such as `Bash(<script>:*)` does not match a command that starts with
  `CLEAN_GUARD_ACK=1` and a space. The prefix assigns a variable outside the built-in known-safe set, and allow
  rules do not match past such an assignment. Deny and ask rules do match past it. The skill's own
  `allowed-tools` grants cover only scripts that delete nothing, which never take the prefix.

When the confirmed apply is denied or prompts, tell the user which layer stopped it and let them
decide. Never work around it with a hand-rolled `rm` or another script.

| Claim | Basis | As of | Recheck |
|---|---|---|---|
| Rules evaluate deny, then ask, then allow; a hook decision does not bypass a matching deny or ask rule. | [permissions](https://code.claude.com/docs/en/permissions) ("Manage permissions", "Extend permissions with hooks"). | 2026-09-29 | The page changes the evaluation order or the hook wording. |
| An allow rule does not match past a leading assignment of a variable outside the known-safe set; a deny or ask rule does. The page does not list the set, so `CLEAN_GUARD_ACK` is not documented as known-safe. | [permissions](https://code.claude.com/docs/en/permissions) ("Wrappers"). | 2026-09-29 | The page lists the known-safe variables or changes the assignment wording. |
| Auto mode reviews shell commands with a classifier and blocks `git stash drop` and similar discards by default. | [permission modes](https://code.claude.com/docs/en/permission-modes) ("What the classifier blocks by default"). | 2026-09-29 | The blocked-by-default list drops those entries, or `claude auto-mode defaults` shows otherwise. |
