---
description: "Plugin profiles: named sets of installed plugins switched on for a folder, for every new folder, or for one session. Use when choosing which plugins load, applying, checking or clearing a profile, resetting every profile on the machine, asking which profile is in force, or setting up profiles from the installed plugins and usage history."
argument-hint: "[apply <name>|launch [<name>]|status|clear|reset|check|setup]"
disable-model-invocation: false
metadata:
  workflow-stage: session
  summary: Switch, check or set up the plugin profile a folder or session loads
---

# Plugin profiles

**Arguments.** `[apply <name>|launch [<name>]|status|clear|reset|check|setup]`. With no argument,
infer the action from the conversation: a read-only one (status, check) runs and names what it
inferred; apply, clear, reset and setup are proposed and wait for a yes. A skill that starts a session
calls launch directly. With nothing to infer, run status.

Every action runs the one command-line tool, and only it reads or writes settings and profile
files:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/profiles.mjs" <command> [arguments]
```

Run `profiles.mjs` with no command to print its usage. Never edit a settings file or a profile file
yourself, and never reproduce what the tool decides (which plugins a profile switches, what is
pinned, what is missing): read it from the tool's output. Profile members live in the profile
files only, so name profiles in replies and quote members only from `list`, `apply --dry-run` or
the file the user asks about.

## Every write: preview, ask, then write

The user sees every change before it is made, so each write runs twice:

1. Run the command with `--dry-run` and show its preview lines to the user as printed, not
   summarized: the counts and the named plugins are what they are agreeing to.
2. Ask whether to go ahead, one yes-or-no question per write, worded as below.
3. Only after the user's yes in this conversation, run the same command with `--yes`. The write is
   done when the tool prints its `Applied`, `Saved`, `Installed` or `Cleared` line, or reset's
   line for each file; a non-zero exit means nothing was written, except reset's exit 3, which
   wrote what it could and names each file it skipped. Relay the message.

`--yes` stands for that answer, so it is never passed on a guess, on an earlier yes for a
different write, or when nobody is there to answer: with no one to ask, stop after the preview
and report what would change. When the preview names a missing required prerequisite, `--yes`
does not apply it; tell the user to run the apply in a separate terminal and answer the tool's own
prompt. A `Not installed` line does not stop an apply: only a missing required prerequisite stops
`--yes`.

Every question the skill asks before a write lists the answer that changes nothing (No, Keep)
first and the answer that writes second, and marks exactly one of them `(Recommended)` in its
label, wherever it sits, followed by one short sentence saying why, taken from the preview's facts.
For apply and clear, recommend Yes only when the user asked for that write in this conversation,
naming what the preview changes and how to undo it (clear undoes an apply, applying again undoes a
clear); otherwise recommend No. Reset's questions take the tool's own advice, as its action says.

## Actions

- **status**: `status` names the profile in force for this folder, each entry that differs from it,
  plugins installed since, an unfinished switch, a one-session profile and the plugins added to
  this conversation only, the surface, and the command that starts another session here in the
  profile in force. Relay it; a handoff's restore line is that command, which adds nothing.
- **launch `[<name>]`**: `launch [<name>] [--folder <dir>]` writes the one-session file for the
  folder and profile and prints the `claude` command that starts a session in it; with no name it
  takes this session's profile. It writes no settings file, so it needs no preview. Every launcher
  (a handoff, a background session, a lane) starts sessions through it; see its usage for
  `--with`, `--unattended` and `--json`. A person in a terminal starts one with
  `profiles.mjs start <name>`, or, where their dotfiles define the `claude` shell function, by
  giving it `--profile <name>`, a flag the function adds (Claude Code's own flags:
  [CLI reference](https://code.claude.com/docs/en/cli-reference#cli-flags)); with the function,
  `claude --resume <id>` resumes in the profile, since it runs `start --claude-args` for that
  flag. `claude -c` continues the same conversation it would without the function, with the
  folder's settings, and its start notice prints the `claude --resume <id>` that reopens it in
  its profile. Tell them both forms.
- **reopen with an off plugin**: in a one-session profile, the session-start notice gives the model
  the line `claude --resume <id> --profile-add <plugin or plugin:skill>`. When the work needs a
  plugin or skill the profile switched off (a `## Next` pointer into it, or the user asking for
  it), offer that line with the session's id: it reopens this conversation in its profile with the
  plugin and its dependencies on, for this conversation only, and a later `claude --resume <id>`
  keeps it while new sessions and handoffs start without it. It takes a plugin id, a plugin name,
  `plugin:skill` or a skill name, never settings text. For a plugin that is not installed, the
  tool refuses and prints its `claude plugin install` line: offer that instead.
