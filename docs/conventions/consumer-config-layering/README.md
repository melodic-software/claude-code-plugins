# Consumer-Config Layering Convention

A versioned, marketplace-wide contract for **how** a plugin's consumer-tracked configuration layers —
which layers exist, what order they resolve in, and what a later layer may do to an earlier one. Every
plugin that reads config from a consuming repo resolves it the same way, so an operator who learns one
surface has learned all of them.

This directory is the source of truth: `README.md` (the contract), `CHANGELOG.md` (version history).

## Boundary — this contract owns the axis, never the keys

It governs **layering and precedence only**. Which keys a config surface has, what they mean, and how
they are validated belong to that concern's own owner doc under `docs/conventions/<concern>/`, or to
the plugin's own bundled reference. The two compose: a per-concern doc declares its keys and points
here for how its layers merge.

The distinction is what keeps this doc from colliding with the one-owner-doc-per-shared-concern rule.
Layering is a genuinely cross-cutting axis every config surface shares; keys are not.

## The layers

Three layers, each optional, resolved in this order — a later layer refines an earlier one:

| Order | Layer | Path | Belongs to |
|---|---|---|---|
| 1 | user-global | `~/.claude/<name>` | the operator, across every repo and machine they work in |
| 2 | team | `${CLAUDE_PROJECT_DIR}/.claude/<name>` | the consuming repository, tracked in version control |
| 3 | local overlay | `${CLAUDE_PROJECT_DIR}/.claude/<stem>.local.<ext>` | one operator in one repo, gitignored |

`<name>` is the surface's whole path **relative to `.claude/`**, not just its leaf filename. For a
single-file surface that is `source-control.md`; for a folder-form surface it is
`ecosystems/<ecosystem>.yaml`, giving a user-global layer at
`~/.claude/ecosystems/<ecosystem>.yaml`. The folder hierarchy is part of the surface's identity and
repeats in every layer — collapsing it to the leaf would point the user-global layer at a different
file than the team layer. `<stem>.local.<ext>` follows the same rule: the overlay suffix attaches to
the leaf file, never to a folder in the path.

**All three layers absent is a valid state**, not an error. The surface falls through to whatever the
plugin's own resolution ladder specifies next — inference from the repo's own files, an interview, or
a bundled default.

### Why these three and not others

Each layer answers a question the others cannot. User-global carries a preference across repos, which
a tracked file structurally cannot — a per-user setting cannot decide the location or content of a
team-shared artifact. The team layer is the only layer teammates receive. The overlay is the only
place a personal deviation can live without either editing the shared file or going uncommitted and
lost. Dropping any one of them reintroduces a problem the other two cannot solve.

## Merge semantics

**Additive-preferred.** A later layer *adds to or refines* earlier layers. It never silently replaces
them wholesale.

Two sanctioned forms, in order of preference:

1. **Concatenate.** Every layer that exists is loaded and appended. Correct when the content is prose
   the model reads as guidance — the layers genuinely accumulate, and a reader wants all of them. This
   is what the first-party precedent does.
2. **Per-key override.** A later layer replaces an earlier layer's value **key by key**; a key absent
   from a later layer keeps the earlier value. Correct when the values are scalars or closed lists,
   where concatenation is meaningless or actively wrong — two anchored regexes cannot concatenate into
   a third valid regex, and two attribution-trailer templates would emit two trailers.

**Wholesale replacement is forbidden.** A layer that "overrides this file entirely" or takes the first
matching layer and stops is outside the contract: it turns every key the overlay does not mention into
a silent loss of the base layer's value, which is exactly the failure additive-preferred exists to
prevent. Both sanctioned forms preserve unmentioned keys; wholesale replacement is the one that does
not.

**A surface using per-key override must declare it** in its own contract, next to its keys. The
declaration is what makes it a design decision a reviewer can check rather than an accident.

### Sanctioned exception class: policy-floor precedence inversion

One class of surface — and only this class — inverts the precedence *direction* above while staying
additive on every other axis. A **policy-floor surface** encodes, in its team-tracked layer, a floor
that personal layers may extend or tighten but must never weaken. On a **direct conflict the team
layer wins**, the reverse of the default where a later layer refines an earlier one. It never drops a
base layer wholesale; it only decides who wins a conflict.

A surface qualifies for this class only when all three hold:

1. Its team layer is a genuine **policy floor** — a shared standard whose whole purpose is that a
   personal layer cannot loosen it; personal weakening of a team-agreed rule is the failure mode worth
   structurally preventing.
