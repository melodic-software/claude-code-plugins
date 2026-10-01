# Ownership investigation

Run this procedure for every entry the [investigated catalog](safety-model.md#investigated-catalog)
has to account for (hinted, suspicious, or listed under `uncataloged`) before classifying it. It
answers section 2 question 1 (what created it) and question 2 (is the owner active) from evidence on
this machine. Every command is read-only; none kills, pauses or modifies anything.

## Local sources

Check each source that applies to the platform. A source that does not apply or turns up nothing is
recorded as checked with no result, not skipped.

1. **Manifests and READMEs.** `package.json`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `README*`,
   `LICENSE` and similar files in the entry or its nearest parent directories.
2. **Config file contents.** Open the entry's own config files and the owning tool's config
   (`~/.config/<tool>`, the tool's folder under `%APPDATA%`, `~/Library/Application Support/<tool>`). Look for the
   entry's path or name.
3. **Command resolution.** Whether a command named like the entry resolves: `Get-Command <name>` on
   Windows, `command -v <name>` or `which <name>` on Linux and macOS.
4. **Running processes.** A process whose command line, working directory or open files name the
   entry (`Get-Process`, `ps`, `/proc/<pid>/cwd`, `lsof`).
5. **Scheduled tasks.** Task Scheduler (`Get-ScheduledTask`), cron (`crontab -l`, `/etc/cron.*`) and
   systemd timers (`systemctl list-timers --all`, `systemctl --user list-timers --all`) whose action
   names the entry.
6. **PATH.** Whether the entry sits on, or is referenced from, the user `PATH` and the machine
   `PATH` (on Windows read both scopes, not only the session value).
7. **Installed programs.** The package manager or installer inventory (`winget list`, the Uninstall
   registry keys, `dpkg -S`, `rpm -qf`, `brew list`) for a program that owns the path.
8. **Git remotes and status.** When the entry is or contains a repository: `git remote -v`,
   `git status --short`, `git log -1`. A remote names the owner; unpushed or dirty state makes the
   entry real work.
9. **Dotfile and settings references.** The shell profiles, editor settings and dotfile manager
   sources that mention the entry's path or name.

## Recording evidence

Each evidence item is one line with its source: the file path it was read from, the exact command that
produced it, or the URL. An item with no source is not evidence. The finding's `owner` and
`provenance` state the conclusion, and each evidence item's source goes into its `evidence` list as
`{"source": "<source>"}`, so the catalog record keeps what the investigation found. The report shows
the same lines beside the conclusion.

## When no owner is found

Escalate to `/discovery:research` only when every source above found no owner, and only when that
skill resolves in this session. When it does not resolve, skip the escalation and go to the question
below. `/discovery:explore` applies only to a stray inside a repository, never to a home-directory or
volume-root entry, and only when that skill resolves in this session. When it does not resolve, read
the repository's own files with the local sources above.

End the report with one question per entry whose owner is still unknown: name the entry, list the
sources checked, and ask who or what owns it. Until the operator answers, that entry stays `keep`.
