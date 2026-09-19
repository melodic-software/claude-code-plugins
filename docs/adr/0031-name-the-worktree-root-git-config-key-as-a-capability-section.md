# Name the worktree-root git config key as a capability section

- Status: accepted
- Date: 2026-09-08

## Context

`melodic.worktreeroot` is the shipped machine-truth for worktree placement
(readable by any `git config --get` consumer). Design boundary forbids
publisher names in runtime behavior and in shipped skill content. The two
were decided in separate passes and never reconciled.

Issue #3345 asked for one of two rulings: rename to a neutral section, or
keep `melodic.*` and narrow the rule. The publisher name is the defect: a
consumer outside this organization must not write `melodic.*` into their
own git config. This record picks the replacement from official Git
documentation and from the keys popular git-related tools actually ship.

## Decision

Keep a git config vendor section — that is Git's documented idiom — and
name it after the **capability**, not the publisher and not this
marketplace's plugin:

`worktreeroot.path`

```ini
[worktreeroot]
  path = ~/worktrees
```

Publisher-named git config keys remain an org-agnosticism defect. This
ruling does not bind `MELODIC_*` environment variables, marketplace ids, or
organization names in skill content.

## Evidence

**Git invites third-party keys, and requires collision-freedom plus
documentation — not org-neutrality, not reverse-DNS.**

git-config(1) Variables: "Other git-related tools may and do use their own
variables. When inventing new variables for use in your own tool, make sure
their names do not conflict with those that are used by Git itself and
other popular tools, and describe them in your documentation."

- Claim: third-party git config variables are a documented Git idiom whose
  constraints are collision-freedom and documentation.
- Basis: [git-config(1) Variables](https://git-scm.com/docs/git-config#_variables),
  the paragraph that opens the variable list.
- As-of: 2026-09-08.
- Recheck trigger: that paragraph being rewritten.

**Git already owns `worktree.*`.** A placement key cannot live there.

git-worktree(1) Configuration documents `worktree.guessRemote` and
`worktree.useRelativePaths`. `includeIf "worktree:"` / `"worktree/i:"`
conditions are on git.git `seen` and appear in some git-config(1) mirrors;
they are a further reason not to occupy the `worktree` section, not a
requirement that already-shipped Git 2.55 expose them.

- Claim: `worktree.*` is Git's namespace.
- Basis: [git-worktree(1) Configuration](https://git-scm.com/docs/git-worktree#_configuration).
- As-of: 2026-09-08.
- Recheck trigger: git-config(1) adding a new `worktree.*` key.

**Popular git-related tools name the section after the tool, not the
publisher.**

| Tool | Key | Source |
|---|---|---|
| ghq | `ghq.root` | [ghq(1)](https://github.com/x-motemen/ghq) Configuration |
| Git Town | `git-town.*` | [Git Town configuration commands](https://www.git-town.com/configuration-commands.html) (`git config --get-regexp git-town`) |
| Git LFS | `lfs.*` | [git-lfs-config(5)](https://github.com/git-lfs/git-lfs/blob/main/docs/man/git-lfs-config.adoc) |
| git-wt | `wt.basedir` | [k1LoW/git-wt README](https://github.com/k1LoW/git-wt) |
| delta | `delta.*` | [dandavison/delta README](https://github.com/dandavison/delta) |
| hub | `hub.protocol` | [hub(1)](https://github.com/github/hub/blob/master/share/man/man1/hub.1.md) |

None of those sections is the author's organization. The Freedesktop
reverse-DNS rule (`org.example.FooViewer`) is a different ecosystem
(Desktop Entry Spec / D-Bus) and is not Git's rule.

**`worktreeroot.path` is the collision-free capability spelling.** It
satisfies Git (not `worktree.*`, not a popular tool's section). It
satisfies org-agnosticism (no publisher name). It is more universal than
`source-control.worktreeroot`, which would still couple every consumer's
git config to this marketplace's plugin identity. It does not take
git-wt's `wt.basedir`. Keeping `melodic.*` would satisfy Git's
collision-freedom alone and would require narrowing Design boundary to
permit a publisher name in a key we ask other people's repositories to
adopt.

## Alternatives considered

- **Keep `melodic.worktreeroot` and exempt git config vendor sections from
  Design boundary.** Rejected. Git's rule is collision-freedom, not
  publisher-naming; a consumer outside this org must not write `melodic.*`.
- **`source-control.worktreeroot`.** Closest to the `ghq` / `git-town` /
  `lfs` tool-section pattern. Rejected as the primary spelling: it still
  names this marketplace's plugin, so a consumer adopting the convention
  couples their git config to that identity.
- **`worktree.root` / `worktree.basedir`.** Rejected: Git owns `worktree.*`.
- **`wt.basedir` / `wtroot.*`.** Rejected: `wt.basedir` is git-wt's key;
  `wtroot` is a coined prefix with no reader-facing meaning.

## Consequences

- `docs/plugin-philosophy.md` Design boundary states the collision-free
  capability-section rule and names `worktreeroot.path`. Convention
  registry gains a row pointing at
  `plugins/source-control/reference/worktree-root-convention.md`.
- The owner doc states `worktreeroot.path` as the convention. A retired
  publisher-named alias is not a skill-facing name: `scripts/worktree-root-legacy.sh`
  dual-reads it, writes `worktreeroot.path` at the winning origin, and unsets
  the alias. Fleet audit stays read-only (its git wrapper does not write).
  Delete the peel after 2026-12-31.
- User-facing remedy strings and skill bodies name only `worktreeroot.path`.
  Doctor `--fix` print-only remains deferred.