2. Personal layers (user-global and overlay) remain **add/tighten-only** — they may never supply a
   looser value that takes effect.
3. **Provenance is reported** — when a personal-layer rule materially shapes output, the surface names
   the contributing layer, so a reader can tell a team floor from a personal addition.

This mirrors well-established prior art — managed settings that supersede user settings, org-enforced
rulesets a repo cannot loosen, MDM managed preferences — where a higher-authority layer may be extended
but not weakened. A surface in this class is **conformant, not a tolerated deviation**, and must declare
the inversion in its own contract next to its keys. The class was ratified by #649; `standards` is its
exemplar.

## Overlay naming and the consumer `.gitignore`

The overlay is spelled `*.local.*` — the stem, `.local`, then the original extension. One spelling
across the fleet is the point: a consumer adds one `.gitignore` line and every current and future
surface is covered.

```gitignore
.claude/**/*.local.*
```

That is the whole convention — **one line, recursive form, for every surface**. `.claude/**/` matches
zero or more directories, so this single rule covers a flat `.claude/source-control.local.md`, a
one-deep `.claude/ecosystems/python.local.yaml`, and a profiled
`.claude/ai-briefing/<profile>/x.local.md` alike, while leaving team files tracked. The narrower
`.claude/*.local.*` is what several surfaces currently recommend and it silently fails to ignore any
folder-form overlay; recommend the recursive form instead, and never ask a consumer for two lines
where one is exact.

**No plugin writes the consumer's `.gitignore`.** A setup skill recommends the line and leaves the
edit to the consumer; their ignore file is their artifact.

## Resolution algorithm

A plugin implementing this contract:

1. **Anchors at the repo root** before any repo-relative read — `${CLAUDE_PROJECT_DIR}` when set,
   otherwise `git rev-parse --show-toplevel`. Never a CWD-relative path: invoked from a nested
   directory, a CWD-relative read finds a nonexistent `<subdir>/.claude/...`, misses the real config,
   and silently degrades to a lower rung. Re-resolve the root in every self-contained shell call.
2. **Reads every layer that exists**, in order, and merges per the surface's declared semantics.
   Reading one layer and stopping is not resolution.
3. **Reports which layer supplied each value** whenever it surfaces the effective config to a human.
   A reader who cannot see which layer won cannot tell why the plugin behaves as it does.
4. **Degrades soft on a malformed layer** — surface the error, name the layer, resolve as if that
   layer were absent. Unknown keys are inert. A consuming repo may validate its own files in a gate;
   plugins do not hard-fail on them.

### Per-layer verification verdicts

The same tracked/ignored question produces opposite correct answers per layer, so a single shared
check is always wrong for two of the three:

| Layer | Version control | On violation |
|---|---|---|
| user-global | outside the worktree — **no git command applies** | n/a |
| team | must be tracked | hard STOP: teammates would never receive the shared convention |
| local overlay | must be gitignored, never staged | FAIL: a personal deviation can reach team history |

The user-global row is not an omission. `git check-ignore` and `git status` against a path outside the
repository return a meaningless verdict — or a confidently wrong one when the operator's home
directory is itself a git repository.

## Versioning

`contract_version` (SemVer) versions this contract; the number lives in `CHANGELOG.md`. A change to
the precedence order or to what a layer means is a major bump. Adding an optional layer, or relaxing a
rule additively, is a minor bump. Per-concern key schemas version independently under their own owner
docs and are deliberately decoupled from this number.

## Deviations

Recorded here whether or not ratified. Listing a deviation documents that it exists and diverges; it
does not by itself bless it. Ratifying one — as #649 did for the policy-floor precedence-inversion
class above — moves it from observed to sanctioned. Ruling on each remaining deviation (correct the
surface, or amend this contract) is a separate human-gated decision.

**Ratified as a sanctioned exception class — one axis only:**

