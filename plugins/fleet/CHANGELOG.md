# Changelog

All notable changes to the `fleet` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.26] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [0.2.25] - 2026-11-11

### Changed

- The reach skill and its relay reference replace machine host names with placeholders, and point at the cross-session messaging, headless and agent view sections for held-message expiry, bare sessions and mechanism limits instead of restating them. No behavior change.

## [0.2.24] - 2026-11-11

### Changed

- The `reach` skill's auto mode link uses the section id the permission-modes page renders now.
  No behavior change.

## [0.2.23] - 2026-11-10

### Fixed

- Links to Claude Code's docs that pointed at moved section anchors now resolve: the permissions page's wrapper list, the permission-modes auto-mode section, and Code Review's setup and review-request sections.

## [0.2.22] - 2026-11-07

### Fixed

- `/fleet:reach` sends a remote headless `claude -p` prompt over SSH on stdin (`printf '%s\n' '<prompt>' | <ssh> <alias> claude -p`), with no prompt text inside the quoted remote command, and warns that `ssh -n` would drop the piped prompt. The eval fixture's FLEET.md rows and the graders keyed to the old form follow ([#13856](https://github.com/melodic-software/claude-code-plugins/issues/13856)).

## [0.2.21] - 2026-11-06

### Fixed

- `/fleet:reach` uses the manifest's `/mnt/c` paths as given, never checking them with file tools or asking a subagent to.
- `/fleet:reach` says that each agent-starting command prompts under auto mode, whether it runs, delegates or hands the command over.

## [0.2.20] - 2026-11-06

### Fixed

- `/fleet:reach` no longer tells the session to mint a `--session-id` UUID with `uuidgen` or `/proc/sys/kernel/random/uuid`: a handed-over command keeps `<uuid>` for its runner, and a turn the session runs itself resumes with the `session_id` from `--output-format json` ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).

## [0.2.19] - 2026-11-05

### Fixed

