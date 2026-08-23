---
description: "Verify visualization's effective `medium` preference — the one option whose legal set (auto | terminal | file | artifact) `userConfig` has no native enum type to hold — and report which delivery surfaces are actually reachable in this session, so a stored preference that cannot be honored here is visible rather than silent. Use when: 'set up visualization', 'configure visualization', 'is visualization configured', 'why is it not publishing an Artifact', 'why did my medium preference not take effect', or after changing the medium option. Actions: check (read-only verification, default) | apply (route a medium change; writes nothing). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply` resolves
what it found. The warrant is criterion (c), non-trivial `userConfig`: `medium` is **coupled to
state outside the manifest** — `artifact` is a correct value only when the publish surface is
actually reachable in this session, which neither the manifest nor Claude Code's native
configuration prompt can settle, so a live `check` is the only surface that can tell the reader
whether the preference they set is the preference they will get. `medium`'s only stored home is the
`pluginConfigs` this contract forbids setup to write, so this setup is check-only: `apply` verifies
and routes, writes nothing, and is idempotent by construction.

Official contract (verified 2026-07-18):
<https://code.claude.com/docs/en/plugins-reference#user-configuration>.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then the
reconfiguration guidance. Both are non-interactive — never prompt when the action is given.

## `check` (read-only)

[`${CLAUDE_PLUGIN_ROOT}/skills/visualize/SKILL.md`](../visualize/SKILL.md) § "Step 3 — Pick the
medium" and the catalog it routes to
([`${CLAUDE_PLUGIN_ROOT}/skills/visualize/context/decision-matrix.md`](../visualize/context/decision-matrix.md))
are the source of truth for selection and for the rendering-surface facts — read them first rather
than reciting this file.
Report a PASS/FAIL/INFO/WARN table with one remediation line per finding. Modify nothing, and
render nothing.

1. **Effective `medium`** — read the rendered `${user_config.medium}` value from this skill; never
   inspect or edit settings files or `pluginConfigs` directly.
   - Unexpanded token or empty: INFO — the option is unset and the zero-config default `auto`
     applies.
   - `auto`, `terminal`, `file`, or `artifact`: PASS, naming the value and what it selects.
   - Anything else: **WARN**, not FAIL. The skill reports the unrecognized value and treats it as
     `auto`, so nothing is broken — this is a typo whose intended value silently never takes
     effect, and the WARN is the only place it surfaces. `userConfig` has no native enum type, so
     the legal set is validated in-skill and the native prompt accepts whatever was typed.
2. **Reachable delivery surfaces, in this session** — INFO per tier, ascending. This is live state,
   not manifest state, and it is why the option is coupled:
   - **Inline terminal** — always reachable. Note that a ` ```mermaid ` fence is shown here as
     source, not a rendered diagram.
   - **Local HTML file** — reachable when a working directory can be written to; a self-contained
     page never leaves the machine.
   - **Published Artifact** — report whether that surface is actually available to this session
     rather than assuming it. It is heavily gated (plan, sign-in, provider, version, and context
     constraints), so absence is ordinary and documented, not a defect.
3. **Cross the two** — the finding the native prompt cannot produce. When the effective `medium` is
   `artifact` and that surface is unreachable here, INFO: every render degrades visibly to a local
   HTML file and then to the terminal, exactly as documented, so the stored preference is inert in
   this session. Say which tier will actually be used. When the effective medium is reachable,
   PASS.
4. **Nothing else to verify** — INFO: this plugin has no external prerequisites, makes no network
   calls of its own, and keeps no persistent state, so there is no tool to probe and no data
   directory to inspect. The chart-craft and artifact-design capabilities it routes to are
   presence-gated collaborators, not prerequisites; their absence changes routing, never readiness.

## `apply` (idempotent)

Run `check`, then resolve what it found. This skill has no legitimate write of its own — `medium`
lives in Claude Code's native configuration surface, which setup must not hand-edit — so `apply` is
verify-and-route, and re-running it once the effective medium is legal and reachable changes nothing
and reports "already configured":

- **Unrecognized value (WARN):** the intended preference is not in effect. Reconfigure to one of
  `auto`, `terminal`, `file`, or `artifact` through the path below — the fix is the value, never a
  change to the skill.
- **Preference inert here (INFO):** if the Artifact surface is unreachable on this machine or
  account, `auto` and `file` describe what will actually happen; `artifact` is a preference for
  sessions where publishing is available and costs nothing where it is not. State the tradeoff and
  let the reader pick — do not prompt.
- **Reconfiguring the option:** `/plugin configure visualization@<marketplace>` (interactive, any
  time). Headless: rerun the install with the new value —
  `claude plugin install visualization@<marketplace> -s <scope> --config medium=file` (repeatable
  per key). Against an already-installed plugin it prints `already installed` **and still writes the
  value** — verified on Claude Code 2.1.240 (a non-sensitive option at `user` scope: a non-default
  value written to an installed plugin, then restored). The short-circuit is about the install, not
  the config write. Re-verify before relying on it outside those conditions — a `sensitive` option,
  or `project`/`local` scope, were not covered. Do **not** uninstall to reconfigure: uninstalling
  drops this plugin's entire stored `pluginConfigs` entry, resetting every option in the README's
  Options reference table to its manifest default. `-s` defaults to `user`, so pass the scope
  `claude plugin list` reports for this plugin, and run from that project's directory for a
  `project`/`local` scope, or the write lands at a scope that does not load. This skill never writes
  user settings or `pluginConfigs`. Afterwards rerun `check` **in a fresh session** — the rendered
  `${user_config.medium}` token is injected at skill load, so a change is observable only in a new
  one — and report the observed effective medium; never claim an unobserved change.

## What this skill does NOT do

- Decide a form, pick a medium, or render anything — that is `/visualization:visualize`.
- Write Claude Code user settings, `pluginConfigs`, or the plugin cache.
- Restate the rendering-surface catalog, or teach chart craft or artifact-design fundamentals —
  those live once in the decision matrix and in the capabilities the visualize skill routes to.