- **`standards` precedence inversion** — the exemplar of the policy-floor precedence-inversion class
  above (ratified by #649). Personal layers may add or tighten only; the team-tracked layer wins a
  direct conflict, with provenance reported. Conformant to that class, not a tolerated deviation.
  **This ratification covers the precedence axis alone.** `standards` also diverges on layer *location*
  (see Declared, below), which #649 did not rule on and which remains observed.

**Declared** — the surface states its divergence and why:

- **`standards` locates its layers outside `.claude/`.** Its team and overlay layers live at
  `<standards_dir>/` (default `docs/standards/`) with a setup-owned in-directory `.gitignore`, rather
  than the contract's `${CLAUDE_PROJECT_DIR}/.claude/<name>` and `*.local.*` paths — deliberately,
  because writes under `.claude/` are permission-guarded. **Observed, not ratified:** #649 ruled the
  precedence axis only; the location model is a separate, still-open ruling.
- **`autonomy` exempts its security axes.** Layers refine additively as the contract requires, except
  that no repo-local value may supply or override a security axis at all — a stricter rule than this
  contract, in the direction of safety.
- **`disk-hygiene`'s `--policy` replaces both standing layers.** Its standing layers merge additively
  (overlays may disable or add hints and add protected globs, never weaken a hard guard); the
  wholesale replacement is confined to an explicit per-invocation flag, not a file layer.

**Undeclared** — divergence with no recorded rationale:

- **`ai-briefing` advertises an overlay layer it does not implement.** Its setup recommends a
  `.claude/ai-briefing/**/*.local.*` gitignore line, but no read path resolves a `.local.*` file and
  no file defines what one would do. Its documented resolution covers profile *selection* only, never
  layer precedence. This is the only surface telling consumers to gitignore a layer that has no
  effect.

## Implementers

Conformance is tracked, not assumed. A surface is listed here whether or not it conforms — the gap is
the point. Each row states the surface's conformance **as it exists on `main`**, never as a
migration intends it to be; a row that ran ahead of the code would report a closed gap that is still
open.

| Surface | Consumer config path | Layers | Conformance |
|---|---|---|---|
| `source-control` | `.claude/source-control.md` | team only | single-layer; migration to all three in flight (#647) |
| `toolchain` / `ecosystem-commands` | `.claude/ecosystems/<ecosystem>.yaml` | all three | conforms |
| `codebase-health` | `.claude/codebase-health.md` | all three | conforms (concatenating, with a declared empty-list opt-out) |
| `github` | `.claude/github/` (`routing.yaml` per-key override, `conventions.md` concatenating) | all three | conforms; policy-floor inversion on write-posture routing keys, declared in the plugin's `change-routing.md` |
| `autonomy` | `.claude/autonomy/binding.json` | all three, plus an org rung | declared deviation |
| `standards` (`planning`, `review`) | `<standards_dir>/`, rooted by `.claude/standards.yaml` | all three | precedence inversion ratified via policy-floor class (#649); layer location outside `.claude/` still observed, not ratified |
| `disk-hygiene` | `.claude/disk-hygiene.json` | user-global + team | declared deviation; no overlay layer |
| `ai-briefing` | `.claude/ai-briefing/` | team only | undeclared: overlay recommended, never resolved |
| `code-tidying` | `.claude/tidy-lanes/<lane>.md` | team only | team layer over a bundled default. A project lane declaring `## Merge semantics` merges per-section with its bundled lane (`docs-prose` decomposed: `Scope` per-section override, watch-for patterns additive — #701); lanes without the declaration still resolve project-only wholesale (`shell-tooling` — #724). No user-global or `*.local.*` overlay (#723) |
| `topic-docs` | `.claude/topic-docs.yaml` | team only | single-layer |
| `repo-fleet-hygiene` | `.claude/repo-fleet-hygiene.conf` | team only | single-layer |
| `work-items` | `.work-item-tracker.json` | team only | single-layer; resolves by CWD-to-root climb rather than anchoring at the repo root |
| `testing` (`run-e2e`) | `.claude/testing/e2e.md` | all three | conforms; per-key override on `recording` / `browser_mode`, keys owned by `run-e2e/context/e2e-config.md` |

Migrating a single-layer surface is one change against that surface's own plugin, not a fleet-wide
sweep — and each migration updates its own row in the same change.

### Overlay spelling drift

The fleet currently ships four spellings — `.claude/*.local.*`, `.claude/ecosystems/*.local.*`,
`.claude/autonomy/**/*.local.*`, and a bare `*.local.md` inside a setup-owned
`<standards_dir>/.gitignore`. Each is narrowly correct for its own surface, and collectively they
defeat the one-line promise: a consumer running three plugins is asked for three lines, and the two
non-recursive spellings would silently miss a nested overlay if their surface ever grew a folder.
The recursive line above subsumes all four. Converging each surface's recommendation on it is a
per-surface change tracked by the rows above, not a rule this contract can retroactively impose on
config already written into consumer repositories.
