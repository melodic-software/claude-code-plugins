# Permission Hygiene Criteria

Version: 1.0.0
Last updated: 2026-07-14

This file defines the checks the `audit-permission-grants` audit runs. The **principle, the three
anti-patterns, and the prescribed correct pattern — with official-doc citations — live in the
marketplace's permission-rule-hygiene convention** and are not restated here, published at
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/permission-rule-hygiene/README.md>.
This file is the mechanical check layer: what the detector flags, at what severity, and how to read a
finding. Each check's **Recommend** line below carries the fix in the form the report needs, so a run
never depends on fetching the convention.

The deterministic spine is
`bash "${CLAUDE_PLUGIN_ROOT}/skills/audit-permission-grants/scripts/permission-rule-check.sh"` — it scans
skill/command/agent frontmatter `allowed-tools` and the `permissions.allow` arrays of
`.claude/settings.json`, `.claude/settings.local.json`, and the user-global settings file, plus any
plugin `settings.json`, and emits one finding per fragile grant. The user-global file resolves as
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json` — that scope is where Claude Code's own "Always
allow" path writes, so it accumulates exactly the broad rules auto mode drops, and a project-only
scan could not see any of them. A user-global finding names the resolved absolute path, because
reporting `~/.claude/settings.json` would name the wrong file whenever `CLAUDE_CONFIG_DIR` has moved
the config root. Frontmatter files under a `vendor/` path segment are skipped: they are
vendored upstream references, not loadable skills/agents/commands, so their `allowed-tools` never take
effect and a finding on them would be a false positive. Findings are advisory and never fail the run,
so a completed scan exits 0 in either mode; `--count` prints the finding count. **An environment gap
exits 2 instead of reporting a clean bill** — a missing `jq`, or a scan root that resolves to neither a
git toplevel nor `$CLAUDE_PROJECT_DIR`. There is no fallback to the current directory, because outside
a repository that is usually the user profile and scanning it would walk the whole home tree and still
exit 0.
`settings.local.json` is parsed for its `permissions.allow` array only — never read or echoed wholesale
(it may hold tokens).

Findings are printed as `<severity> [<check>] <source>: <detail>`.

---

## P1: Interpreter-wildcard / blanket allow rule [warning]

**What**: An `allowed-tools` or `permissions.allow` entry matching an action class Claude Code drops on
entering auto mode — blanket `Bash(*)` / `PowerShell(*)` / bare `Bash` / bare `PowerShell`, a
wildcarded interpreter (`Bash(python*)`, `Bash(node *)`, `Bash(bash <path>*)`, `Bash(sh -c*)`), a
package-manager grant — a runner subcommand (`Bash(npx *)`, `Bash(uvx *)`, `Bash(pipx run *)`,
`Bash(pnpm dlx *)`, …) or a bare package-manager wildcard (`Bash(npm:*)`, `Bash(npm *)`,
`Bash(pnpm:*)`, `Bash(yarn:*)`), which grants arbitrary execution via `npm exec` / lifecycle scripts —
a script-glob command (`Bash(*.py:*)`), or an `Agent` allow rule (bare `Agent` or scoped `Agent(...)` —
both dropped categorically, with no narrow carry-over form).

**How to check**: run the detector. Each P1 alternative requires a wildcard, so an exact narrow rule
(`Bash(npm test)`, `Bash(npm run build)`, `Bash(cargo build)`, `Bash(babysit_merge.sh:*)`) is not
flagged — matching the official "narrow rules carry over" behavior.

**Why**: every P1 shape is interpreter/runner-led rather than the portable bare-name pattern, and the
**broad forms** — blanket rules, package-manager runners, and interpreters with a wildcarded or
globbed script target (e.g. `Bash(python "*helper.py":*)`) — are the ones auto mode drops, after which
the grant does nothing and the action falls to the classifier. A grant that invokes one fixed script
via an interpreter (`Bash(bash <fixed-path>:*)`) is flagged as the same authoring anti-pattern even
where the doc's dropped-category wording does not clearly reach it; the fix (a bare PATH command) is
the same. See convention anti-pattern 1.

**Recommend**: expose the helper as a bare command on PATH and allow the bare name narrowly. An
`Agent` rule has no bare-PATH analog — remove or re-scope it, or run outside auto mode.

## P2: Hardcoded absolute machine/user path [error]

**What**: An entry containing a concrete user-home absolute path — `/c/Users/<name>/…` (POSIX-normalized
Windows), `/home/<name>/…`, `/Users/<name>/…`, or `C:\Users\<name>\…`.

**How to check**: run the detector. `${CLAUDE_PROJECT_DIR}/…`, `~/…`, and `//…` forms are not flagged
(they expand or are portable anchors); only concrete usernames match.

