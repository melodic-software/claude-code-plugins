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

## Known gap — step 1's plugin `bin/` delivery is unreliable, not absent

The plugin `bin/` half of step 1 is documented, and it *does* get delivered — but only in some
sessions, so a helper whose only permission story is bin/-on-PATH has no allow rule it can **depend**
on. Delivery rides the per-session shell snapshot's final `export PATH=` line; when that line does
not land, every enabled plugin's `bin/` goes with it, and a bare name that resolved last session is
gone this one. A local snapshot survey found the line present-with-plugin-bins in some sessions and
missing in others on the same machine, including sessions carrying the surveyed plugin's own `bin/`
(full corpus and per-day breakdown on
[#843](https://github.com/melodic-software/claude-code-plugins/issues/843); upstream mechanism and
root cause in [anthropics/claude-code#68066](https://github.com/anthropics/claude-code/issues/68066),
a macOS/zsh report whose own log shows healthy and degraded sessions minutes apart). Behavior on
macOS and Linux is unverified at scale — probe there rather than reading this as platform-specific.

**Per-session absence is what makes the bare name unusable — not permanent non-delivery.** An earlier
revision of this section read the gap as categorical ("no plugin directory of any kind is on
`PATH`"); that came from sampling only degraded sessions. The operational conclusion is unchanged and
if anything firmer: an intermittent capability cannot carry a permission story. A degraded session
measured on Windows 11 / Git Bash, Claude Code **v2.1.219**, with the owning plugin installed at user
scope and reported `enabled` by `claude plugin list`, looks like this:

```console
$ which source-control-babysit-merge ; echo $?
which: no source-control-babysit-merge in (...)
1
$ echo "$PATH" | tr ':' '\n' | grep -i plugins
                          # no plugin directory of any kind is on PATH
```

When it degrades, it degrades **harness-wide, not as a packaging defect in one plugin**: a second,
unrelated installed plugin that also ships a `bin/` is equally absent from `PATH` in the same
session. The files themselves are fine — committed `100755`, present in the install cache, correct
shebangs. The feature also is not version-gated away: it predates the measured harness.

Two consequences for anyone writing a guarded helper today:

- **Invoke it by its bundled path**, the same form the sibling `scripts/` use. That is deterministic
  and works now. Resolve `${CLAUDE_PLUGIN_ROOT}` in skill or agent content — it is substituted there,
  but it is *not* exported to the Bash tool's own environment, so a raw shell expansion yields an
  empty string ([plugins-reference](https://code.claude.com/docs/en/plugins-reference), Environment
  variables).
- **Do not assume the operator can pre-approve the helper.** `bash` is not one of the wrappers Claude
  Code strips before matching, so a rule for a `bash <path> …` command has to name `bash` — making it
  interpreter-led, i.e. anti-pattern 1. The documented drop categories clearly reach the
  wildcarded-target form (`Bash(bash <path>*)`); whether they reach a fixed-path form
  (`Bash(bash <fixed-path>:*)`) is not stated, so that shape is an anti-pattern on convention grounds
  rather than a confirmed drop. What happens to an uncovered call is then the **permission mode's**
  decision, not the allow rule's: a prompting mode issues a per-call prompt, while
  [auto mode](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)
  routes it to the classifier, which may approve or deny without prompting. Design for both — never
  document a prompt the operator will wait for in a session that will never issue one.

Until the gap closes upstream, treat step 1's plugin-`bin/` bullet as the intended end state rather
than a capability to build on, on this platform. Two substitutes look attractive and are not:

- A **`~/.local/bin` shim**: a static shim pins a version-numbered install path that changes on every
  plugin update.
- **`env.PATH` in user settings**, which does reach the Bash tool's shell (`env` is applied "to
  subprocesses Claude Code spawns", [settings](https://code.claude.com/docs/en/settings)): it carries
  the same version-pinned-path rot, and overriding `PATH` wholesale in settings is its own hazard.

One candidate is untested rather than rejected. Bash rules accept a wildcard in any position,
including leading, so a rule anchored on the wrapper's own name rather than on the interpreter could
reach the bundled-path invocation without naming one. Two things have to be established before
building on it.

- **It has to match the invocation as actually written.** The documented bundled-path form quotes the
  path, so the character following the wrapper name is a closing quote, not a space — a candidate
  shaped `Bash(*<wrapper-name> *)` does not match it, and fails before the auto-mode question is even
  reached. Derive the candidate from the exact command string operators are told to run.
- **Whether a leading-wildcard rule survives auto mode is unverified.** The documented drop list
  enumerates blanket rules, wildcarded interpreters, package-manager runners, and `Agent` rules, and
  says nothing about a leading wildcard in the command position.

Weigh too that a rule anchored on a bare wrapper name matches that name at *any* path, including an
unvetted copy.

## Sources

- Auto-mode drop behavior and decision order — [permission-modes](https://code.claude.com/docs/en/permission-modes#eliminate-prompts-with-auto-mode)
- `classifyAllShell`, narrow-rule carryover — [auto-mode-config](https://code.claude.com/docs/en/auto-mode-config#route-all-shell-commands-through-the-classifier)
- Literal matching, wildcard / `:*` semantics, process-wrapper stripping — [permissions](https://code.claude.com/docs/en/permissions#permission-rule-syntax)
- `allowed-tools` scope and `${CLAUDE_PROJECT_DIR}` substitution — [skills](https://code.claude.com/docs/en/skills)
- Plugin `bin/` on PATH and the `agent`/`subagentStatusLine`-only `settings.json` — [plugins-reference](https://code.claude.com/docs/en/plugins-reference)
