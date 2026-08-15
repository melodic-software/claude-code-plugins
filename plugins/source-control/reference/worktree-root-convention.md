# Worktree root convention — `melodic.worktreeroot`

Owner doc for the fleet's worktree-placement convention (#2610, #2612). The
machine truth is a **git config key**, so the convention is readable by
anything that can run `git config --get` — humans, scripts, CI, and every
agent, not just this plugin. Prose surfaces (a repository's `AGENTS.md` /
`CLAUDE.md`, skill text) should **cite this key, never copy the path**:
restating the path in several places is exactly the drift the fleet
measurement in #2610 found on disk (292 linked worktrees across ten
conventions, zero at the configured root).

## The key

```ini
[melodic]
  worktreeroot = ~/worktrees
```

- **Name:** `melodic.worktreeroot`. Deliberately NOT under `worktree.*` — git
  owns that namespace (`worktree.guessRemote`, `worktree.useRelativePaths`,
  and 2.56 extends `includeIf` into `worktree:` conditions). `melodic.*`
  collides with nothing; the vendor-section pattern matches `ghq.root`,
  `git-town.*`, and git-wt's `wt.basedir`, all of which store placement in
  git config.
- **Type:** path (read with `--type=path`, which expands a leading `~`).
- **Multi-valued, last value wins** — an include can *append* rather than
  override, which is what makes the `includeIf` layering below work.
- **Value:** a directory OUTSIDE every repository, and outside
  repository-discovery roots such as a ghq root (`ghq list` enumerates each
  worktree there as a repository of its own; a leading dot does not hide it).
  On Windows, the same drive as the repositories it serves.

## Reading it (any consumer)

```sh
git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || exit  # mandatory gate
root=$(git -C "$repo" config --get-all --type=path melodic.worktreeroot | tail -n 1)
```

Two hazards, both verified on git 2.55 in #2610 and both silent:

- **Never pass a scope flag without `--includes`.** Per git-config(1),
  `--includes` defaults OFF "when a specific file is given (e.g., using
  `--file`, `--global`, etc)" and ON when searching all config files. A
  scoped read silently skips every `includeIf` — the whole per-identity
  layer.
- **Gate on `rev-parse --git-dir` first.** Under dubious ownership
  (`safe.directory`), `git -C <repo> config --get <key>` returns the GLOBAL
  value as though it were the repository's answer — rc=0, no stderr, and
  `--show-scope` reports `global`.

## Resolution order in this plugin

`scripts/worktree-create.sh` (shared by the `/worktree create` skill and the
`WorktreeCreate` hook) resolves the root most specific first:

1. Explicit `--root` / `--root-file` — a per-invocation caller decision.
2. **`melodic.worktreeroot`**, read from the *target repository* with
   includes on. `includeIf` supplies per-identity and per-repository answers
   with no new machinery (below).
3. `--fallback-root` / `--fallback-root-file` — the machine-global
   `worktree_root` **plugin option**, ranked below the key because only this
   plugin can read the option while every consumer can read the key.
