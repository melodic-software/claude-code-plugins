# Auditing a hook

PreToolUse / PostToolUse / lifecycle hook scripts.

## Read first

- `hooks/hooks.json`: which events, which `matcher` (tool-name regex), which scripts, timeouts.
- The script itself + any shared utility script it sources.
- The plugin's `userConfig` for kill switches / allow-lists that gate the hook.

## Check

- **Matcher coverage**: does the matcher cover every tool that can perform the gated action?
  (Bash-only matchers miss a PowerShell/other-shell tool → silent bypass.)
- **Exit-code semantics**. Does the script use each exit code as its event defines it, and fail
  closed where blocking matters? Grade against the live reference, never memory.
  - **Pointer**: when grading a hook's exit codes, fetch
    [Exit code 2 behavior per event](https://code.claude.com/docs/en/hooks#exit-code-2-behavior-per-event)
    live.
  - **As of**: 2026-10-11
  - **Recheck trigger**: that section changes what an exit code does for any event, or a release
    note names hook exit codes.
- **Fail-open vs fail-closed** on missing deps (jq), empty/timed-out stdin, parse errors.
- **Enablement/scope probe**: if it self-disables based on plugin enablement or settings, does it
  read the *merged effective* scopes (user-global + project + local), not just one?
- **Content vs mechanic**: does it inspect the payload it claims to (subject text, args), or only
  a surface marker?
- **Escape hatch**: documented bypass for when the hook is buggy?
- **Cross-platform**: remediation messages runnable on the user's shell; path/quoting assumptions.
- **Observability**: degraded state surfaced, not silently skipped.

## A mod (hooks module)

A hook config that names `"modules"` loads a hooks module: in-process code with the user's
permissions, not a shell script. Read the module and run `claude plugin validate --json <plugin>`.

- **Read meanings from the declarations.** Step 1 records the declaration-file path the built-in
  `plugin-authoring` skill names. Grep that path for each event and `$` call the
  module uses and read the declaration it lands on. It is written for the running build, so it wins
  where the pages cited below disagree. As of 2026-10-03 the path ends in `types/claude-code.d.ts` (recheck when the
  `plugin-authoring` skill names a different file);
  a later skill that names a different file is still the file to read. With no path in the packet, or a path that no longer exists
  (the folder belongs to one process, so a resumed audit can carry a dead one), ground in the pages
  and record that the declarations were not read.

- **Read the declared surface.** The `hooks` content's `notes` hold one line per kind:
  `./register.js hooks: tool.call, attribution.text`,
  `./register.js calls: $.env.get, $.http.fetch`, `env reads:`, `env writes:`, and `state reads:`/`state writes:` for a module using `$.state`. The
  `errors` and `warnings` arrays stay empty for a clean mod, so reading only those misses the
  surface entirely.
- **Audit `calls:` as the trust boundary.** Each call must be one the component's stated purpose
  needs. Flag any capability with no use the plugin documents, above all: `$.fs.write`,
  `$.process.run`/`$.process.spawn`, `$.http.fetch`, `$.env.set`, `$.mcp.call`,
  `$.model.complete`, `$.prompt.submit`, `$.session.send`. In `hooks:`, `tool.call`,
  `prompt.submit` and `tool.check` need the same justification. What each call and event can do is
  read at the pointer below, never from this list.
- **Compare code to declaration.** A call the source makes that `calls:` omits means the static
  analysis could not read it; what Claude Code does with such a module at load is read at the
  pointer below.

The `notes` placement above was observed by running `claude plugin validate --json` on a
throwaway mod with Claude Code 2.1.287 on 2026-10-01.

- **Pointer**: when grading a mod's calls and events, or the validator's output shape, fetch
  [Review what a mod can do](https://code.claude.com/docs/en/plugins/mods/admin#review-what-a-mod-can-do)
  and [Check what Claude Code reads from your mod](https://code.claude.com/docs/en/plugins/mods/create#check-what-claude-code-reads-from-your-mod)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: either section's call table or sample output changes, or a release note
  changes `plugin validate` output or mod loading.

**Claim:** loading `plugin-authoring` writes the declarations into that skill's own folder for the
current process, and a subagent without the Skill tool cannot load it. **Basis:** the skill's
"WHERE THE TYPES ARE" section, read by loading it in Claude Code 2.1.288; `auditor.md`'s `tools:`
line. **As of:** 2026-10-03. **Recheck:** that section names a different location, or the auditor
gains the Skill tool.

## Categories

- **Errors:** a wrong exit code, a fail-open that the hook claims is fail-closed, a matcher that misses the tool that performs the gated action.
- **Improvements:** behavior the hooks reference implies for this event and the script does not implement.
- **Quality of life:** a block message the operator cannot act on, or a path spelled for the wrong shell.
- **Standards:** the `windows-path-emit` and `untrusted-content` probes, plus the `hook-budget` convention, which the collector leaves to this lens because cost is measured.
- **Emitted findings:** when the hook reports something about the user's code or state (a lint result, a policy verdict), sample those reports and grade each.

## Reproduce

Trigger the tool call the hook matches (and one it *should* match but might not), through each
relevant tool, and confirm block/allow behavior empirically.
