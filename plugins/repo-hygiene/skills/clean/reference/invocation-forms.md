# clean invocation forms: the two-form split

`/repo-hygiene:clean` carries two bundled-script invocation forms on purpose. Converting the
`context/*.md` files to `${CLAUDE_SKILL_DIR}` is not a fix.

## Paired form: `SKILL.md` + `allowed-tools`

`SKILL.md` and its `allowed-tools` frontmatter use the paired form:

- Body: direct, unquoted `${CLAUDE_SKILL_DIR}/scripts/<name>.sh`
- Rule: `Bash(${CLAUDE_SKILL_DIR}/scripts/<name>.sh:*)`

Claude Code substitutes `${CLAUDE_SKILL_DIR}` in two places, the skill's markdown content and Bash
rules in `allowed-tools`
([skills docs](https://code.claude.com/docs/en/skills#available-string-substitutions)). The five
read-only grants (`resolve-clean-action.sh`, `scan.sh`, `preflight.sh`, `git-branch-audit.sh`,
`git-stash-audit.sh`) are fully paired through this surface.

## Interpreter-led form: bundled `context/*.md`

The six routed detail files invoke through the interpreter-led form:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/<name>.sh
```

Files: `context/action-router.md`, `context/clean-batch.md`, `context/git-branch-cleanup.md`,
`context/git-tree-reset.md`, `context/git-tree-reset-batch.md`, `context/preflight.md`.

They load on demand when `SKILL.md` routes into a step. Whether `${CLAUDE_SKILL_DIR}` substitution
reaches them is unverified: the skills page scopes substitution to "the skill's markdown content"
without saying whether bundled context files loaded later count, and
`docs/conventions/permission-rule-hygiene/README.md` states the same scope without carving them
out. `${CLAUDE_PLUGIN_ROOT}` is documented more broadly (plugins reference: "Skill and agent
content | Anywhere the placeholder appears"), so it is the safe token for a copy-paste example the
model may run from a context file.

Converting a context file on the other assumption fails silently. An unsubstituted body emits a
literal `${CLAUDE_SKILL_DIR}/scripts/x.sh`, which the Bash tool expands from an unset environment
variable (that variable is not exported into the tool's shell) to `/scripts/x.sh`. It fails safe, a
prompt or a not-found error rather than a wrong action, but it gives no signal.

## The rule

Keep `context/*.md` on the `${CLAUDE_PLUGIN_ROOT}` form until substitution scope for bundled
context files is verified. A command the model takes from a `context/*.md` does not match the
paired `allowed-tools` rules and will prompt or fall to the classifier. That is expected, because
every granted script is also invoked from `SKILL.md`.

`scripts/allowed-tools-pairing.test.sh` pins both halves: the paired contract on `SKILL.md`, and a
guard that `context/*.md` never adopt the direct `${CLAUDE_SKILL_DIR}/scripts/…` form.