4. The plugin data directory (`--data-root-file` → `<data-dir>/worktrees`).
5. Absent all: refuse (exit 3). Never the in-repo `.claude/worktrees/` —
   [the nesting invariant](../skills/worktree/SKILL.md#the-nesting-invariant-verified)
   owns that claim.

Whatever rung supplies the root, the helper's containment guard then rejects
a root that itself resolves inside a working tree or a git directory — a
misconfigured key is a refusal, not a licensed nesting.

Enforcement seams: `hooks/worktree-create-gate.sh` (harness-driven
creations) and `hooks/worktree-add-containment-gate.sh` (a raw Bash
`git worktree add` targeting a path inside a repository, #2611).
`EnterWorktree(name:)` is not a Bash call and lands in the in-repo default;
the skill is contractually forbidden from calling the name form, and
harness-driven creation is covered by the `WorktreeCreate` hook — that pair
is the documented handling of the `EnterWorktree(name:)` gap.

## Per-identity and per-repository roots (#2612)

One machine, several git identities: resolve the root through git's own
conditional configuration. Parse order IS precedence (see hazards), so the
machine default goes first and each more-specific include after it:

```ini
[user]
  name = <name>
  useConfigOnly = true            # NO user.email here — see hazards
[melodic]
  worktreeroot = <machine-default>  # plain default FIRST — below an includeIf it would win

[includeIf "gitdir/i:<work-tree-root>/"]
  path = ~/.config/git/identity-work.inc
[includeIf "gitdir/i:<personal-tree-root>/"]
  path = ~/.config/git/identity-personal.inc

[includeIf "gitdir/i:**/dotfiles/.git"]      # per-repo exception, survives re-clone
  path = ~/.config/git/repo-dotfiles.inc
```

Each `.inc` sets `melodic.worktreeroot` (appending after the default, so
last-wins picks it up) alongside the identity keys. Verified properties
(hermetic lab, git 2.55, #2612):

- `includeIf` splices whole files and is not key-aware, so a custom key
  resolves exactly as `user.email` does.
- `git -C` chdirs before repository discovery: the condition evaluates
  against the **target repository's gitdir, never the cwd**, so a fleet tool
  iterating repositories from elsewhere gets correct answers.
- **Linked worktrees classify with their repository**: a worktree's
  `$GIT_DIR` is always under its main repository, so a tree-anchored
  `gitdir:` gives every worktree of a repository the same answer. Corollary:
  a pattern anchored at a worktree's own tree path matches nothing, ever —
  that presents as "includeIf is broken", and it is the likely first
  misdiagnosis.

### Hazards (all fail silently — rc=0, zero stderr)

- **Use `gitdir/i:` for the identity layer, not `hasconfig:`.** libgit2
  clients (gitui, TortoiseGit, git2/nodegit/pygit2) implement `gitdir:`,
  `gitdir/i:`, `onbranch:` but NOT `hasconfig:` — and fail unrecognized
  conditions silently; JGit and go-git resolve no `includeIf` at all.
  `hasconfig:` is fine for `melodic.*`, which only CLI-shelling tools read.
- **`gitdir:` is case-sensitive even on case-insensitive NTFS.** Only the
  pattern author's spelling matters. Always `gitdir/i:` on Windows.
- **Precedence is parse order, not specificity.** A plain
  `[melodic] worktreeroot` *below* the `includeIf` block silently overrides
  every identity include. Two matching conditions: last parsed wins.
- **Attribution needs `--show-origin`.** `--show-scope` collapses a
  conditionally-included file to `global`.
- **Junction-anchored patterns match nothing** in either direction
  (contradicting the manpage's symlink claim). Anchor patterns at canonical
  target paths.
- **Bare repositories have no `/.git` suffix**, so `**/<name>/.git` patterns
  silently miss them.
- **Per-repo exceptions belong in a name-keyed global include, not
  `.git/config`** — repo-local config is not cloned, so the exception
  vanishes on re-clone (twice, for a dotfiles repo with two peer clones).
- **Version floors:** `gitdir:`/`gitdir/i:` 2.13, `onbranch:` 2.23,
  `hasconfig:remote.*.url:` 2.36, `worktree:`/`worktree/i:` **2.56** — a
  config authored for 2.56 degrades silently on 2.55.
- **Per-worktree overrides need `config.worktree`** behind
  `extensions.worktreeConfig` — no `gitdir:` pattern can distinguish two
  worktrees of one repository.
- **Identity includes must set more than `user.email`** — `user.signingkey`,
  `gpg.ssh.allowedSignersFile`, `core.sshCommand`, and `url.*.insteadOf` all
  leak from global otherwise, and a wrong SSH signing key **verifies Good
  locally** (git derives the principal from the signature; only the forge
  shows Unverified). `user.useConfigOnly` is inert if a global `user.email`
  exists.

## Doctor

`scripts/worktree-root-doctor.sh [--repo-dir <dir>]` makes the silent
failure classes loud and names **which rule** supplied the repository's root
(`--show-origin`, mapped back to its `includeIf` condition). It checks:
dubious-ownership / non-repository fallback, declared-but-unfired
conditions, include paths pointing at nonexistent files, unrecognized or
version-floor-gated condition keywords, `gitdir:` without `/i` on Windows, a
plain value parsed after an include-supplied one, scoped-read divergence, a
root that itself sits inside a repository, and identity partials
(`user.email` without `user.signingkey` where signing is configured). Exit 0
clean, 1 with findings. `/source-control:worktree audit` runs it as part of
its configuration-health step.

## For consuming repositories' prose surfaces

Add a pointer, not a path, e.g.:

> Worktrees live under the root named by
> `git config --get-all --type=path melodic.worktreeroot | tail -n 1`
> (never scope the read without `--includes`; gate on `rev-parse --git-dir`
> first). Convention: the source-control plugin's
> `reference/worktree-root-convention.md`.
