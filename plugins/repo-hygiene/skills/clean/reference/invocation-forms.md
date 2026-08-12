# clean invocation forms — accepted two-form split

`/repo-hygiene:clean` deliberately carries **two** bundled-script invocation forms. This is an
accepted residual, not a pairing defect to "fix" by converting every `context/*.md` file to
`${CLAUDE_SKILL_DIR}`.

## Paired form — `SKILL.md` + `allowed-tools`

`SKILL.md` and its `allowed-tools` frontmatter use the **paired** form from #2225:

- Body: direct, unquoted `${CLAUDE_SKILL_DIR}/scripts/<name>.sh`
- Rule: `Bash(${CLAUDE_SKILL_DIR}/scripts/<name>.sh:*)`

Per the [skills](https://code.claude.com/docs/en/skills#available-string-substitutions) docs
(changelog v2.1.69), Claude Code substitutes `${CLAUDE_SKILL_DIR}` in **two** places only: the
skill's markdown content, and Bash rules in `allowed-tools`. The five read-only grants
(`resolve-clean-action.sh`, `scan.sh`, `preflight.sh`, `git-branch-audit.sh`, `git-stash-audit.sh`)
are fully paired through this surface.

## Interpreter-led form — bundled `context/*.md`

The six routed detail files still invoke through the **interpreter-led** form:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/<name>.sh
```

Files: `context/action-router.md`, `context/clean-batch.md`, `context/git-branch-cleanup.md`,
`context/git-tree-reset.md`, `context/git-tree-reset-batch.md`, `context/preflight.md`.

They are loaded on demand when `SKILL.md` routes into a step. Whether `${CLAUDE_SKILL_DIR}`
substitution reaches those files is **unverified** — the skills page scopes substitution to "the
skill's markdown content" without saying bundled context files loaded later count. That phrasing
already leans toward the broader reading: `docs/conventions/permission-rule-hygiene/README.md`
states the same substitution scope for `${CLAUDE_SKILL_DIR}` in "the skill's markdown content"
without carving out bundled files loaded on demand, so the two repo docs are in tension until
#2237 settles it empirically. `${CLAUDE_PLUGIN_ROOT}` is documented more broadly
(plugins-reference: "Skill and agent content | Anywhere the placeholder appears"), so it is the
safe token for copy-paste examples the model may run from a context file.

**Failure mode if converted on the wrong assumption:** an unsubstituted body emits a literal
`${CLAUDE_SKILL_DIR}/scripts/x.sh`, which the Bash tool expands from an unset environment variable
(that variable is not exported into the tool's shell) to `/scripts/x.sh`. It fails safe — a prompt or
a not-found error, never a wrong action — but **silently**, which is the defect class #2225 exists
to remove.

## decide-lane verdict (#2237)

**DEFER** converting `context/*.md` to `${CLAUDE_SKILL_DIR}`. Keep the `${CLAUDE_PLUGIN_ROOT}`
form until substitution scope for bundled context files is settled empirically (see #2237). Commands
the model takes from a `context/*.md` will not match the paired `allowed-tools` rules and will
prompt or fall to the classifier — that is expected and does not weaken #2225's fix, because every
granted script is also invoked from `SKILL.md`.

`scripts/allowed-tools-pairing.test.sh` pins both halves: the paired contract on `SKILL.md`, and a
guard that `context/*.md` never adopt the direct `${CLAUDE_SKILL_DIR}/scripts/…` form.

## Related

- #2225 — paired body+rule rewrite this defers finishing
- #1824 — neighbouring open question on `${CLAUDE_SKILL_DIR}` in pre-compute blocks
- `docs/conventions/permission-rule-hygiene/README.md` — which variables substitute in `allowed-tools`
