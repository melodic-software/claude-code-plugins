# Safety model

## Contents

- [Trust boundaries](#trust-boundaries)
- [Tidiness, not emergency](#tidiness-not-emergency)
- [Non-overridable checks](#non-overridable-checks)
- [Live agent scratchpads](#live-agent-scratchpads)
- [Handle semantics and honest scope](#handle-semantics-and-honest-scope)
- [Manual-handoff revalidation (`handoff-verify`)](#manual-handoff-revalidation-handoff-verify)
- [Opt-in elevation](#opt-in-elevation)
- [Outcome vocabulary](#outcome-vocabulary)
- [Primary references](#primary-references)

## Trust boundaries

The target path, optional policy, model-authored plan, filesystem metadata, Git output, and process
handle output are untrusted inputs. The Python boundary parses them without shell interpolation,
canonicalizes every selected path under the snapshot root, and rejects absolute paths, traversal,
overlap, and entries absent from the snapshot.

Standing-policy `additional_hints[].reason` prose is likewise untrusted: the additive-only design
means a hint can never authorize anything, but its reason text reaches the model's triage reasoning
unlabeled. Treat it as an unverified claim requiring independent evidence, never as a finding.

Candidate patterns are advisory. The model supplies contextual evidence, but the engine alone decides
whether an exact plan is mechanically eligible. Neither layer may weaken the other:

- model judgment excludes work product and defers to owning-system cleanup;
- deterministic checks exclude protected/changed/tracked/linked/mounted/open/unverifiable entries;
- explicit human approval authorizes one tier and exact list;
- the engine binds that preview to a snapshot nonce and plan digest.

## Tidiness, not emergency

The cleaner has no disk-full mode. Every pass is a cautious tidiness pass: bytes stay secondary,
mutation still needs a fresh preview and one-tier approval, and a filename pattern stays a hint.
An operator facing a full disk acts with OS tools, Recycle Bin / Trash, or the owning product's
GC; this engine does not become more aggressive under pressure.

Regenerable-but-costly state (a build cache versus an irreplaceable artifact) is not an engine
signal. High/Medium/Low already encode provenance, not regeneration cost.

**Claim:** the cleaner does not distinguish a tidiness pass from a disk-full emergency; none of
the three rules yields, and regenerable-at-a-cost is not an engine signal. **Basis:** #3855 is
the decision carrier and lists changing nothing as a complete answer; relaxing any of those
rules under pressure is when a wrong deletion is most likely. The no-proportionality decision keeps
the current defaults rather than funding a proportionality rebuild. **As of:** 2026-09-28.
**Recheck:** reopening #3855, or a funded design that names which rule yields and under what
bounded conditions.

## Non-overridable checks

- target containment; an OS-managed root (per `system_roots()`: the OS drive holding an existing
  Windows install / `Program Files` / `ProgramData`, or `/` holding `/bin`, `/etc`, …) is denied as
  a recursive walk target, while `--root-children` may address that same root only as a listing of
  immediate non-OS child entries (regular files and directories) with explicit `--root-child`
  selection (never a whole-root
  walk); `--root-children` is also valid on a directory that is not a volume root (a user home),
  where only directories are admitted and hidden and OS-named ones stay selectable, so approved
  immediate children can be re-inventoried into one snapshot without walking the rest of the tree;
  a non-OS volume root (a Windows Dev Drive: a drive root carrying only the per-volume
  metadata every volume has and no OS-install marker) is a valid target rather than blanket-denied,
  but as a known-large root it is routed through the large-target scan gate below (bound or
  confirm), its `--root-children` listing uses the same strict ladder as an OS-managed volume root
  (`System Volume Information`, `$Recycle.Bin`, `$`-prefixed, hidden, and OS-owned names are
  withheld), and deletion stays gated by the preview and per-tier approval;
- the audit root itself is never a removal candidate; no protected shell-folder root, OS
  registry/profile hive, VCS metadata or tracked file, except that the read-only manual-handoff
  verifier may classify a whole standalone Git checkout `clear` under the complete evidence bundle
  below;
- no symlink, Windows reparse traversal, non-root mount target, nested mount, or Linux bind mount
  (a volume root is itself a mount point and is governed by the OS-managed/confirmation reasoning
  above, not this structural mount veto);
- exact file identity and complete descendant set unchanged since snapshot;
- repository markers re-discovered from live filesystem state and the Git index queried with
  `git ls-files` at preview and apply; snapshot VCS/protection annotations are never trusted;
- live-handle state proven clear; missing authority or tooling blocks;
- no handle closing, and no elevation unless the operator opted in (see
  [Opt-in elevation](#opt-in-elevation));
- one confidence tier per plan and approval.

The policy overlay can add protections, disable candidate hints, and add consumer hints. It cannot
remove a non-overridable check or baseline protected name. Its version 2 `elevation` field is the
one setting that widens what the skill may do, on Windows only, as described under
[Opt-in elevation](#opt-in-elevation).

## Live agent scratchpads

A Claude Code temp root (`%TEMP%\claude` on Windows, `$TMPDIR`-derived on POSIX, relocated by
`CLAUDE_CODE_TMPDIR`) is a plausible target: it accumulates per-session scratchpads with no cleanup
owner, and `machine-health`'s `claude-temp-root` check routes its findings here. Its hazard is not
the session running the clean, which is identifiable by `CLAUDE_CODE_SESSION_ID`, but a
*concurrently running other* session, whose scratchpad is an active working directory with no marker
distinguishing it from an abandoned one. Directory age does not separate them: a long-running
session's scratchpad is old and live at the same time, so no age tier can be trusted to mean
"finished".

Nothing new is needed to hold that line; the existing non-overridable checks already do, and they do
it structurally rather than by heuristic:

- **Live-handle proof.** An open file under a running session's scratchpad is `locked`, and any
  authority, tooling, timeout, or unverifiable condition is `handle-state-unverified`, and both keep
  the entry. This is the primary defense and it fails closed.
- **VCS markers re-discovered from live state.** Agent scratchpads routinely hold clones and
  registered worktrees of real repositories, at paths such as
  `<temp-root>/<project-key>/<session-id>/scratchpad/`, and their pack files can dominate the
  tree's size. Repository markers are re-discovered and `git ls-files` re-queried at
  preview and at apply, since snapshot annotations are never trusted, so a repository checked out after
  the snapshot still refuses.
- **Identity and descendant-set equality since snapshot.** A live session writes continuously, so its
  scratchpad drifts between snapshot and apply and lands `changed-or-link` or `drifted`. The
  quiescence a `clear` verdict describes is exactly what a live scratchpad cannot hold.
- **Verdict expiry.** `handoff-verify` verdicts expire immediately and are per-path, so a session
  that starts writing between two paths cannot be covered by an earlier path's approval.

Two consequences worth stating plainly. First, on Windows and macOS the engine returns
`execution-platform-unsupported`, so a Windows temp root, where this growth was measured, is a
manual-lane job under the per-item human prompt, never an engine apply. Second, the honest posture
here is that a temp root is a *low*-confidence target however large it looks: the tier is set by what
can be proven quiescent, not by how much space would be reclaimed.

## Handle semantics and honest scope

On Windows, `CreateFile` with a zero share mode conflicts with existing access and
`FILE_FLAG_BACKUP_SEMANTICS` permits the same probe for directories. Sharing violations are `locked`;
access/privilege failures are `needs-elevation`; other errors are unverified.

On Linux/macOS, `lsof <file>` or `lsof +D <directory>` supplies the process view. `+D` is bounded by
the caller's authority and may be slow; a timeout, diagnostic, absent binary, or unexpected exit is
`handle-state-unverified`. The plugin never substitutes deletion failure because POSIX may unlink an
open file while the process retains the underlying object.

Execution is intentionally not cross-platform. Linux requires readable `/proc/self/mountinfo`,
`O_NOFOLLOW`, and descriptor-relative stat/unlink/rmdir. Apply anchors the target and every parent to
directory descriptors, verifies those descriptor identities, repeats live mount/protection/Git/handle
checks immediately before each operation, and walks only snapshot entries bottom-up. Once captured
children have been removed, apply opens the directory itself with `O_NOFOLLOW`, verifies its stable
device/inode/type identity, proves it empty through that descriptor, rechecks the name-to-descriptor
identity, and only then calls descriptor-relative `rmdir`. Windows and macOS return
`execution-platform-unsupported`; their audit and report behavior is unchanged.

Windows and macOS execution stays declined by design. A descriptor-anchored Windows apply would
be a large new trust surface, while the manual lane's per-item revalidation rules and the
`handoff-verify` revalidation keep the residual approval-to-execution window small. A near-miss
recurrence in the manual lane reopens this as a design question with full security review.

**Claim:** the reversal trigger has not fired; Windows and macOS stay behind the platform-name
execution gate (`os_key() != "linux"`); per-primitive re-gating of macOS is a new design
question, not this trigger firing. **Basis:** the trigger quoted from the
[#1116](https://github.com/melodic-software/claude-code-plugins/issues/1116) maintainer
affirmation (2026-07-23): "if handoff-verify proves insufficient in practice (a post-#1109
near-miss recurrence), reopen as a design issue with full security review." No post-#1109
near-miss recurrence is on the record in this checkout. #3855 closed 2026-09-28 with the
no-emergency-lane decision, not a per-primitive design. **As of:** 2026-09-28. **Recheck:** a
documented post-#1109 near-miss in the manual lane, or a macOS consumer.

## Manual-handoff revalidation (`handoff-verify`)

`handoff-verify` brings snapshot binding to the platforms where apply is unsupported, without
adding an engine deletion lane. It takes the snapshot plus the human-approved exact path list
(same containment rules as plan candidates: relative, non-root, no traversal, present in the
snapshot, non-overlapping), re-validates the target root with the same link/mount/OS-managed/
protected-path and stable device/inode/type root-identity checks preview and apply use. The root's
own mtime and size flip whenever any direct child is added or removed, so they are not identity; a
replaced root still refuses. It then reruns the per-path
identity/reparse/protection/descendant/VCS/handle checks against live state and emits one
machine-readable verdict per path. When those settled removals (`clear` or `gone`) would empty
inventoried directories, the same round reports them under `emptied_containers`, deepest first,
using the apply lane's bottom-up ordering key. They are not in the approved list: each still
needs its own approval and is removable only after every path beneath it is gone. Verification
still mutates nothing. It deliberately does not apply platform execution blockers, since
it exists exactly where `execution-platform-unsupported` blocks the engine lane, and it has no
deletion capability of any kind: the model deletes only verdict-`clear` paths in the manual lane,
per item, under the hook-issued `ask` the PowerShell guard returns. Add a `permissions.ask`
rule for the deletion spellings if that prompt must appear in `auto` and `bypassPermissions`;
leave `dontAsk` first, because that mode auto-denies an `ask` rule instead of prompting.

### Standalone Git checkout evidence

VCS protection remains categorical in preview, apply, and every handoff verification that does not
explicitly supply `--vcs-evidence`. The evidence mode can relax only
`vcs-tracked-content`, `vcs-metadata`, `.git`'s own `baseline-protected-name`, and the opaque scan
boundary at that `.git` marker. It does so only when all four live gates pass for every repository
marker within the one approved checkout (gates 1 and 2 may instead be waived by the
`accept_unpublished` acknowledgement described below):

1. `git status --porcelain=v1 --untracked-files=all --ignored=matching --ignore-submodules=none`
   exits successfully and emits nothing, including gitignored-but-present paths (`.env`, local
   databases, IDE state) that ordinary porcelain status would omit.
2. Every `refs/heads/*` tip, plus a detached `HEAD` when present, is confirmed by exact SHA through
   the configured `github.com` remote's `gh api repos/<owner>/<repo>/commits/<sha>` endpoint. An
   unborn repository with no local heads satisfies this gate vacuously; a missing remote is accepted
   only in that case.
3. Every SHA emitted by `git stash list --format=%H` also appears in the stash list of at least one
   declared independent checkout outside all approved deletion paths; no stashes satisfies the gate.
4. The checkout is one exact human-approved path, given inline as `--path` or listed in
   `handoff-paths.json`. The evidence option adds no approval surface and creates no token.

The engine discovers `.git` markers from live descendants and requires their repository-root set to
equal the evidence file exactly. `git rev-parse --show-toplevel` must bind each marker to the declared
root, and `--git-common-dir` must resolve inside the approved checkout; this rejects linked
worktrees. Stash-copy paths must be absolute, non-link checkout roots, independent of the candidate
and every path approved in the same handoff, and must resolve a `--git-common-dir` distinct from
(and not nested under) the source repository's common Git directory. A linked worktree of the
candidate shares stash refs and is not an independent backup. Only GitHub.com is implemented:
unsupported providers, missing tools, timeouts, diagnostics, malformed output, set mismatches,
dirty trees, unconfirmed heads, and missing stash copies all fail closed and retain the original
categorical reasons, except that the `accept_unpublished` acknowledgement below waives the dirty-tree
and unconfirmed-head reasons for one exact approved path.

An operator who wants a throwaway checkout gone even though it fails gates 1 or 2 records that on
the evidence entry: `"accept_unpublished": true` with a non-empty `"reason"`. The engine accepts it
only on an entry whose `path` is itself an exact approved path, so a nested repository or a pattern
cannot carry it. For that repository, porcelain output and local heads that are not on a
`github.com` remote (or have no remote) stop failing gates 1 and 2; those gates report
`accepted-unpublished` and the evidence result lists each acknowledgement with its reason under
`accept_unpublished`. A status or head probe that fails to run still fails closed, and gate 3, the
repository-set and Git-boundary checks, and every check in the next paragraph still apply. Without
the acknowledgement the verdict is unchanged. A refusal alone does not prevent deletion, so the
lane keeps every other check in force and records the acknowledgement. Before deleting under it,
tell the operator that unpushed commits and untracked or ignored files in the checkout will be
lost.

Passing this bundle does not relax any non-Git protected name, non-Git VCS marker, mount,
link/reparse, consumer protection, identity/descendant, or live-handle check. The mode is read-only;
deletion remains a per-path manual handoff under the existing hook-issued `ask`, and the
verdict still expires immediately.

| Verdict | Meaning | Manual-lane action |
|---|---|---|
| `clear` | Every check passed against live state at emission time | Delete this exact path immediately. Verify one path per deletion, never one batch for all (earlier checks age while later paths are probed) |
| `gone` | The path no longer exists | Nothing to delete; report it |
| `drifted` | Identity, kind, or the captured descendant set changed since the snapshot | Keep; the approval no longer describes what is on disk, so rescan |
| `contested` | Protection, VCS state, a live handle, elevation, or unverifiable state | Keep; the reasons list names each contest, so resolve and re-verify |

Fail-closed mapping: every unverifiable condition (handle tool missing or timing out, unreadable
state, truncated coverage) lands in `contested`, never `clear`. A `clear` verdict authorizes
nothing by itself. It reports that revalidation found no change and no contest at that instant;
the human approval and the per-item prompt remain the authorization. Verdicts expire immediately:
any delay or interruption means re-running handoff-verify. Managed-state exclusion stays where it
always was in the manual lane, with model judgment plus human review of the audit report, because
snapshot entries carry no owner claim for the engine to check.

The skill-frontmatter Bash belt accepts only complete literal words in the four declared engine command
shapes. It rejects every Bash expansion family, glob/word-splitting input, redirection, operator,
escape, and compound-command form before validating arguments. Canonical script-path comparison uses
the host platform's path case rules; POSIX path identity is never case-folded. A `--data-root` value
is accepted only when it matches the plugin data directory the guard derives from
`${CLAUDE_PLUGIN_ROOT}`, the only substitution a skill-frontmatter hook receives, passed to the
guard as `--plugin-root` and mapped to `<plugins>/data/<id>` per the documented
[persistent-data-directory](https://code.claude.com/docs/en/plugins-reference#persistent-data-directory)
layout, either from the root's `<plugins>/cache` layout or, for a plugin loaded in place from a
local-directory marketplace, through `known_marketplaces.json` (see below). A host that can
substitute `${CLAUDE_PLUGIN_DATA}` itself may instead pass it directly as
`--authorized-data-root`. The `CLAUDE_PLUGIN_DATA` environment variable is never a
channel: a repository `settings.json` `env` block can set it, so it carries no
provenance. A literal unsubstituted placeholder counts as absent. Absent every
trusted channel the flag fails closed. `--data-root` is mandatory at the guard even
though the engine's grammar leaves it optional so a state-writing subcommand can
refuse its absence with the engine's own diagnostic; an otherwise exact call that
omits it is denied. The engine itself never reads `CLAUDE_PLUGIN_DATA` for generated
state: only the `--data-root` the guard validated may place it.

**Handing the values over up front.** A plugin `UserPromptExpansion` hook matching
`disk-hygiene:clean$` runs `engine_context.py` through the same launcher, with the same
`--plugin-root` argument, when the command expands. It prints the guard's `_display_python()` and
`resolve_authorized_data_root_channel()` results as `additionalContext`, so the skill needs no denied call to
learn them. The note names the channel that supplied the data root (`--authorized-data-root
argument`, `plugin-cache layout`, or `local-directory marketplace install`). It grants nothing: the guard still judges every call, and a hook that fails prints
nothing and leaves the skill on the kill-switch probe, whose `hook_python` and `data_root` fields
come from the guard's `launch_disclosure` for the probe's install root. The note and the skill
belt now share the same three channels, so a `--plugin-dir` session with no marketplace proof
reports `data_root: none` on both sides. Verified 2026-09-27 against https://code.claude.com/docs/en/hooks ("UserPromptExpansion":
typing `/skillname` fires it, it matches on `command_name`, and `additionalContext` reaches Claude
alongside the expanded prompt); recheck when that section changes, or if a release note names the
event. Whether `command_name` carries the leading `/` was not observed, so the matcher admits both.

The hook is the chosen primary delivery path for both values. The one denied bare-python probe in
the no-hook path is an accepted residual: the probe cannot supply `hook_python` to itself.

`--max-depth` accepts only a bare positive-integer literal. `--confirmed-large-scan`, `--quiet`
and `--root-children` are the valueless scan flags; the guard permits at most one of each and
rejects any trailing value, so the scan grammar stays exact.
`--quiet` is admitted because it shapes the engine's stdout only: it reaches no path, and skips no
check, that the same invocation without it would not already reach.

Deriving the data root from `${CLAUDE_PLUGIN_ROOT}` couples to the one undocumented part of that
layout: the `cache/<marketplace>/<name>/<version>` shape of the installation root (the install root
is the version leaf; a directly-linked local install omits it). The guard anchors on the
`<plugins>/cache` marker rather than a fixed depth, taking the marketplace and name from the two
segments after `cache` and reading `data` as `cache`'s sibling, so a version leaf does not shift the
result. That coupling is acceptable only because its sole failure mode is fail-closed: an
unrecognized layout yields no authority, so every engine call is denied while the
destructive-action guard stays fully active. The plugins reference documents all three path
variables (`CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA`/`CLAUDE_PROJECT_DIR`) as exported to hook
processes as environment variables. That page covers plugin `hooks.json` commands; it does not
say whether a skill-frontmatter hook receives `CLAUDE_PLUGIN_DATA` or inherits a launch-shell
export of it. A paid live probe of that question was not run (see the residual below). The
guard therefore never treats the environment variable as a data-root channel: the derivation
from `${CLAUDE_PLUGIN_ROOT}` is the belt that has to hold, and a missing derivation fails closed.

**Local-directory marketplace installs.** A plugin loaded in place from a local-directory
marketplace has a `${CLAUDE_PLUGIN_ROOT}` that is the source checkout, with no `<plugins>/cache`
segment, while its data directory is still `<config>/plugins/data/<id>`. For such a root the guard
reads `<config>/plugins/known_marketplaces.json` and requires exactly one entry whose `source.source`
is `directory` and whose `installLocation` strict-resolves to a directory containing the plugin root.
That marketplace's `.claude-plugin/marketplace.json` must carry the entry's key as its `name` and
exactly one plugin entry whose relative string `source` resolves to the plugin root, with the `name`
`disk-hygiene`, matching the root's own `.claude-plugin/plugin.json`. The id is `disk-hygiene@<key>`,
sanitized as the documented layout does, and the data root is built only from the trusted config dir
plus that id, never from a path read out of either file. The same proof supplies
`<config>/settings.json`, so the kill switch is read on a directory install too. That read passes no
exact `pluginConfigs` key: the user and managed reads match any `disk-hygiene` key, as broad as the
managed read was before, so the channel can only add a deny. This couples to the
undocumented contents of `known_marketplaces.json`, and is acceptable on the same terms as the cache
coupling: its only failure mode is fail-closed, since any unproven step yields no authority.

`<config>` is `<account home>/.claude`, with the home read from the OS account record (the password
database entry for the effective uid on POSIX, the Profile known folder on Windows), never `HOME`,
`USERPROFILE`, `CLAUDE_CONFIG_DIR`, or `Path.home()`. A repo `settings.json` `env` block reaches hook
subprocesses, so an environment-derived anchor would let a repo point the read at a forged
`known_marketplaces.json`. There is no argv or env override, and a user whose `HOME` differs from the
account record fails closed. A config relocated with `CLAUDE_CONFIG_DIR` is still read only from the
account home's `.claude`: it fails closed unless that home file still lists the marketplace, and then
authority stays inside `<home>/.claude/plugins/data/` and the kill switch reads the home settings, no
less restrictive than before.

Data-root precedence, highest first: `--authorized-data-root`, the cache derivation, the
directory-marketplace derivation. There is no environment-variable channel. A repo `env` block
can set `CLAUDE_PLUGIN_DATA`, so treating that value as authority would let repository content
point generated state and the belt's admitted `--data-root` at an attacker-chosen directory.

**User-scope `extraKnownMarketplaces` is declined.** The settings-reference key registers
additional marketplaces "so that people who open the repository, or everyone your managed
settings reach, get the marketplace without adding it themselves"
([extraKnownMarketplaces](https://code.claude.com/docs/en/settings-reference#extraknownmarketplaces)).
Scope is `Any file`. A `directory` source is "for development only". Project-scope entries were
already declined because repository content is hostile to this guard. User-scope is declined too:
the key's documented purpose is repo-or-org registration, and distinguishing user-scope from
project-scope in a skill-frontmatter hook would add a settings-merge parser this belt does not
need. The directory channel stays pinned to harness-written `known_marketplaces.json`.
**Claim:** `extraKnownMarketplaces` is not a trusted directory-marketplace channel for this
guard, at any settings scope. **Basis:** settings-reference `extraKnownMarketplaces` (scope Any
file; purpose "people who open the repository"; `directory` source "for development only"),
fetched 2026-09-28 as `https://code.claude.com/docs/en/settings-reference.md`. **As of:**
2026-09-28. **Recheck:** when that key's scope stops including project files, when a release
note says only the user can write it, or when `known_marketplaces.json` is documented as
derived from it.

The remaining shapes with no derivable authority are a `claude --plugin-dir <checkout>` development
session whose checkout lies outside every registered directory marketplace, and a config relocated
with `CLAUDE_CONFIG_DIR`. Such a `--plugin-dir` checkout has no `<plugins>/cache/<marketplace>`
structure and no marketplace entry, so it has no stable marketplace-keyed data `<id>`. A
`--plugin-dir` root that does sit inside a registered directory marketplace is indistinguishable
from that install and derives the marketplace's canonical data root. `CLAUDE_CONFIG_DIR` itself is never honored, because that would
reopen the env-injection hole, so a relocated config derives nothing from its relocated files (see the
account-home note above). Both fail closed (every engine invocation denied) while the
destructive-action guard itself stays fully active. This is a deliberate safe-over-convenient
tradeoff, not a security gap. The belt's denial names one recovery: run this plugin from a
marketplace install, or register the checkout as a local-directory marketplace
(`claude plugin marketplace add <checkout>`) so a `--plugin-dir` session inside it derives that
marketplace's data root. Setting `CLAUDE_PLUGIN_DATA` in the launch shell is not a recovery: a
paid `claude -p` probe of whether that export reaches a skill-frontmatter hook was not run, and
even if it did the value would be the same repo-injectable channel the belt dropped.
**Claim:** whether a launch-shell `CLAUDE_PLUGIN_DATA` reaches a skill-frontmatter hook is
unmeasured; the recovery hint therefore does not recommend it. **Basis:** decision not to run
the paid probe in #4669; hooks.md says both hook forms export `CLAUDE_PLUGIN_DATA` on the
spawned process (the paragraph on exec and shell form); plugins-reference "Where each
variable resolves" lists hook commands as exporting it and skill/command/agent content as
not applicable, and does not say a launch-shell export survives into a skill-frontmatter
hook. Fetched 2026-09-28 as `https://code.claude.com/docs/en/hooks.md` and
`https://code.claude.com/docs/en/plugins-reference.md`. **As of:** 2026-09-28. **Recheck:**
a live probe with version and platform, or a hooks.md / plugins-reference sentence that
states the skill-frontmatter inheritance.

Verification records for the directory channel:

- **Claim:** a plugin loaded in place from a local-directory marketplace hands its hook processes a
  `CLAUDE_PLUGIN_ROOT` pointing at the source directory. **Basis:** plugins reference,
  [plugin caching and file resolution](https://code.claude.com/docs/en/plugins-reference#plugin-caching-and-file-resolution):
  "For a plugin loaded in place from a local-directory marketplace, ... The plugin's hook processes
  and MCP and LSP servers receive a `CLAUDE_PLUGIN_ROOT` that points at the source directory."
  **As of:** 2026-09-24, Claude Code 2.1.282. **Recheck:** when that page stops carrying the sentence,
  or a release note changes in-place loading.
- **Claim:** the data directory is `~/.claude/plugins/data/{id}/`, `{id}` being the plugin identifier
  with characters outside `[A-Za-z0-9_-]` replaced by `-`. **Basis:** plugins reference,
  [persistent data directory](https://code.claude.com/docs/en/plugins-reference#persistent-data-directory):
  "`{id}` is the plugin identifier with characters outside `a-z`, `A-Z`, `0-9`, `_`, and `-` replaced
  by `-`". **As of:** 2026-09-24, Claude Code 2.1.282. **Recheck:** when that section's id rule
  changes, or a release note names the plugin data directory.
- **Claim:** the docs name `~/.claude/plugins/known_marketplaces.json` only as where marketplace state
  is stored, and `installLocation` only as a field of `claude plugin marketplace list --json` output;
  the file's contents are undocumented. **Basis:** raw-markdown fetches of the plugins reference (no
  mention) and
  [plugin marketplaces](https://code.claude.com/docs/en/plugin-marketplaces) ("Marketplace state is
  stored once per user in `~/.claude/plugins/known_marketplaces.json`, not per project"; "an
  `installLocation` field with the local cache path where the marketplace is stored"). The absence
  covers those two pages only. **As of:** 2026-09-24, Claude Code 2.1.282. **Recheck:** when either
  page documents the file's contents, or a release note names `known_marketplaces.json`.

The same guard also covers the PowerShell tool with the inverse tradeoff: PowerShell stays open for
read-only support work, while engine invocations are hard-denied (Bash is the only engine lane) and
known deletion spellings and .NET Delete calls resolve against the `disk_hygiene_enabled` kill
switch. When the guard sees execution enabled they are downgraded to a hook-issued `ask`;
when it sees a configured `false` (audit-only mode) they are denied outright, so the kill switch would
block deletions on the PowerShell lane too and not only the Bash engine apply.

The flagged set is not deletion-shaped only. It also covers destructive
**non-deletion** spellings: `Move-Item`/`mv`/`move`, `Rename-Item`/`ren`/`rename`, the overwriting
writers (`Set-Content`, `Out-File`, `Add-Content`, `New-Item -Force`, and both `>` file redirection
and `>>` append, with PowerShell's stream merges and `$null` discards excluded),
and the volume operations (`Format-Volume`, `Clear-Disk`, `Initialize-Disk`), alongside `robocopy`
mirror/purge/move and .NET `Delete`. Each resolves against the kill switch on the same terms as a
deletion spelling: `ask` when execution is enabled, denied outright in audit-only.

Because the lane still **enumerates** spellings rather than denying unknown commands, its coverage
remains knowingly partial: a raised bar, not a fail-closed lane. Concrete residuals: the
module-qualified form (`Module\Cmdlet`) is covered only for `Remove-Item`, `Clear-Content`, and
`Clear-RecycleBin`, so a module-qualified `Move-Item` passes; the .NET pattern matches `Delete`
alone, so writer and mover calls such as `[System.IO.File]::WriteAllText` or `::Move` pass; and any
spelling nobody enumerated passes. For anything that passes, the only thing standing between it and
the filesystem is the consumer's own permission policy, never this guard. The manual handoff's
per-path approval covers the paths selected for removal, so it does not reach what such a command
collaterally destroys: a `Move-Item -Force` destination, a truncated `Out-File` target, or an entire
volume. The engine's own containment, revalidation, and platform gates remain the deletion
authority, except inside the [opt-in elevated script](#opt-in-elevation).

**Kill-switch enforcement: both surfaces resolve it by reading user settings.** The guard
registers on two surfaces, the **plugin-level engine gate** (`hooks/hooks.json`, exec form:
`node`, then `hooks/exec-bash.mjs`, then `hooks/run-python-hook.sh`, `--mode engine-gate`; see
"Hook launch form" below) and the
**skill-frontmatter belt** (the clean skill's frontmatter hook, the same entry),
and both
resolve `disk_hygiene_enabled` the same single way: by reading it from `pluginConfigs` in the
`settings.json` files, through the shared `lib/killswitch_config.py` reader (the same read the setup
skill's `kill_switch_probe.py` reports). Neither surface takes the value from the process environment.
Claude Code honors that key only from user, managed, and `--settings` scope since 2.1.207, and a project or
local `.claude/settings.json` is ignored, so a hostile repo cannot flip it. That scoping is verified
2026-09-06 against Claude Code 2.1.263 and the plugins reference at
`https://code.claude.com/docs/en/plugins-reference`, which states that Claude Code reads all
`pluginConfigs` values from only user settings, `--settings`, and managed settings, that entries in a
project's `.claude/settings.json` or `.claude/settings.local.json` are ignored, and that those entries
were read before v2.1.207. Recheck when that page stops carrying the ignored-project-scope statement, or
when a release note names `pluginConfigs` scope. The **user** file is located
from `${CLAUDE_PLUGIN_ROOT}` (the plugin's true install path, which a repo cannot forge): the
`plugins/cache` layout's sibling `settings.json`, or for a local-directory marketplace install
`<config>/settings.json` under the account-record config dir above. It is **never** located
from `CLAUDE_CONFIG_DIR`/`HOME`, which a repo `settings.json` `env` block could inject. A root that
proves neither (a `--plugin-dir` checkout, or a `CLAUDE_CONFIG_DIR`-relocated config whose account
home no longer lists the marketplace) yields no trusted
user-settings path, so the user scope is skipped there and the switch relies on managed settings, failing
closed to enabled otherwise. The **managed**
(enterprise) file at its fixed root-owned system path is read too and, as the highest-precedence
non-overridable scope, an explicitly configured value there **wins over the user file**, so an
organization can enforce audit-only mode; the sibling `managed-settings.d/` drop-in directory is merged
over it (later files win). The one honored source the guard cannot read is a session's `--settings` file
(a runtime CLI flag no hook observes); a value supplied only there is not enforced. When the value
resolves `false` (audit-only mode), `false` is guard-enforced as an outright deny with no prompt fallback, but
the two surfaces reach different lanes. The **always-on engine gate** enforces it against every Bash
engine invocation **whether or not the clean skill is active**; it defers (no output) on any command that
does not reference the engine, so it does **not** see PowerShell deletion spellings. Those are enforced by
the **skill-frontmatter belt** (`powershell_decision`), denied outright in audit-only, for the **rest of
the session after the skill is invoked**. Claude Code registers a skill's frontmatter `PreToolUse` hooks
when the skill is invoked and keeps them registered session-wide; the skills reference states it plainly
("Hooks that Claude Code registers when the skill is invoked and keeps running for the rest of the
session"). There is no harness-level "while the skill is active" window for hooks. The asymmetry
is easy to misread and is worth naming: a skill's `allowed-tools` and `disallowed-tools` grants DO clear
on the user's next message, but its `hooks` do not, so "skill-scoped" is true of the tool grants and
false of the belt. Consequences in both directions: the belt keeps enforcing over unrelated later work in
the same session (a later `Remove-Item` is still prompted long after cleanup ended), and it cannot be
retracted by finishing the cleanup. Only the session's end clears it.
An absent, unreadable, or ambiguous read fails **closed to enabled**: the guard stays
active and forces a human prompt before every mutation **it sees**, meaning every Bash engine `apply`
and, on PowerShell, only the flagged spellings above, so an unreadable toggle never silently disables
the guard.

**The gate's "different file" escape stops at this plugin's own cache tree.** A word naming an existing
file that is not the bundled engine defers, so a consumer's own `tools/hygiene.py` is not mistaken for
this engine. Claude Code keeps a replaced version's directory on disk after an update,
so that escape also covered every previous version of *this* engine sitting beside the current one,
each a genuinely different file, each deletion-capable, and each answering to nothing but its own
containment once the always-on gate defers. The gate now refuses that escape to any path resolving
inside `<plugins>/cache/<marketplace>/<name>`, derived from the guard module's own `__file__` rather
than from argv, so no environment channel can redirect it. A `--plugin-dir` checkout, or a plugin
loaded in place from a local-directory marketplace, has no such prefix and the narrowing is inert
there, which is correct: a checkout has no cached siblings, and
narrowing on it would gate a contributor's work on their own tree. **Residual:** versions at or below
0.8.1 predate settings-based kill-switch enforcement entirely, and a copied engine, rather than a
cache-resident one, remains outside the prefix, as it is outside every identity check the gate
makes.

The gate must never carry a bare `${user_config.disk_hygiene_enabled}` argument. The declared
userConfig `default` is not implemented upstream (#46477 / #39455 / #39827), so an
unset-but-defaulted token is neither substituted nor exported as `CLAUDE_PLUGIN_OPTION_*`, and
its presence **drops the whole engine-gate hook**: on a default install the gate would never run
at all. Reading settings directly needs no `default` substitution. **Recheck** the tamper and
scoping premises against the dated `pluginConfigs` record under "Kill-switch enforcement" above.

PreToolUse hooks with a `Bash|PowerShell` matcher fire for the PowerShell tool (payload
`tool_name` is literally `PowerShell`, confirmed by a live block through that tool); there is no harness
firing divergence. That firing is verified 2026-09-06 against Claude Code 2.1.263 and the hooks reference
at `https://code.claude.com/docs/en/hooks`, whose matcher table says a `PreToolUse` matcher filters on
tool name and whose Windows example uses that exact `Bash|PowerShell` matcher. Recheck when that page
drops the example, or when a release note names hook matchers. Read `tool_name` from the stdin payload,
never from an env var. `CLAUDE_TOOL_NAME`
does not exist. Where both surfaces see the same command their verdicts are idempotent. The gate defers
instantly (no output) for any command that does not reference the
engine, so it never taxes unrelated work; its coverage marker is the engine script name, a belt against
casual invocation, not an authority (renaming the script evades the gate but not the engine's own
preview/approval-token containment). The model additionally reads the `disk_hygiene_enabled` value from
the skill content and self-enforces audit-only, now defense-in-depth over the guard rather than the only path.
Even when the switch resolves enabled, the PowerShell lane is a raised bar, not fail-closed: an unknown
mutation spelling passes it, so the engine's own containment, revalidation, and platform gates remain the
deletion authority, except inside the [opt-in elevated script](#opt-in-elevation).

**Hook launch form, and what it does and does not bound.** All three registrations use **exec form**:
the engine gate on `PreToolUse`, its detector on `Stop`, and the skill-frontmatter belt in the clean
skill's frontmatter. In each, `command` is `node` and `args` names `hooks/exec-bash.mjs`, then
`hooks/run-python-hook.sh` and that script's arguments. Bare `"command": "bash"` resolves to the WSL
relay `System32\bash.exe` and `"command": "python3"` resolves to the zero-length `WindowsApps` stub,
so those spellings are not used: the launch would die and, a failed hook launch being non-blocking,
the guard would silently enforce nothing. There is no shell in exec form. The bound is that `args`
are fixed literals in the plugin's own `hooks.json` or SKILL.md frontmatter, with no model-, repo-,
or session-supplied text interpolated into them. Claude Code substitutes `${CLAUDE_PLUGIN_ROOT}` and,
on a plugin hook, `${CLAUDE_PLUGIN_DATA}` as plain strings before spawn. The belt's bound is the
tighter of the two: a skill-frontmatter hook receives only `${CLAUDE_PLUGIN_ROOT}`, so that is the
sole placeholder its `args` carry and the `--authorized-data-root` channel stays out of it.
`hooks/run-python-hook.test.sh` asserts the `hooks.json` shape. `test_hygiene.py` asserts the belt.

**Guard launch/runtime failures are surfaced, not silently indistinguishable from approval.** A
`PreToolUse` hook that fails to launch, or launches and then exits non-zero, denies
nothing, because Claude Code treats a non-blocking hook result as approval, so "the guard denied nothing because
it approved" and "the guard denied nothing because it never ran, or ran and silently died" looked
identical from outside the harness. `skills/clean/scripts/guard_launch_monitor.py` closes that gap with a
second, independent hook registered on `Stop` in `hooks/hooks.json` (deliberately not `PreToolUse`, so
it does not tax every guarded tool call): it scans the session
transcript's tail for `hook_non_blocking_error` records whose command string names
`destructive_guard.py`, and if it finds any, emits a `systemMessage`, never a block and never a
`permissionDecision`, naming the guard, the total failure count, and the most recent failure's exit
code, duration, and truncated stderr, at most once per session. It is a separate, stdlib-only process
that imports nothing from the guard: a guard that cannot launch cannot report that it did not launch, so
the detector cannot depend on the guard's own code path, and it fails silently closed (exit 0, no output)
on any transcript-read or parse error so it can never itself become the reason a turn is blocked. What
this does **not** cover: repo-hygiene ships its own, structurally different guard, verified working
independently and out of scope here; the detector's command-substring filter matches only
`destructive_guard.py` invocations, so a renamed or unrelated guard script is invisible to it the same
way it is invisible to the engine gate's own coverage marker (see above); and it never retroactively
scans a prior session's transcript, reading only the transcript named by the current `Stop` event's own
`transcript_path`. Interpreter resolution is not one of those gaps: every surface, the wired hooks and the
skill-frontmatter belt alike, launches through the shared `hooks/run-python-hook.sh`, which
tries `python3`, then `python`, then `py -3`, rejects the zero-length `WindowsApps` alias stub, and,
in monitor mode, emits the `systemMessage` itself when nothing resolves, so a host with no usable
Python reports the blind spot instead of hiding it. What every surface still shares is that launcher
and the bash that `hooks/exec-bash.mjs` starts: all are exec form with `"command": "node"`, so a
host where `node` is missing, or where that launcher resolves no bash, takes the guard and
its detector down together with nothing left to report it. When the shell starts but no Python resolves, the launcher answers for the
guard on the call itself (#3861), mirroring the watchdog's "could not decide" rule: the belt denies
every call (exit 2), the engine gate denies any payload naming `hygiene.py` or carrying nothing, and
the `/disk-hygiene:clean` expansion is blocked so the belt never loads. The engine gate's
marker-free commands differ from the watchdog: they proceed unchecked with a once-per-session
`systemMessage` and `additionalContext` notice rather than an `ask`. The Stop detector is kept as the end-of-turn
backstop. Verified 2026-09-28 against Claude Code 2.1.280 at
<https://code.claude.com/docs/en/hooks> (exit 2 blocks a PreToolUse call whatever stdout carries;
exit 0 with no `permissionDecision` proceeds through the normal permission flow; a hook `ask` forces
a prompt even in auto mode) and <https://code.claude.com/docs/en/headless> (a prompt in a `-p` run
with no permission host is denied); recheck when either page changes PreToolUse exit-code or `ask`
semantics. The README states each surface in one table. The launch shape is asserted by
`hooks/run-python-hook.test.sh` and `test_hygiene.py`, the no-interpreter posture by the former, and
both are verified as step 1 of `/disk-hygiene:setup check`.

A depth-limited scan records every directory it declined to enter in `truncated_paths`. Truncated
directories have no captured descendant set, so the preview blocks them (and anything beneath them)
as `truncated-not-inventoried`; they are coverage gaps, never candidates.

`children_rollup` states that same coverage per immediate child of the target, so a gap is visible
against the child an operator actually reasons about rather than only in a flat path list. Every
immediate child the run covered gets exactly one row, whatever that row's coverage. Omission would
read as absence. (In `--root-children` mode the run covers the SELECTED children only: an unselected
sibling is never opened, never inventoried, and owes no row. `root_children_selected` in the same
payload names what was in scope.)

| Field | Meaning |
|---|---|
| `name` | The immediate child's own name (never a path) |
| `kind` | The entry kind the walk recorded, one of `directory`, `file`, `link`, `other`, or `null` when no inventory record survived |
| `walked` | `true` only when the child's whole subtree was inventoried |
| `logical_bytes` | Recursive LOGICAL total, qualifiers included; `null` unless `walked` |
| `reclaimable_local_bytes` | Recursive total over unqualified files only, the bytes deleting the child is expected to return locally; `null` unless `walked` |
| `size_qualifiers` | Union of the qualifiers observed in the subtree (`cloud-placeholder`, `hardlinked`, `sparse`, …); `null` unless `walked` |
| `entry_count` | Inventoried descendants, excluding the child's own record; `null` unless `walked` |
| `newest_mtime_ns` | Newest `mtime_ns` across the child and its inventoried descendants; `null` unless `walked` |
| `unwalked_reasons` | Sorted causes when `walked` is false: `depth-cut`, `protected`, `vcs-boundary`, `scan-error`, `descendant-not-walked`, or the bare `not-walked` fallback when the walk recorded no more specific cause. Empty when `walked` |

`walked` is the single discriminator, and every aggregate moves with it: all exact, or all `null`.
Two failure modes are closed by construction. A partial subtree sum is never presented as a child's
total. A child that was itself entered but holds an unwalked descendant is `descendant-not-walked`,
`null`. And `null` never degrades to `0`, because `0` is the genuine "this child is empty" answer
that keeps zero-byte residue first-class.

**That first case is a gap the flat entry list does not state, which is the sharpest reason to read
the roll-up.** A directory's own record gets the `not-walked` qualifier only from ITS OWN branch:
a VCS boundary, protection, a depth cut, or its own `scandir` failure. It is never propagated up from a
descendant, and only `target_identity` is special-cased to append it whenever anything truncated. So
an intermediate child holding an unwalked descendant keeps `walked: true`, an empty
`size_qualifiers`, and a `logical_size` that is a PARTIAL sum indistinguishable from a complete one:
a target holding `repo_child/.git` (a VCS boundary) plus `repo_child/src.py` records
`repo_child` at `logical_size: 10`, `size_qualifiers: []`, with only `repo_child/.git` in
`truncated_paths`. The roll-up is what makes that gap legible per child, since it draws
`descendant-not-walked` from the walk's coverage record rather than from the child's own qualifier,
so never read a directory's `logical_size` as a total without checking whether anything beneath it
is in `truncated_paths`.

The third failure mode, a byte figure that overstates what deleting would return, is closed by
pairing, not by omission. `logical_bytes` is a logical total, so a cloud placeholder's REMOTE size, a
hard link's shared object, and a sparse file's unallocated extent all inflate it; `size_qualifiers`
says which of those are present in the subtree and `reclaimable_local_bytes` counts only unqualified
files, exactly as `target_reclaimable_local_bytes` does for the target. Rank a child on the
reclaimable figure and state the qualified bytes separately with their reasons. Never read
`logical_bytes` as space a delete would give back. A `link` child is the limiting case: it reads
`logical_bytes: 0` because the walk never traverses a link, and 0 is the honest figure for deleting
the link itself, whatever the target holds.

The roll-up is assembled from what the walk already recorded: it opens no directory and stats no
path, so it cannot turn a bounded pass into an unbounded one. The engine's test suite holds that
line by counting `os.scandir`, its only directory-enumeration route, on a bounded pass with and
without the roll-up. The cost of that guarantee is the honest limit an operator has to read the
block with: under `--max-depth 1` a recursive total for a
NON-EMPTY child is not knowable without walking it, so every such child reads `depth-cut` and
`null`. The bounded pass delivers the complete frontier, per-child coverage, and exact numbers for
loose files and empty children; a per-child total is bought by fanning a deeper scan out over that
subtree.

The roll-up is written to the snapshot file on every run, so `scan --quiet` omits it from stdout.
The two copies are otherwise identical, and the snapshot is the copy the engine treats as the
record: the flag drops a duplicate, never data. Quiet output keeps `snapshot`, `status`, `target`,
the three coverage terms, `empty_directory_count`, `empty_file_count`, both byte totals, `errors`, `policy_sources`,
`elevation` and `os_autoclean`, so every field a keep-or-review decision rests on survives, and it replaces the
closing note with a short one naming where the rows went. It prints `truncated_paths` as the number
of truncated paths, not the list: a depth-2 home scan truncated about 140, which is most of what the
flag exists to avoid. The count is printed even at zero, so a clean scan reads differently from a
suppressed list, and the snapshot keeps the list for the preview and for reporting the gaps. That field set holds in `--root-children` mode too, which reports
`empty_directory_count` and `empty_file_count` on stdout for the same reason an ordinary scan does. The default stays the
full payload: a caller already parsing `children_rollup` off stdout must not be quietened by an
upgrade.

Root-children mode's quiet note is its own. That mode's default note carries a coverage
qualification the ordinary one has no reason to: the volume root itself and every skipped
OS-owned, hidden, system or reparse entry were never walked, so the inventory is partial by
construction. Nothing else on stdout encodes that. The skipped entries are recorded as
`root_children_skipped` in the snapshot as the full list (stdout carries the same field grouped by
reason with counts), and `truncated_paths` does not stand in for them,
so a quiet note that dropped the qualification would be dropping a fact rather than a duplicate.
The quiet root-children note therefore keeps the coverage sentence and drops only the rollup
prose.

The `scan-complete` summary reports hint coverage in three terms: `entries`, `hinted_entries`, and
`unhinted_entries` (`entries` minus `hinted_entries`). The third is what makes the first two
readable: without a denominator for what no hint judged, a run that annotated 7 of 40,247 entries is
indistinguishable from a thorough one.

A scan of a known-large root, the user home directory or a non-OS volume root (a Windows Dev
Drive), is gated before it walks.
Absent an explicit `--max-depth` bound or a `--confirmed-large-scan` acknowledgement, the engine
performs a cheap top-level probe and returns `large-target-confirmation-required` instead of the
unbounded traversal, so an unauthenticated whole-volume walk cannot begin by omission. This is
scan-cost gating (time and resources), distinct from the hard rejection of an OS-managed root as an
invalid target.

`--sizes-only`, as implemented, bypasses that gate. It does not ask the large-scan question, does
not stop at VCS or protected directories (it sums through them, read-only, and emits no entries),
and has no entry cap. Its snapshot is refused by disposition.

Managed state is engine-ineligible. Even current native dry-run evidence is recorded only as a
report-only handoff because this engine cannot independently authenticate the owning product's state
or cleanup contract.

The baseline policy therefore ships no discovery hint for another product's managed state. A hint
for a class the engine will never act on tells the operator to look for residue the plugin has
already decided to hand off. For that reason the `.pulumi-write-test-*` hint was removed (#3860)
rather than exempted. Residue inside a managed directory is reported as a handoff to its owner, and
any gated lane for it is tracked separately (#4006). Do not re-add a baseline hint for managed state
without that lane.

## Opt-in elevation

The version 2 overlay field `elevation` is `never` by default, and the `scan-complete` output
reports the effective value beside `policy_sources`. With `never`, the skill never elevates or
triggers UAC or sudo. `uac-prompt` opens one narrow lane on Windows, inside the
[unsupported-platform handoff](unsupported-platform-handoff.md). It covers a path in the approved
tier whose per-path `handoff-verify` returns `contested` with `needs-elevation` as its only reason.
For those paths the skill writes an elevated PowerShell script under the run directory, shows the
operator its full contents, launches it with `Start-Process -Verb RunAs -Wait` so it waits behind the
UAC prompt the operator approves, and reads the per-path results back from a log file the script
writes.
**Claim:** `-Verb RunAs` starts the process through the Run as administrator option, `-Verb` does
not apply off Windows, and `-Wait` returns only after the process and all its descendants exit.
**Basis:**
[Start-Process](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process)
(Example 5; the `-Verb` and `-Wait` parameters; Notes). **As of:** 2026-09-29, PowerShell 7.6 page
dated 2026-07-06. **Recheck:** when that page changes `-Verb` or `-Wait` semantics.

The lane never runs on Linux or macOS (no sudo there), never for a protected entry or any other
contest reason, never without the per-tier approval, and never for a preview-time `needs-elevation`
blocker: that preview is `blocked` and still stops the tier. The script never invokes the engine,
because engine invocations stay on the Bash lane's exact shapes. It re-checks each path natively
before removing it: the path is still present, is not a reparse point, has the identity the
snapshot recorded (volume and file ID), and holds no entry the snapshot did not record, and an
exclusive-open probe finds no live handle, where a sharing violation skips the path as `locked`.
The Windows handle probe itself reports an access-denied open as `needs-elevation`, so a
`needs-elevation`-only verdict can mean the handle check is the one that failed; the elevated
re-check must repeat it, and skips any path it cannot re-prove. The manual lane's other rules still apply: one path at a time, no
container-wide deletion, and a fresh approval for a permanent fallback.

Only the user-global file or an explicit `--policy` can set `uac-prompt`. A project file lives in a
repository the operator may not control, so the loader rejects `uac-prompt` there and accepts only
`never`. When layers disagree, the last layer that sets the field wins.

**What the guard does not see.** Neither guard surface denies the launch. The engine gate fires only
on commands that name the engine, and the belt's PowerShell lane flags deletion spellings on the
command line. `Start-Process -Verb RunAs` carries none, and the deletions live inside the script
file. So the kill switch does not block this lane: offer it only when the kill-switch probe reports
execution enabled. Nothing checks the script against the approved list except the operator, who
reads the script's contents and then answers the UAC prompt. Making the belt `ask` or deny
`-Verb RunAs` would be a guard change and stays with the owner.

**Unverified.** No Windows UAC pilot has run this lane. Until the operator runs one, treat it as
documented intent, not observed behavior.

## Outcome vocabulary

| Outcome | Meaning | Next action |
|---|---|---|
| `locked` | A current handle was observed | Close the owning application yourself, rescan |
| `changed-or-link` | Identity changed or a link appeared | Keep; investigate and rescan |
| `protected` | Hard or consumer protection matched | Keep |
| `needs-elevation` | Access could not be proven without greater privilege | Defer to a human-run elevated workflow, or on Windows with `elevation: uac-prompt`, the [opt-in elevated script](#opt-in-elevation) |
| `handle-state-unverified` | Handle tool/authority/timeout prevented proof | Keep; install/configure the declared verifier if desired |
| `delete-failed` | Final OS operation failed after preflight | Keep remaining content; inspect the reported error |

## Primary references

Verified 2026-07-16: [Claude skills](https://code.claude.com/docs/en/skills),
[PreToolUse hooks](https://code.claude.com/docs/en/hooks),
[GNU Bash shell expansions](https://www.gnu.org/software/bash/manual/html_node/Shell-Expansions.html),
[Python 3.11 `os`](https://docs.python.org/3.11/library/os.html),
[Python 3.11 `os.path`](https://docs.python.org/3.11/library/os.path.html),
[Git `ls-files`](https://git-scm.com/docs/git-ls-files),
[Windows `CreateFile`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-createfilew),
[Windows reparse points](https://learn.microsoft.com/en-us/windows/win32/fileio/reparse-point-operations),
[`GetLogicalDrives`](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getlogicaldrives),
[Linux `mountinfo`](https://man7.org/linux/man-pages/man5/proc_pid_mountinfo.5.html),
[`lsof`](https://lsof.readthedocs.io/en/stable/), and
[Linux `unlink(2)`](https://man7.org/linux/man-pages/man2/unlink.2.html).
