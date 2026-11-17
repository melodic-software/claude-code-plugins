# Scenarios: what each situation does, and how to get back

Each row says what happens, how to return to the state before any profile, and its proof: a test in
[`scripts/profiles.test.mjs`](../scripts/profiles.test.mjs) (or the `lib/` test it names), quoted by
name, or a live probe from [Live probes](#live-probes) with the Claude Code release it ran on. A
probe row marked **waits on probe** has no live result yet.

"Before any profile" means the settings files as they were before the first apply, and for a
one-session profile, a session started without its file.

## Levels and where they are stored

| # | Situation | What happens | Back to before | Proof |
|---|---|---|---|---|
| 1 | Initial profile | `apply --for initial` writes `enabledPlugins` and `skillOverrides` in `~/.claude/settings.json`; new folders start from it | `clear --for initial` | "#16432: apply --for initial sets the initial profile in user settings, status --for initial names it, and clear --for initial puts user settings back"; "apply always-on --for initial switches on the always-on members alone in user settings" |
| 2 | Folder profile | `apply --for folder` writes the `.claude/settings.local.json` Claude Code reads: the repository root's, shared by every worktree and subdirectory; the folder's own on Windows, outside git, at the home folder, or where the root is not yours ([Claude Code's rule](https://code.claude.com/docs/en/settings#where-claude-code-keeps-the-local-file-in-a-git-repository)) | `clear` restores the file byte for byte, or removes it when the apply created it | "AC19: clear after apply restores the file byte for byte"; "AC19: with no settings file before the apply, clear removes the file"; `lib/folder-file.test.mjs` |
| 3 | One-session profile | A file passed with `--settings`; no settings file changes. It names every plugin and skill a profile can switch, so nothing from another level leaks in | Start a session without it (`claude`, or `claude-profile` and pick **No profile**) | "AC2: a one-session apply writes a --settings file naming the profile, says to pass it again on resume, and leaves every settings file byte-identical"; "#16893: a one-session file names every plugin and skill entry any folder profile writes, so a folder switch elsewhere never reaches that session" |
| 4 | Repository profiles and pins | A repository profile shapes the folder, never the initial profile, and cannot switch off an always-on member; a plugin the committed `.claude/settings.json` enables stays on unless excluded, one it sets `false` stays off. Order between levels: managed, one-session file, folder, repository, user ([settings precedence](https://code.claude.com/docs/en/settings#settings-precedence)) | As row 2 | "a repository profile shapes the folder but never the user settings an initial apply writes"; "a repository profile's exclude of an always-on member is ignored, and the rest of that profile still applies"; "#16893: a plugin's state follows Claude Code's order: --settings over local over project over user"; `lib/plan.test.mjs` "AC18: a managed entry pins its plugin, which is reported and left alone" |
| 5 | Record of what an apply changed | Kept outside the data folder: `<main checkout>/.git/plugin-profiles/records/` for a folder in git, `~/.claude/plugin-profiles-state/records/` for the initial profile, the plugin's data folder outside git; the data folder is also read as a fallback | Read by `clear` | "#16893: the record of a folder in git lands under .git/plugin-profiles/records, and clear still restores after the data folder is deleted"; "#16893: the initial profile's record lands under the config folder's plugin-profiles-state, outside the data folder"; "#16893: a record an earlier version left in the data folder is still found and cleared, and the next apply moves it to the primary home" |

## Sessions, folders and worktrees

| # | Situation | What happens | Back to before | Proof |
|---|---|---|---|---|
| 6 | Several sessions in one repository | A folder switch reaches every session of the repository, in any worktree, at its next `/reload-plugins` or start; the switch's confirm names them. A one-session profile is the way to keep one terminal apart | Row 2 for the folder; each terminal's own session as row 3 | "#16893: a folder dry-run from a linked worktree names the live sessions in every worktree of the repository"; `lib/sessions.test.mjs`; live reach: **waits on probe** P7 |
| 7 | Sessions started in the main checkout that work in worktrees | They read the main checkout's file, as row 2 | Row 2 | "#16893: from a linked worktree and from a subdirectory, apply --for folder writes the main checkout's root file, and status there names it" |
| 8 | A worktree file an earlier version wrote | Claude Code reads it only for plugins the root file does not set; status and the start notice name it as partly in force | `clear --for worktree` | "#16893: an earlier worktree file with its own record is named as partly in force, the root's value wins in launch, and clear --for worktree puts it back"; "#16893: clear --for worktree restores an earlier worktree file byte for byte"; live, with both files present: **waits on probe** P6 |
| 9 | Entering a worktree mid-session | **waits on probe** P6: which file status and the next `/reload-plugins` read | Row 2 | P6 |
| 10 | A submodule | Its own root; no profile from the checkout around it | Row 2 | "a folder whose .git is a file without a commondir, such as a submodule, is its own root and takes no profile from the checkout around it" |

## Session lifecycle

| # | Situation | Folder profile | One-session profile | Proof |
|---|---|---|---|---|
| 11 | `/clear` | Plugins unchanged; the start notice shows again | The file stays in force; the new session id is recorded, so a later resume finds it | "#16893 the session-start hook records the profile a session runs in by its id, and skips a bad id or bad input" (the hook runs on `clear` too, `hooks/hooks.json`); live: **waits on probe** P1, P2 |
| 12 | `/resume` inside a session, or Ctrl+C then `claude --resume <id>` | Holds: it is on disk | A plain `claude --resume` starts without the file and its start notice prints `claude-profile --resume <id>`; that command resumes in the profile | "#16893 a session resumed without its profile is told the command that resumes it there, even in a folder with no profile"; "#16893 start --resume takes the recorded profile; a given profile wins; no record resumes with the folder's settings"; "#16893 start --resume rewrites a missing session file through launch"; ADR 0109 `resume-keeps-settings` (2.1.325); live: **waits on probe** P3, P4 |
| 13 | `claude-profile -c` | Holds | Resumes the latest session started in that folder in a profile | "#16893 start -c resumes the latest session started here in a profile, else passes -c through" |
| 14 | A crash (the process killed) | As row 12 | As row 12 | **waits on probe** P5 |
| 15 | A background or relay session | As row 12 | Lanes and relays pass the file at start; its id is recorded like any other | **waits on probe** P8 |

## Edits and interruptions

| # | Situation | What happens | Back to before | Proof |
|---|---|---|---|---|
| 16 | A switch cut off between its on write and its off write | Recorded as unfinished; status names it; the next apply finishes it | `clear`, or apply again | "D8: a switch cut off after its first write is recorded off-pending, named by status, and finished by the next apply" |
| 17 | Several applies stacked | Each keeps the first apply's before-values | `clear` | "a second apply over a first keeps the first apply's before-values, so clear still restores the original" |
| 18 | A clear by another copy of the tool than the one that applied | Found through the record homes of row 5 and other copies' data folders | `clear` from either copy | "#16818: an installed copy clears a profile a --plugin-dir copy applied, whose record sits in plugin-profiles-inline"; "#16893: a CLAUDE_PLUGIN_DATA another plugin set is ignored, so the record and session file stay where every copy finds them" |
| 19 | The settings file edited by hand after an apply | Status names each entry that differs; clear names each hand edit it overwrites before asking | `clear` | "AC12: status names the folder's profile and every entry that differs from it, and AC22 plugins installed since"; "#16893: clear names each entry edited since the apply that it overwrites, and leaves an entry already back at its before-value unnamed" |
| 20 | A plugin installed after an apply | Named by status and the start notice | `clear` | "AC22: a plugin installed after the apply is named by the session-start notice" |
| 21 | A plugin uninstalled after an apply | Clear still writes its before-entry back | `clear` | "#16893: a plugin uninstalled after the apply leaves clear able to restore the file byte for byte" |

## Reset when the record is gone

| # | Situation | What happens | Back to before | Proof |
|---|---|---|---|---|
| 22 | A fresh clone, or `.git` removed and cloned again, with no data-folder copy | The file may still hold profile entries; clear says it cannot tell which ones a profile wrote, changes nothing, and names the keys to remove | Remove the `enabledPlugins` and `skillOverrides` keys from the file by hand | "#16893: with .git/plugin-profiles gone after an apply, as in a fresh clone, and no data-folder copy, clear says it has no record and changes nothing"; "#16893: clear with no record but plugin entries in the file says it cannot tell which a profile wrote, and changes nothing" |
| 23 | A linked worktree, whose `.git` is a file | The record goes under the common git folder, so every worktree finds it | `clear` from any worktree | "#16893: an apply from a linked worktree puts the record under the common git folder, never under the worktree's own gitdir" |

## Dotfiles

| # | Situation | What happens | Back to before | Proof |
|---|---|---|---|---|
| 24 | `~/.claude/settings.json` managed by chezmoi | The owner's dotfiles render it through a modify template that forces an `enabledPlugins` map. After `apply --for initial`, `chezmoi diff` shows the changed entries, and the next `chezmoi apply` puts every forced entry back; status then names each as differing from the profile. [melodic-software/dotfiles#1607](https://github.com/melodic-software/dotfiles/issues/1607) resolves it: the dotfiles run `apply always-on --for initial --yes` instead of forcing the list | `clear --for initial`, or `chezmoi apply` for the forced entries | **waits on probe** P9 |
| 25 | Folder profiles under chezmoi | Not affected: `.claude/settings.local.json` is not chezmoi-managed and is ignored by git | Row 2 | Claude Code's git exclude ([settings](https://code.claude.com/docs/en/settings#keep-personal-settings-out-of-a-repository)) |

## Live probes

Run by a person in an interactive session, on the release named in each result. Use a throwaway
git repository `P` with one linked worktree `P-wt`, and two installed plugins `A` (a member of
`build`) and `B` (not a member). "Check the plugins" means `/plugin`, or typing `/` and looking for
`A`'s and `B`'s skills.

| Probe | Steps | Expected | Result |
|---|---|---|---|
| P1 `/clear`, folder | In `P`: `apply build --for folder --yes`, start `claude`, check the plugins, run `/clear`, check again | `A` on and `B` off both times; the start notice shows again after `/clear` | waits |
| P2 `/clear`, one session | `claude-profile build`; `! printenv PLUGIN_PROFILES_SESSION`; `/clear`; check again | `build` both times, `A` on | waits |
| P3 Ctrl+C then resume, folder | After P1, Ctrl+C twice, then `claude --resume <id>` | `A` on | waits |
| P4 Ctrl+C then resume, one session | After P2, Ctrl+C twice, then `claude --resume <id>`; then exit and run `claude-profile --resume <id>` | First: the start notice names `build` and prints `claude-profile --resume <id>`; `printenv` is empty. Second: `printenv` shows `build`, `A` on | waits |
| P5 crash | As P4, ending the session with `kill -9 <pid>` from another terminal | As P4 | waits |
| P6 worktree mid-session | In `P` with a folder profile and an earlier worktree file in `P-wt` setting `A` the other way: start in `P`, enter `P-wt` (EnterWorktree or `/cd`), run `! node <profiles.mjs> status` and `/reload-plugins` | Status names `P`'s file and the partly-in-force `P-wt` file; after the reload `A` follows `P`'s value | waits |
| P7 five sessions | Five terminals in `P` and `P-wt`, each `claude-profile <different profile>`; in a sixth, plain `claude`, run `/plugin-profile review` and send a message; in each of the five, `/reload-plugins` | The five keep their own plugin sets; the confirm in the sixth names all five | waits |
| P8 background or relay | Start a session through the lane launcher or `/fleet:reach` in a profile, `/clear` it, end it, resume with `claude-profile --resume <id>` | The profile holds after `/clear` and on resume | waits |
| P9 chezmoi drift | On a host whose dotfiles force `enabledPlugins`: `apply review --for initial --yes`, `chezmoi diff ~/.claude/settings.json`, `chezmoi apply ~/.claude/settings.json`, `status --for initial`, `clear --for initial --yes` | The diff lists the profile's entries; after the apply, status names each forced entry as differing; clear leaves no diff | waits |
