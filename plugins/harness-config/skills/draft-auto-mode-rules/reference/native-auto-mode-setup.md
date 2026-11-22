# The built-in `/auto-mode-setup` command, as this skill relates to it

Records behind the `## Boundary` section in `SKILL.md`. The section carries the conclusion; this
file carries what it rests on. A row with an As of date stores a copied string; the other rows are
pointers and carry no stamp. Nothing here asserts that the command is present in any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `/auto-mode-setup` is a built-in command, user-invocable only, hidden from the command menu, and gated; its description is "Teach auto mode about your environment, plus optional rule tweaks" | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary (`model_invocable: false`, `user_invocable: true`, `hidden: true`, `gated: true`) | 2026-09-29, Claude Code 2.1.284 | A release renames or removes the command, or changes its invocability or hidden flag |
| We treat it as the writer of auto mode classifier entries, saved after the person reviews them, and this skill as the reader | Pointer: when routing, fetch the `/auto-mode-setup` row of [commands: all commands](https://code.claude.com/docs/en/commands#all-commands) live; when deciding what it drafts, fetch [auto mode config: generate environment entries](https://code.claude.com/docs/en/auto-mode-config#generate-environment-entries) live | | |
| Its availability depends on plan and version requirements, which we never restate: read them from the same row before telling a person it is available | Pointer: when telling a person it is available, fetch the same row live | | |
| We treat what it reads as possible input to the interview, never as a source this skill reads itself | Pointer: when deciding what it read, fetch [auto mode config: what `/auto-mode-setup` reads](https://code.claude.com/docs/en/auto-mode-config#what-auto-mode-setup-reads) live | | |
| Since Claude Code 2.1.329 it can offer `allow` rules drawn from recent auto mode denials; we treat those rules as input to the interview's `allow` section. No auto mode config section covers the denial scan yet | Changelog, Claude Code 2.1.329: "Fixed `/auto-mode-setup` ignoring recent auto mode denials when it scans a project for rules to suggest; it may now offer allow rules from them, and you review each before it's saved" ([changelog](https://code.claude.com/docs/en/changelog)) | 2026-11-21, Claude Code 2.1.329 | The auto mode config page documents the denial scan, or a release changes what it offers |
| The changelog and the auto mode config page disagree on how the draft is reviewed | [changelog](https://code.claude.com/docs/en/changelog) and [auto mode config: generate environment entries](https://code.claude.com/docs/en/auto-mode-config#generate-environment-entries) | | |
| We treat its save as the user-settings write that Phase 1 then reads | Pointer: when deciding what it writes, where it saves, or how it handles `"$defaults"` and `permissions.allow`, fetch [auto mode config: generate environment entries](https://code.claude.com/docs/en/auto-mode-config#generate-environment-entries) live, including its "Review and save the draft" subsection | | |
| Its argument hint is `[--request-id <uuid>] (--wizard posture=... scope=... depth=... --propose \| --expect-sha256 <64-hex> --apply-file <path>)`: a propose step and a hash-checked apply step | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary | 2026-09-29, Claude Code 2.1.284 | A release changes the argument hint |

## Why the verdict is complementary

We treat the command as the writer of classifier entries to user settings, once the person reviews
its draft. Since 2.1.329 its `allow` entries can come from recent denials (the stored changelog
line above), which is the allow-rule evidence this skill's interview has no source for. This
skill never writes and covers every classifier section, with an interview for stated exclusions and
a condition the classifier can see in the transcript. Using the command for `environment` and
denial-based `allow` rules, then this skill to sharpen those rules and draft the rest, composes
cleanly, since the command's save is what Phase 1 then reads.