- `/fleet:reach` says a lane's session listing shows only that lane, so a request naming a machine lists each of its lanes (#12908).
- `/fleet:reach` points a receiver that must stay up at a background session, links the docs section on when a `-p` run ends, and asks for standing instructions that say what to do with each message and when to stop (#12908).
- `/fleet:reach` gives one PowerShell quoting rule, for its PowerShell tool and a PowerShell window alike, that passes an apostrophe intact on Windows PowerShell 5.1 and pwsh 7, in place of `-p "..."`, which 5.1 cuts to its first word (#12908).

## [0.2.18] - 2026-11-04

### Fixed

- reword reach's shared-account trigger so the other reach cases keep firing

  The trigger 'share one account across lanes' replaces 'one account for every lane'. On Sonnet it fires on the shared-account prompt as often as the old phrase, without the misses the old phrase showed on the same-repo and port-22 prompts.

## [0.2.17] - 2026-11-04

### Changed

- The reach evals now create the condition each one measures, and their graders accept the correct reply forms they used to fail. `/fleet:reach` itself does not change.

## [0.2.16] - 2026-11-03

### Fixed

- The `reach` skill's description adds the trigger phrase 'one account for every lane' (445 to 475 characters), so a request to sign every lane into one account loads the skill, which declines it.

## [0.2.15] - 2026-11-03

### Changed

- The `reach` skill and its relay reference no longer restate upstream behavior for idle notices from a `-p` sender, print-mode stdin, `wsl.exe --exec`, SessionEnd hook output, WSL interop, or the stream-json input schema ([#12696](https://github.com/melodic-software/claude-code-plugins/issues/12696)). Each rule stays, and each now points at the upstream section with an as-of date and a recheck trigger.

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`, with deterministic graders where an expectation is mechanical ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Three legacy scenarios that the `fr-*` outcome cases already cover are dropped, and each kept prompt names the workspace fleet manifest.

## [0.2.14] - 2026-11-03

### Changed

- The `reach` skill body is shorter (235 to 220 lines) with the same routes, commands, pointers and safety rules: the Purpose section folds into "Resolve the target first", which now comes before the route matrix, and repeated pointers to `reference/relay.md` merge into one. Measured on the three outcome cases: non-inferior to the previous body on Sonnet 5.5 and Opus 5.5 with no case drop.

### Fixed

- The `reach` outcome evals can now produce a VALID pass. Their scaffold writes the fixture `FLEET.md` into the workspace and each prompt names that location, because the agent cannot see `$HOME` in a run: it expands `~` from the `/home/<user>` prefix of the paths in its context, and the run denies that read. `fr-decline-ssh-allow-rule` also gets a workspace settings file, and five regex graders now match their cases' expected outcomes.

## [0.2.13] - 2026-11-03

### Changed

- The `reach` skill's description is shorter (488 to 445 characters) and keeps every quoted trigger phrase and Not-for boundary. On Sonnet and on Opus, a held-out trigger set scored the same before and after (48 of 48 runs each). A generic-description control on the same set, run on Sonnet, dropped two cases, which shows the set can detect a loss. The body is unchanged: no outcome pass could be valid on the measuring host, because the agent read the real home's FLEET.md instead of the eval's scaffolded copy, and the sandbox denied that read.

## [0.2.12] - 2026-10-30

### Added

- The three `reach` outcome eval cases seed a fixture `~/.config/fleet/FLEET.md` through `context.scaffold_script` when a run passes `--scaffold` ([#8550](https://github.com/melodic-software/claude-code-plugins/issues/8550)), so the skill's first step finds a manifest. The fixture names only made-up hosts and accounts, and its script refuses to run against the account's real home or to overwrite a file.

## [0.2.11] - 2026-10-29

### Fixed

- The `fr-decline-ssh-allow-rule` eval's `declines-allow-rule` grader accepts a "Why I didn't add `Bash(ssh:*)`" heading, and `names-the-cost` accepts a rule that "would approve" or "would allow" any or every ssh command. The `fr-git-bash-publickey` eval's `not-a-key-problem` grader accepts "not that a key is broken" and "the wrong key or no key, not a broken one". The `fr-expired-oauth-login` eval's `no-credential-in-prompt` grader accepts "advise against both" followed by a heading saying the key in the prompt won't work. Each has new pass samples and a fail sample that must still fail.

## [0.2.10] - 2026-10-28

### Fixed

- The `fr-expired-oauth-login` eval's `no-credential-in-prompt` grader accepts a reply that declines both moves in one sentence and names the credential in the bold heading after it. New samples cover that wording and a reply with credential headings that declines nothing.

## [0.2.9] - 2026-10-23

### Added

- `/fleet:reach` names `fleet-converge <lane>`, run by its bare name, as the way to converge dotfiles on any fleet lane, with a dated pointer to the dotfiles design record for what it checks.

### Changed

- `/fleet:reach` allows a distro start that `fleet-converge` makes itself as the one exception to the `wsl -d` ban on a target's drift-convergence path; an agent never runs `wsl -d` on its behalf.

## [0.2.8] - 2026-10-20

### Added

- Three outcome eval cases under `evals/` and a frozen trigger-probe set under `probes/` for `reach`.

## [0.2.7] - 2026-10-20

### Fixed

- `/fleet:reach` no longer says an interactive session simply accepts inbound messages: it holds one from a sender that bypasses permission prompts, and a `-p` receiver without `crossSessionInbound: accept` drops a held message after `dialogExpiry`.
- The relay reference's agent view note now names the `#limitations` anchor, an as-of date and a recheck trigger.

## [0.2.6] - 2026-10-18

### Changed

- `/fleet:reach` relay reference marks the `logs` accepts-only-the-id probe row as observed on Claude Code 2.1.284, so it no longer reads as current behavior.

## [0.2.5] - 2026-10-13

### Changed

- `/fleet:reach` stops restating error strings and documented flag behavior, and dates its measured per-turn cost; it keeps our probe results and decisions and points at the live sections (errors, cross-session messaging, CLI flags, auto mode) with an as-of date and recheck trigger.
- `/fleet:reach` no longer states a per-turn cost figure in its body; it links the costs page and keeps the dated measurement in its relay reference's Cost row.

## [0.2.4] - 2026-10-10

### Fixed

- **`/fleet:reach` no longer says `claude logs` rejects a session name.** Current Claude Code accepts part of a session's name for `claude logs` and `claude attach`. The skill and its relay reference now say to address a background session by the id from `claude agents --json --all`, which lists completed sessions too and works on every lane, and to check the lane's version against the CLI reference before passing a name instead.

## [0.2.3] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.
- The `reach` skill description no longer contains angle brackets: placeholders such as `<X>` are now uppercase words. The Agent Skills spec forbids XML tags in a description, and claude.ai strips them.

## [0.2.2] - 2026-10-02

### Changed

- **`reach`'s relay probe table no longer states a per-turn dollar figure.** The Cost row keeps
  what the cost went to and points at the official cost-tracking docs for measuring a turn.

## [0.2.1] - 2026-09-30

### Changed

- **`reach`'s description fits the 500-character listing budget and the 1,024-character field cap.** Its core triggers and the same-lane and other-machine routes are kept ([#4661](https://github.com/melodic-software/claude-code-plugins/issues/4661)).

## [0.2.0] - 2026-09-29

### Added

- `reach` covers same-machine cross-lane reach: WSL to native Windows by running `claude.exe` over
  interop, and Windows to WSL through `wsl.exe -d <distro> --exec`, with the distro read from
  `wsl.exe -l -q`. Apostrophe quoting follows the origin shell: `'\''` in bash and Git Bash,
  `''` in pwsh.
- A route matrix at the top of `reach`: every origin lane against every target lane, each row
  carrying its command shape and whether it was tested.
- A Verbs section: run a script, prompt, multi-turn (`--session-id` then `--resume`), one open
  stream-json pipe, list sessions, message a session, a named headless receiver (`-n <name>` with
  `crossSessionInbound: accept`), and background sessions (`claude --bg --name`, trusted directory
  only). Each verb is marked tested or untested. Every verb but running a script starts an agent,
  prompts under auto mode, and costs about $0.22 to $0.31 per one-line turn, so a script is
  preferred where it does the job; `--bare` cuts the cost but cannot receive messages.
- Query and wait polls `claude agents --json` or reads the receiver: `notify_when_idle` from a `-p`
  sender does not arrive before its turn ends. Remote Control stays out of headless recipes, since
  `-p --remote-control` does not connect.
- `reference/relay.md` lists the mechanisms the skill does not use (Remote Control, cloud sessions,
  Channels, the raw inbox socket, agent teams) and why, and documents the signed-out Windows lane
  check (`Failed to authenticate: OAuth session expired`, fixed by `/login` at that console), the
  receiver's nested quoting and lifetime, and a verification record for each route.
- Evals for the cross-lane routes, query and wait, the named receiver, the signed-out lane, and the
  run-a-script verb.

### Changed

- The account model is per lane, not per machine: WSL and native Windows on one machine can sign
  into different accounts, and the built-in peer tools reach only the current lane. Description,
  Boundary and README now say so, and the peer tools own same-lane messaging only.
- Commands address targets by their FLEET.md ssh alias through the Windows OpenSSH client.

## [0.1.3] - 2026-09-27

### Fixed

- `reach`'s Boundary table routes repository fleets to `repo-fleet-hygiene:audit` instead of the bare plugin name (#4119).

## [0.1.2] - 2026-09-23

### Changed

- `reach`: a one-shot remote prompt states what done looks like and what should make the remote
  turn stop and report, since nobody answers its questions.

## [0.1.1] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.1.0]

### Added

- Initial release. One skill, `reach`: run a Claude Code agent turn on another machine in the
  fleet over SSH on the tailnet.
- Target resolution from the rendered fleet manifest at `~/.config/fleet/FLEET.md`, addressing
  machines by hostname over the tailnet rather than by session name.
- Verification, one-shot and multi-turn (`--output-format json` plus `--resume`) headless recipes
  for the WSL hop, and the reason port 22 is not an agent lane. The recipes and a Gotchas entry
  carry the apostrophe rule: a `'` in `<prompt>` closes the local shell's outer single quote
  before ssh runs, so replace each `'` with `'\''` or wrap the remote command in `$'...'`.
- The Windows-side relay, in `reference/relay.md`: reaching a target's own native-Windows sessions
  through the same SSH hop, since a WSL session and a native Windows session on one computer
  cannot see each other. The relay command carries the same apostrophe rule as the hub recipes.
- The account model: why the accounts are split per machine and why that puts the built-in peer
  tools out of reach across machines.
- The permission posture: remote agent launches are outside the auto-mode classifier and prompt by
  design, with no ssh allow rule and no `bypassPermissions` on either side.