- **apply `<name>`**: `apply <name> --for folder|initial|session`. Ask where when the user has not
  said: `folder` for this folder, `initial` for every folder without its own profile, `session` for
  one session started with the `claude --settings` command the tool prints. Run `list` first when
  the name is unknown. `native` is Claude Code as it ships: it switches guardrails and every other
  plugin of these marketplaces off and keeps only this plugin on; before that apply, point the user
  to the preview lines naming the always-on plugins it switches off and any it leaves on. To switch inside this session,
  tell the user to run `/plugin-profile`; when
  an apply takes effect is in
  [plugin commands: /reload-plugins](https://code.claude.com/docs/en/plugins/cli-reference#reload-plugins).
- **clear**: `clear [--for folder|initial]` restores what the tool wrote. Inside a session, tell
  the user to run `/plugin-profile` and pick **No profile**, which also reloads the session.
- **reset**: puts every settings file a profile changed on this machine back, every folder and user
  settings, when the user wants all profiles gone. Run `reset --dry-run --json`. Before asking
  anything, show every line of its `lines`, in order, exactly as printed, in a code block: never a
  summary, a paraphrase or a subset of them, since the questions point at "the files above" and
  each line says what reset does to one file. Files in `unchangedSinceReset` are ones an earlier reset put back and nobody
  changed since: reset leaves them, so ask nothing about them. When `question` is set, ask it as
  worded, No before Yes: one yes covers the files a profile record covers, and a no keeps them. Then
  ask each `folders[].ask.question` on its own, whatever the first answer, `ask.no.label` before
  `ask.yes.label`: that row's `ask.file` changes only on a yes for it, and no is the default. The
  recommendation and its reason come from the tool and are never your own: for the first question
  `questionRecommend.asked` when the user asked for a reset, else `questionRecommend.unasked`; for
  each file `ask.recommend`. Mark the option its `answer` names (yes or no) `(Recommended)` and give
  its `reason` as the sentence. When every answer is no, nothing
  is written: run nothing. Otherwise run `reset --yes --json --preview-id <previewId>`, plus
  `--keep-recorded` when the first answer was no, with
  `<ask.yes.flag> <ask.file>` for each yes and `<ask.no.flag> <ask.file>` for each no, the
  file exactly as `ask.file` names it. Relay its `lines`. When the last line says records wait and
  to run reset again (a moved repository goes back one layer per run), offer another reset, starting
  from a new dry run. When it refuses because the preview changed, nothing was written:
  start again from the dry run. Inside a session, tell the user that `/plugin-profile` and
  **Reset** do the same and reload the session.
- **check**: `check` reports profile files that name plugins the catalog or machine lacks; relay
  each FAIL and Report line.
- **setup**: the guided walk below.

## setup

Walk the user through one phase at a time. A phase is done when its result is shown and the user
has answered its question or chosen to skip it; only then start the next. A user who says to skip
questions skips the interview questions only: phase 1 and, for any member not installed, phase 6
always run. Every save and install
goes through the preview rule above. Setup is done when each saved profile has been previewed and
written or declined, and the start offer in phase 7 is answered.

1. **What is installed.** Run `inventory --json`. Report the number of plugins and skills, then
   each plugin with its skills, grouped by marketplace.
2. **What gets used.** Run `usage --json`. When it found history, report the most used skills and
   plugins and the installed plugins with no recorded use. When it reports no usage history, say
   so, propose profiles from the interview and the shipped profiles' descriptions alone, and offer
   to turn on session recording for a later, sharper setup: session-telemetry's hooks record each skill a
   session uses, and recording starts once session-telemetry is enabled (installed first if it is
   not). When `/harness-ops:audit-skill-visibility` is among the available skills, offer it for what
   that recording shows. Either way, say that setup can run again later.
3. **The user's work.** Ask what they work on and in which phases (exploring, planning, building,
   reviewing, interface design, harness upkeep), a few questions at a time, multiple choice where
   the answers are known.
4. **Plugins that ship hooks.** For each installed plugin whose `ships` shows `hooks` or `mod`,
   session-telemetry and plugin-diagnostics included, ask whether it is always on or per profile; what a hook runs on is in
   [hooks: hook lifecycle](https://code.claude.com/docs/en/hooks#hook-lifecycle). Always on: `save always-on --level user --plugins <id>`. Per
   profile: it goes into the profiles the user picks, and every apply names it when it is switched
   off.
5. **Propose profiles.** Start from `list --json`. For each phase the user named, propose the
   shipped profile as it is, an extension of it (a user file of the same name with `--plugins` and
   `--remove`), or a new profile, each with the usage or answer behind it. Save with `save <name>
   --level user|repository`: `user` (under `~/.claude/plugin-profiles/`) for the user's own
   sessions, `repository` (the repository's convention home, committed) only when the user wants
   the team to share it.
6. **Missing plugins.** For a member that is not installed, show `install <id> --dry-run` and
   install only on the user's yes to that plugin at that moment. The tool installs only from a
   marketplace this machine already knows, never for a plugin only a repository profile names, and
   leaves the new plugin off at user level unless the initial profile includes it; it never
   updates or uninstalls. How Claude Code installs a plugin, and what it asks for along the way:
   [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).
7. **Start.** Offer `claude --profile <name>` (or `profiles.mjs start <name>`) for the profile that
   fits the next piece of work, which starts one session in it and writes no settings file.

## Next

- A profile applied to this folder: `/harness-ops:audit-skill-visibility`, to see which skills the
  next session's listing shows.
- A handoff that should restore the profile: `/session-flow:handoff`.

## Gotchas

- Only `/plugin-profile` switches inside a session, and it is a command the user types; when a
  plugin switched off unloads is in
  [plugin commands: /reload-plugins](https://code.claude.com/docs/en/plugins/cli-reference#reload-plugins).
- `save` rewrites the whole file in the tool's form and drops comments; its preview says so, so
  show that line too.
- An install the user approved ends with the plugin off at user level when the initial profile
  lacks it. Apply the profile that names it to switch it on where it is wanted.
