---
description: "Verify and configure the bugs plugin for this repository. check inspects both surfaces read-only — the rendered output_dir userConfig value, and the tracked .claude/bugs.md lane config across its cascade layers; apply writes or updates that tracked file and nothing else. Use when: 'set up bugs', 'configure bugs', 'bugs setup', 'where do bug reports land', you want --file reports committed alongside code, or '/bugs:scan' needs project lanes and a filing posture. Actions: check (read-only, default) | apply (creates or updates the tracked lane config; output_dir still routes through Claude Code's own configuration prompt)."
argument-hint: "check|apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Confirm where `/bugs:write --file` writes reports, and manage the tracked project config
`/bugs:scan` reads for its lanes and filing posture.

## Two surfaces, two owners

| Surface | Holds | Written by |
|---|---|---|
| `output_dir` — native `userConfig` | one operator's personal `--file` destination on one machine | Claude Code's own plugin configuration prompt — never this skill |
| `.claude/bugs.md` — tracked, cascade-layered | team policy: `/bugs:scan` lanes and filing posture | `apply` here, team layer only |

This is the narrow-write setup shape: `apply` is bounded to the one writable artifact this plugin
owns, and the unwritable surface beside it stays check-only. `output_dir` is a personal value that
Claude Code prompts for when the plugin is enabled, stores in user settings, and ignores in
`pluginConfigs` entries under project and local settings on current releases (≥ 2.1.207) — so an
`apply` could only write the `pluginConfigs` the uniform setup contract forbids, and reconfiguration
routes through the native flow instead.

Official contract: <https://code.claude.com/docs/en/plugins-reference#user-configuration>.

Keys, layers, merge semantics, the `output_dir` partition rule, and the file format live in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md) — their single home. Read it
before checking or writing; never restate its keys here, and never let this skill and that reference
disagree.

Both actions are non-interactive when the invocation and the repo make the values unambiguous:
report and recommend, and ask only where a lane genuinely needs the user. No argument runs `check`.

## `check` (read-only, the default)

Modify nothing. Report both surfaces, then one remediation line per gap.

### A. `output_dir` (native `userConfig`)

1. Read the rendered `${user_config.output_dir}` value from this skill. Do not inspect or edit
   `settings.json`, `settings.local.json`, managed settings, or `pluginConfigs` directly.
2. Explain the effective behavior:
   - empty or unexpanded value: `--file` uses
     `${CLAUDE_PLUGIN_DATA}/bug-reports/<project-slug>/`;
   - configured value: `--file` uses that directory.
3. State the tradeoff instead of asking: machine-private (the default under
   `${CLAUDE_PLUGIN_DATA}`) versus a repository path committed alongside code. For the
   repository option, inspect the consumer's `CLAUDE.md`, `AGENTS.md`, and existing report or
   artifact directories and recommend one portable location. Never recommend a machine-absolute
   team path.
4. If the recommended value differs from the effective one, direct the user to Claude Code's
   plugin configuration prompt for `bugs` (interactive `/plugin configure bugs@<marketplace>` any
   time; headless, rerun `claude plugin install bugs@<marketplace> -s <scope> --config
   output_dir=<path>` — against an already-installed plugin it prints `already installed` and
   still writes the value, verified on Claude Code 2.1.240 for a non-sensitive option at `user`
   scope. Never uninstall to reconfigure: that drops the whole stored `pluginConfigs` entry and
   resets every option to its manifest default). Claude Code owns persistence. Do not hand-edit
   any `pluginConfigs` key.
5. Tell the user to rerun `check` after reconfiguration — in a fresh session, since the rendered
   value is injected at load — then verify and report the effective destination.

### B. `.claude/bugs.md` (tracked lane config)

Anchor at the repo root — `${CLAUDE_PROJECT_DIR}` when set, otherwise `git rev-parse --show-toplevel`
— never at the CWD, then report **each layer separately** and the effective merged result:

1. **Per-layer presence.** Name every layer of the surface (the reference's layer table is
   authoritative) and say for each: absent, present-and-parsed, or malformed. A malformed layer
   degrades soft — surface the error, name the layer, and resolve as if it were absent.
2. **Effective config and provenance.** Report the merged `lanes` and `filing_posture` and which
   layer supplied each value, honoring the reference's merge semantics — including an explicit
   empty-list opt-out, which is reported as an opt-out, not as a broken layer. All layers absent is
   a valid, fully working state: INFO, never FAIL — `/bugs:scan` falls through to its bundled
   generic default lanes.