**Why**: the rule names a concrete user home, so it breaks on any other machine or username — and after
a skill migrates into a plugin, since the install path changes — and it leaks a username into version
control. That portability break is the whole of the finding, and it holds for every rule class this
check fires on.

**Do not state it as "no expansion".** No such rule is documented on the permissions page, and the
blanket form is false for the file tools. Match the mechanism to the rule class:

| Rule class | What actually happens |
| --- | --- |
| `Bash(...)` | A glob over the literal command string ([permissions](https://code.claude.com/docs/en/permissions#bash)) — with the two documented exceptions below. |
| `Read(...)` / `Edit(...)` | gitignore pattern syntax, which **does** resolve anchors: `~/path` from the home directory, `//path` from the filesystem root, `/path` from the settings source ([permissions](https://code.claude.com/docs/en/permissions#read-and-edit)). The page's own example: `Read(~/Documents/*.pdf)` matches `<home>/Documents/*.pdf`. |

The two exceptions on Bash rules:

1. **Token substitution in `allowed-tools`.** Claude Code substitutes `${CLAUDE_SKILL_DIR}` and
   `${CLAUDE_PROJECT_DIR}` in both a skill's markdown content and Bash rules in `allowed-tools`
   ([skills](https://code.claude.com/docs/en/skills#available-string-substitutions)) — the documented
   way to run a bundled script without a prompt, e.g.
   `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)`. Two limits the convention records:
   `${CLAUDE_PROJECT_DIR}` substitution requires Claude Code **v2.1.196 or later** (below that floor the
   rule stays a literal string and never matches), and `${CLAUDE_PLUGIN_ROOT}` is **not** substituted at
   all, so a rule written with it is inert.
2. **Leading env-assignment stripping**, and it is scoped: an assignment of certain known-safe variables
   is stripped, so `Bash(npm test *)` matches `NODE_ENV=test npm test`. An **allow** rule will not match
   past an assignment of any other variable; a **deny** or **ask** rule matches past any leading
   assignment ([permissions](https://code.claude.com/docs/en/permissions#process-wrappers)).

Full doctrine, and the source this row syncs from: the
[permission-rule-hygiene convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/permission-rule-hygiene/README.md)
anti-pattern 2.

**Recommend**: replace with a portable form — `${CLAUDE_SKILL_DIR}` for a skill's own bundled script, a
bare-name command on PATH, or for `Read`/`Edit` rules the `~/` home anchor.

## P3: Plugin self-granted permissions [warning]

**What**: A plugin `settings.json` (a `settings.json` beside a `.claude-plugin/plugin.json`) that
declares a `permissions` block.

**How to check**: run the detector; it reports the offending plugin `settings.json`.

**Why**: a plugin `settings.json` supports only the `agent` and `subagentStatusLine` keys, so a
self-granted permission rule is inert; the operative rule must be added by the operator to
`~/.claude/settings.json`. See convention anti-pattern 3.

**Recommend**: remove the inert block; document an operator-setup note for the bare-name rule instead.

---

## Related but out of scope (route elsewhere)

The sibling `audit` skill owns config-**file correctness**: baseline deny/ask presence,
overly broad patterns like `Bash(git *)`, and live plugin drift. This skill
owns a different question — grant **portability and auto-mode durability**, and who adds the operative
rule. When a request is about baseline security patterns, deprecated syntax, or drift, route it to
`audit` rather than answering here.

## Output format

```text
## Permission Hygiene Report — {date}

### Summary
- Grants scanned: frontmatter allowed-tools + project, local, and user-global permissions.allow
- error: X findings (P2)
- warning: X findings (P1, P3)

### Findings
| # | Check | Severity | Source | Finding | Recommended |
|---|-------|----------|--------|---------|-------------|
```
