# The built-in `/auto-mode-setup` command, as this skill relates to it

Four-part records behind the `## Boundary` section in `SKILL.md`. The section carries the
conclusion; this file carries what it rests on. Nothing here asserts that the command is present in
any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `/auto-mode-setup` is a built-in command, user-invocable only, hidden from the command menu, and gated; its description is "Teach auto mode about your environment, plus optional rule tweaks" | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary (`model_invocable: false`, `user_invocable: true`, `hidden: true`, `gated: true`) | 2026-09-29, Claude Code 2.1.284 | A release renames or removes the command, or changes its invocability or hidden flag |
| We treat it as the writer of `autoMode.environment` entries, and sometimes rule entries, saved after the person reviews them, and this skill as the reader; what it drafts and where it saves are read from its row, which names only the `environment` entries | Pointer: when routing, fetch the `/auto-mode-setup` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) live; the rule entries are from [auto mode config: generate environment entries](https://code.claude.com/docs/en/auto-mode-config#generate-environment-entries) | 2026-11-21 | The commands page row changes what it drafts or where it saves |
| Its availability depends on plan and version requirements, which we never restate: read them from the same row before telling a person it is available | Same pointer | 2026-10-11 | The commands page row changes its plan or version requirements |
| What it reads: this project's `CLAUDE.md`, `README.md`, config files and git remotes; the person's `autoMode` and `permissions.allow` settings; the hosts, buckets and command names from commands Claude ran in recent sessions in this project, never the person's messages; and, behind two opt-in scans, the first word of each shell-history command and the remotes of repositories under the home directory | [auto mode config: what `/auto-mode-setup` reads](https://code.claude.com/docs/en/auto-mode-config#what-auto-mode-setup-reads) | 2026-11-21 | That section adds or drops a source |
| It also reads recent auto mode denials when it scans a project, and may offer `allow` rules from them. The auto mode config page does not document this yet; the changelog does. The two describe the review differently: the changelog says each rule is reviewed before it saves, the config page that the draft is accepted or discarded as a whole | Changelog, Claude Code 2.1.329: "Fixed `/auto-mode-setup` ignoring recent auto mode denials when it scans a project for rules to suggest; it may now offer allow rules from them, and you review each before it's saved" ([changelog](https://code.claude.com/docs/en/changelog)) | 2026-11-21, Claude Code 2.1.329 | The auto mode config page documents the denial scan, or a release changes what it offers |
| What it writes: `autoMode.environment` entries, and sometimes `allow`, `soft_deny` or `hard_deny` entries, to `~/.claude/settings.json` once the person accepts the draft as a whole. It adds `"$defaults"` to each rule list the draft adds to, unless the person already wrote an `allow` list without it, and keeps `"$defaults"` in `environment` only when the person chose to add rather than replace. After saving, it offers to remove `permissions.allow` rules in that file that auto mode ignores, such as `Bash(*)`, or that auto-approve destructive commands | [auto mode config: generate environment entries](https://code.claude.com/docs/en/auto-mode-config#generate-environment-entries) and its "Review and save the draft" subsection | 2026-11-21 | That section changes what the draft holds, where it saves, or how it handles `"$defaults"` |
| Its argument hint is `[--request-id <uuid>] (--wizard posture=... scope=... depth=... --propose \| --expect-sha256 <64-hex> --apply-file <path>)`: a propose step and a hash-checked apply step | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary | 2026-09-29, Claude Code 2.1.284 | A release changes the argument hint |

## Why the verdict is complementary

The command writes: it produces `environment` entries, sometimes rule entries, and saves them to
user settings after the person accepts the draft. Since 2.1.329 its `allow` entries can come from
recent denials, which is the allow-rule evidence this skill's interview has no source for. This
skill never writes and covers every classifier section, with an interview for stated exclusions and
a condition the classifier can see in the transcript. Using the command for `environment` and
denial-based `allow` rules, then this skill to sharpen those rules and draft the rest, composes
cleanly, since the command's save is what Phase 1 then reads.
