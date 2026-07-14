# Permission Hygiene Criteria

Version: 1.0.0
Last updated: 2026-07-14

This file defines the checks the `permission-hygiene` audit runs. The **principle, the three
anti-patterns, and the prescribed correct pattern — with official-doc citations — live in the
marketplace convention** and are not restated here:
[docs/conventions/permission-rule-hygiene](../../../../../docs/conventions/permission-rule-hygiene/README.md).
This file is the mechanical check layer: what the detector flags, at what severity, and how to read a
finding.

The deterministic spine is
`bash "${CLAUDE_PLUGIN_ROOT}/skills/permission-hygiene/scripts/permission-rule-check.sh"` — it scans
skill/command/agent frontmatter `allowed-tools` and the `permissions.allow` arrays of
`.claude/settings.json` and `.claude/settings.local.json`, plus any plugin `settings.json`, and emits
one finding per fragile grant. It is advisory (always exits 0); `--count` prints the finding count.
`settings.local.json` is parsed for its `permissions.allow` array only — never read or echoed wholesale
(it may hold tokens).

Findings are printed as `<severity> [<check>] <source>: <detail>`.

---

## P1: Interpreter-wildcard / blanket allow rule [warning]

**What**: An `allowed-tools` or `permissions.allow` entry matching an action class Claude Code drops on
entering auto mode — blanket `Bash(*)` / `PowerShell(*)` / bare `Bash` / bare `PowerShell`, a
wildcarded interpreter (`Bash(python*)`, `Bash(node *)`, `Bash(bash <path>*)`, `Bash(sh -c*)`), a
package-manager runner (`Bash(npx *)`, `Bash(uvx *)`, `Bash(pipx run *)`, `Bash(pnpm dlx *)`, …), or a
script-glob command (`Bash(*.py:*)`).

**How to check**: run the detector. Each P1 alternative requires a wildcard, so an exact narrow rule
(`Bash(npm test)`, `Bash(cargo build)`, `Bash(babysit_merge.sh:*)`) is not flagged — matching the
official "narrow rules carry over" behavior.

**Why**: every P1 shape is interpreter/runner-led rather than the portable bare-name pattern, and the
**broad forms** — blanket rules, package-manager runners, and interpreters with a wildcarded or
globbed script target (e.g. `Bash(python "*helper.py":*)`) — are the ones auto mode drops, after which
the grant does nothing and the action falls to the classifier. A grant that invokes one fixed script
via an interpreter (`Bash(bash <fixed-path>:*)`) is flagged as the same authoring anti-pattern even
where the doc's dropped-category wording does not clearly reach it; the fix (a bare PATH command) is
the same. See convention anti-pattern 1.

**Recommend**: expose the helper as a bare command on PATH and allow the bare name narrowly.

## P2: Hardcoded absolute machine/user path [error]

**What**: An entry containing a concrete user-home absolute path — `/c/Users/<name>/…` (POSIX-normalized
Windows), `/home/<name>/…`, `/Users/<name>/…`, or `C:\Users\<name>\…`.

**How to check**: run the detector. `${CLAUDE_PROJECT_DIR}/…`, `~/…`, and `//…` forms are not flagged
(they expand or are portable anchors); only concrete usernames match.

**Why**: Bash rules match literally with no `~`/`$HOME`/env expansion, so the rule breaks on other
machines/usernames and leaks a username into version control. See convention anti-pattern 2.

**Recommend**: replace with a machine-independent bare-name rule.

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

The sibling `settings-audit` skill owns config-**file correctness**: baseline deny/ask presence,
deprecated `:*` syntax, overly broad patterns like `Bash(git *)`, and live plugin drift. This skill
owns a different question — grant **portability and auto-mode durability**, and who adds the operative
rule. When a request is about baseline security patterns, deprecated syntax, or drift, route it to
`settings-audit` rather than answering here.

## Output format

```text
## Permission Hygiene Report — {date}

### Summary
- Grants scanned: frontmatter allowed-tools + settings.json/settings.local.json permissions.allow
- error: X findings (P2)
- warning: X findings (P1, P3)

### Findings
| # | Check | Severity | Source | Finding | Recommended |
|---|-------|----------|--------|---------|-------------|
```
