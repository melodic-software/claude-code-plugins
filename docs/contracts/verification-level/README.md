# Verification level: how much independent checking a skill runs

One setting, `verification`, decides whether a skill's verifier-subagent steps run, and how many.
Each plugin keeps it in its own team file; this page owns what the levels mean. It never touches
CI merge gates: the pull request lanes (`pr-verify`, the review lanes, `ci-status`) run whatever
the level says.

## Keys

In a plugin's team file, `<home>/<plugin>.yaml`, validated by that plugin's schema. `<home>` is
the convention home named by the pointer line, read at the same default-branch commit by
`lib/resolve-convention-home.sh`; with no pointer line, or a declined one, it is
`docs/conventions`. A broken pointer skips the layer.

```yaml
verification: light          # the plugin's level
verification_skills:
  confirm: strict            # one skill's level; beats the plugin's
```

| Level | What an adopting skill does |
|---|---|
| `off` | everything `light` does, and also skips the skill's own real-check steps that its text names as `off`-skippable |
| `light` | skips the verifier dispatch and writes `verification: skipped (light)` where the verdict would go; it never checks inline in its place |
| `standard` | the default: today's behavior |
| `strict` | always runs the verifier passes that are optional today, such as a carve-out for mechanical, behavior-preserving changes |

Where the verifier is the product (a scan whose findings are the verifier's output), `light`
emits the results labeled unverified instead of skipping them.

## Resolution

`read-verification.sh --plugin <plugin> --skill <skill>`, shipped in each adopting plugin's `lib/`
(source `lib/read-verification.sh`), resolves the level and always prints one line, for example
`verification: light (docs/conventions/implementation.yaml verification at origin/main, commit <sha>)`.

- `verification_skills.<skill>` wins; otherwise `verification`; otherwise `standard`.
- **Team layer only, read from the default branch.** Floor direction `team-only`
  ([config-cascade](../config-cascade/README.md#sanctioned-exception-class-policy-floor-precedence-inversion)):
  the file is read at `origin/<default>` after a fetch, never the working tree, so a branch cannot
  lower its own level. There is no user option and no personal override. When the working tree's
  copy gives another level, a second line names both copies.
- The root rule of `lib/config-root.sh classify` comes first: a `$HOME` or non-repository root
  skips the layer. So do no `origin`, a default branch name outside letters, digits, `.`, `_`, `/`
  and `-` (or one with a leading `-` or `..`), and an unfetched default branch. Each skip resolves
  `standard` with its reason.
- An invalid value, at either key, is named and resolves `standard`, as does a file that does not
  parse. A failed fetch reads the last fetched copy and says it may be stale.

## Interactions with other settings

- **`proof_level`** (verification plugin, stricter wins) is unchanged: `off` never drops evidence a
  resolved `live` or `strict` proof level requires.
- **`verify_mechanical_phases`** (implementation plugin, floor `true`): `true` keeps the phase
  verifier on every phase under `light` and `off`. `strict` implies `true`.
- **`pre_ready`** (source-control) decides whether the ready flow's verify step runs;
  `verification` decides only what happens inside it.

## Exempt skills

A skill that is itself the independent check when invoked does not read the level:
`/planning:audit-answers`, `/performance:verify`, `/discipline:scrutinize-dont-coast`,
`/review:quality-gate`, `/review:fanout`, `/planning:devils-advocate` and
`/review:security-review`.

## Adopters

| Skill | Steps the level governs |
|---|---|
| `/verification:confirm` | the fresh-context verifier for the Stage 2 verdict ("Independence of the verdict") |
| `/implementation:implement-dispatch` | the phase verifier and the post-phase source commit verifier (Gates, Phase boundaries) |
