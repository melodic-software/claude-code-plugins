# Permission Rule Hygiene Convention

A marketplace-wide convention for writing Claude Code permission grants that actually take effect —
specifically, grants for the auto-mode-gated action classes (arbitrary code execution) that a skill,
command, or plugin wants to run without a prompt.

The principle: **the operative allow-rule for a guarded code-execution helper must be a narrow,
machine-independent, bare-command rule that the operator adds to user-global settings — never an
interpreter-wildcard grant, never a hardcoded machine path, and never a self-granted rule a skill or
plugin ships expecting it to work.** The three anti-patterns below each break that in a different way;
the [correct pattern](#the-correct-pattern) fixes all three at once.

Enforced by the [`audit-permission-grants`](../../../plugins/claude-config/skills/audit-permission-grants)
skill in the `claude-config` plugin, which scans skill/command/agent frontmatter `allowed-tools`
and `settings.json` / `settings.local.json` `permissions.allow` and flags each anti-pattern (checks
P1/P2/P3).

## Why this convention exists

Running this convention's own detector against this marketplace surfaced six pre-existing
interpreter/runner-led frontmatter grants (shapes like `Bash(bash <script>:*)`, `Bash(bash <dir>/*)`,
and `Bash(npx:*)`) across unrelated plugins — none of them the portable bare-name pattern, and the
broad forms among them (a globbed script target, a package runner) are exactly what auto mode drops.
When a grant is dropped the failure is silent: it parses, looks correct, and does nothing the moment
the session enters auto mode, so the action falls through to the classifier and can be denied even when
the operator intended to pre-approve it. A convention plus an enforceable check is the durable fix.

## Anti-pattern 1 — interpreter-wildcard / blanket allow rules (dropped in auto mode)

On entering [auto mode](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode),
Claude Code **drops broad allow rules that grant arbitrary code execution**. Per the official decision
order:

> On entering auto mode, broad allow rules that grant arbitrary code execution are dropped:
> Blanket `Bash(*)` or `PowerShell(*)`; Wildcarded interpreters like `Bash(python*)`; Package-manager
> run commands; `Agent` allow rules. Narrow rules like `Bash(npm test)` carry over. Dropped rules are
> restored when you leave auto mode.
> — [permission-modes](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)
> ("How the classifier evaluates actions")

The [auto-mode configuration reference](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier)
restates it and adds that `autoMode.classifyAllShell: true` suspends even the narrow shell allow rules:

> Auto mode suspends only the broad rules that grant arbitrary code execution, such as `Bash(*)` or
> wildcarded interpreters.

So a frontmatter grant such as `allowed-tools: ['Bash(python "*helper.py":*)']`, or any
`Bash(python*)` / `Bash(node*)` / `Bash(bash *)` / `Bash(*.py:*)` / `Bash(sh -c*)` / package-manager
runner (`npx`, `uvx`, `pipx run`, `pnpm dlx`, …), silently grants nothing under auto mode. The action
then depends entirely on the classifier. Empirically, a guarded merge helper granted this way was
denied even when invoked bare.

A **bare package-manager wildcard** — `Bash(npm:*)`, `Bash(npm *)`, `Bash(pnpm:*)`, `Bash(yarn:*)` —
is the same anti-pattern: it reads like a scoped grant but permits arbitrary execution (`npm exec`,
`npm run <anything>`, lifecycle scripts), so it is interpreter/runner-led rather than the bare-name
pattern and is flagged. The doc's dropped-category wording enumerates "package-manager run commands";
this bare form is broader than — not narrower than — that category, so it is treated as the same
authoring anti-pattern with the same fix. A **fixed** package-manager subcommand (`Bash(npm test)`,
`Bash(npm run build)`) carries no wildcard, carries over into auto mode, and is not flagged.

`Agent` allow rules (both bare `Agent` and scoped `Agent(...)`) are dropped the same way, and are
flagged too — but unlike a shell helper they have no bare-command-on-PATH analog to re-scope to.
Remove or re-scope the rule, or run the sub-agent action outside auto mode.

## Anti-pattern 2 — hardcoded absolute machine/user paths

Bash permission rules match the command string **literally**. Per
[permissions](https://code.claude.com/docs/en/permissions#wildcard-patterns), a Bash rule is a glob
over the literal command — there is no `~`, `$HOME`, or environment-variable expansion (the `~/` and
`//` home/absolute anchors documented under
[Read and Edit](https://code.claude.com/docs/en/permissions#read-and-edit) are gitignore-style path
anchors for the file tools, not shell-command expansion). A rule like
`Bash(/c/Users/<name>/.agents/skills/merge/x.sh:*)`:

- breaks on any other machine or username, and after the skill migrates into a plugin (the install
  path changes), and
- leaks a username into version control.

The one substitution that *is* expanded in `allowed-tools` is `${CLAUDE_PROJECT_DIR}` (Claude Code
v2.1.196+, per [skills](https://code.claude.com/docs/en/skills)) — but that anchors to the consuming
project, not to a portable command, so it still isn't the right tool for a shared code-execution
helper.

## Anti-pattern 3 — assuming a skill or plugin can self-grant

Three official constraints mean the operative allow-rule cannot be shipped by the skill or plugin:

- **Skill `allowed-tools` is skill-scoped and (per anti-pattern 1) ineffective for auto-mode-gated
  action classes.** It "grants permission for the listed tools while the skill is active … It does not
  restrict which tools are available" —
  [skills](https://code.claude.com/docs/en/skills) — but auto mode still drops the broad/interpreter
  shapes.
- **A plugin cannot ship permission rules.** A plugin's `settings.json` supports "Only the `agent` and
  `subagentStatusLine` keys" —
  [plugins-reference](https://code.claude.com/docs/en/plugins-reference) (Settings row). A
  `permissions` block placed there is inert.
- **An agent editing its own settings to self-grant is blocked.** `defaultMode: "auto"` is ignored
  from project/local settings "so a repository cannot grant itself auto mode" and `.claude/` writes are
  a protected path routed to the classifier —
  [permission-modes](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode).

So the operative rule must be added **by the operator** to user-global
`~/.claude/settings.json`.

## The correct pattern

Expose the guarded helper as a **stable bare command on the Bash tool's PATH**, then allow that bare
name narrowly:

1. **Put the helper on PATH under a stable bare name.**
   - Pre-plugin: a small PATH shim in a directory already on your PATH (e.g. `~/.local/bin`, if it is
     on your PATH) that delegates through `$HOME` to the skill's self-locating wrapper.
   - Post-migration: the plugin's `bin/` directory — "Executables added to the Bash tool's `PATH` …
     as bare commands in any Bash tool call while the plugin is enabled" —
     [plugins-reference](https://code.claude.com/docs/en/plugins-reference) (Executables row).
   - Wrappers self-locate their real directory (e.g. `readlink -f`) so they work via direct, shim, or
     symlink invocation.
2. **Allow the bare name, narrowly.** `Bash(babysit_merge.sh:*)` — a narrow rule that carries over
   into auto mode exactly like `Bash(npm test)`, is machine/username-independent, and is identical
   before and after plugin migration.
3. **State the operator-setup boundary.** The skill/plugin documents an "Operator setup" note telling
   the operator to add the bare-name rule once to `~/.claude/settings.json`, and never relies on
   interpreter-wildcard `allowed-tools` for auto-mode-gated actions.

## Known gap — step 1's plugin `bin/` is not delivered on Windows / Git Bash

The plugin `bin/` half of step 1 is documented but does not hold on this platform, so a helper whose
only permission story is bin/-on-PATH has **no** operative allow rule there. Measured on Windows 11 /
Git Bash, Claude Code **v2.1.219**, with the owning plugin installed at user scope and reported
`enabled` by `claude plugin list`:

```console
$ which source-control-babysit-merge ; echo $?
which: no source-control-babysit-merge in (...)
1
$ echo "$PATH" | tr ':' '\n' | grep -i plugins
                          # no plugin directory of any kind is on PATH
```

The absence is **harness-wide, not a packaging defect in one plugin**: a second, unrelated installed
plugin that also ships a `bin/` is equally absent from `PATH`. The files themselves are fine —
committed `100755`, present in the install cache, correct shebangs. The feature also is not
version-gated away: it predates the measured harness.

Two consequences for anyone writing a guarded helper today:

- **Invoke it by its bundled path**, the same form the sibling `scripts/` use. That is deterministic
  and works now. Resolve `${CLAUDE_PLUGIN_ROOT}` in skill or agent content — it is substituted there,
  but it is *not* exported to the Bash tool's own environment, so a raw shell expansion yields an
  empty string ([plugins-reference](https://code.claude.com/docs/en/plugins-reference), Environment
  variables).
- **Expect no allow rule to cover it.** `bash` is not one of the wrappers Claude Code strips before
  matching, so a `bash <path> …` command can only be matched by an interpreter-led rule — which is
  anti-pattern 1, dropped on entering auto mode. The call therefore reaches the classifier on every
  invocation. Do not design a helper on the assumption that the operator can pre-approve it.

Until the gap closes upstream, treat step 1's plugin-`bin/` bullet as the intended end state rather
than a capability to build on, on this platform. A `~/.local/bin` shim is **not** a substitute: a
static shim pins a version-numbered install path that changes on every plugin update, and a shim that
resolves the newest directory under the install cache can select an unvetted staging clone.

## Sources

- Auto-mode drop behavior and decision order — [permission-modes](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)
- `classifyAllShell`, narrow-rule carryover — [auto-mode-config](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier)
- Literal matching, wildcard / `:*` semantics, process-wrapper stripping — [permissions](https://code.claude.com/docs/en/permissions#permission-rule-syntax)
- `allowed-tools` scope and `${CLAUDE_PROJECT_DIR}` substitution — [skills](https://code.claude.com/docs/en/skills)
- Plugin `bin/` on PATH and the `agent`/`subagentStatusLine`-only `settings.json` — [plugins-reference](https://code.claude.com/docs/en/plugins-reference)