3. **Per-layer version-control verdict.** A present team file must be tracked, which takes **two**
   probes — not-ignored and actually-tracked. Run `git check-ignore -v .claude/bugs.md`; a
   non-empty result is FAIL, naming the matching pattern — teammates would never receive it. Then run
   `git ls-files --error-unmatch .claude/bugs.md`; a non-zero exit on a present file is also
   FAIL — "present but untracked — commit it so teammates receive it". The ignore probe alone cannot
   see this: an untracked, unignored file returns the same empty output as a healthy tracked one, so
   `check` would bless a config nobody else ever receives. The `.local.md` overlay must be
   gitignored; staged or unignored is FAIL. The user-global layer sits outside the worktree, so no git
   verdict applies to it — say so rather than running a command whose answer is meaningless.
4. **Unreachable layers.** When a layer cannot be read (the user-global one often is not), WARN that
   it was not considered rather than presenting the rest as the whole effective config.
5. **Unknown keys.** Report them as inert, naming their layer — including `output_dir`, which is not
   a recognized key here per the reference's partition rule.

## `apply` (idempotent, bounded to `.claude/bugs.md`)

Run `check` first, then converge the **team** file — the only artifact this action writes. Never
touch `settings.json`, `settings.local.json`, managed settings, `pluginConfigs`, `userConfig`, the
user-global layer, the `.local.md` overlay, or the consumer's `.gitignore`. An `output_dir` change
requested here is routed to the native flow in `check` step A4, never written.

1. **Read the effective config first, across every layer**, and present it. Where a user-global or
   overlay layer changes the team file's effect — adding lanes, replacing one by name, opting out
   with an empty list, or supplying `filing_posture` nearest-wins — say so explicitly: a team-scope
   edit alone will not account for it, and re-adding a lane an overlay opts out of will not restore
   it on this machine. Prompt the user to also update that layer; do not edit it for them.
2. **Draft lanes from the repository.** Before asking anything, infer candidates from what exists —
   entrypoint and API directories, the highest-churn source areas in `git log`, and any subsystem
   the repo's own docs treat as critical. Propose kebab-case lane names with globs relative to the
   repo root. Degrade to the bundled generic default lanes as the proposal when history or layout
   gives nothing to infer from.
3. **Confirm, one decision at a time.** Present each drafted lane with a recommendation; let the
   user accept, edit, or drop it. Then settle `filing_posture`, stating what each value permits per
   the reference — and that neither value ever lets a bare invocation file.
4. **Write conservatively.** Scaffold the file in the reference's documented format when absent; for
   an existing file, make a targeted update — fill absent keys at their documented defaults,
   preserve prose and keys you do not recognize, and *report* rather than silently rewrite anything
   you cannot reconcile. Never overwrite blind, and never rewrite a file you did not first read.
5. **Verify after writing.** Re-run the `check` B probes against the file on disk: it parses, every
   lane declares `name` and `globs`, the globs match real paths (a lane matching nothing is reported
   as skipped), and `git check-ignore -v .claude/bugs.md` confirms it is not ignored. A file
   just scaffolded here is legitimately untracked until it is staged, so
   `git ls-files --error-unmatch` will not match yet — that is not a FAIL at this point; state the
   commit obligation instead (step 7). Report the values you observed, never an unobserved change.
6. **Recommend the overlay line, do not write it.** Personal deviations belong in
   `.claude/bugs.local.md`; recommend the consumer add the recursive `.gitignore` line the
   reference names if it is not already covered. Their ignore file is their artifact.
7. **Remind them to stage it.** The team file only reaches teammates once committed.

Re-running `apply` when everything already matches changes nothing and reports "already configured".

## Output

Report, for each surface: the effective state and the layer that supplied it, the recommended state,
and what changed — the tracked file's path and the keys written, plus whether the user must still
change the Claude-owned `output_dir` through Claude Code's own flow. Do not claim a configuration
change until it is observed: for the tracked file, by re-reading it; for `output_dir`, by a rerun in
a fresh session.

## Boundaries

- Do not produce or file a bug report; invoke `/bugs:write` via the Skill tool.
- Do not run a hunt; that is `/bugs:scan`. This skill only verifies and writes its config.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform
  setup contract (`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" in the
  marketplace repository).
- Do not delete the tracked config: `apply` converges to the configured state and never removes.
- Do not invent an organization, repository, marketplace, or environment-variable prefix.
