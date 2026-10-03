# Review Digest Convention

When `/review:explain-change` builds or offers a change digest for a pull request. This file is
the owner doc for the `review-digest` cascade concern and this repository's team layer for it: the
config block below is what the skill reads here.

## The policy

`digest_policy` takes one of three values:

- `off`: the digest is never offered or built unasked.
- `offer` (the default): the skill offers the digest when any trigger below fires, and stays
  quiet when none does.
- `always`: the skill builds the digest when the pull request is marked ready. At any other
  point it behaves as `offer`.

A reader who invokes the skill directly has asked for the digest. That request is the explicit
argument tier, so the skill builds it whatever the policy says.

Whatever the policy, the digest never posts to the pull request, never comments on it, and never
sets a check status. It does not gate merge.

## The triggers

Under `offer`, any one of these fires the offer:

| Trigger | Fires when | Key |
|---|---|---|
| files | the pull request changes more than `max_files` files | `max_files` |
| changed-lines | additions plus deletions exceed `max_changed_lines` | `max_changed_lines` |
| blast-radius | the assessed blast radius is one of `blast_radius` | `blast_radius` |
| risk-path | a changed path matches one of the `risk_paths` globs | `risk_paths` |
| label | the pull request carries the `opt_in_label` label | `opt_in_label` |

`risk_paths` globs use `**` for any number of directories and `*` or `?` within one path
segment. An empty `opt_in_label` turns the label trigger off. The blast radius comes from the
plan or a `/review:quality-gate downstream` pass, as LOW, MEDIUM, HIGH, or CRITICAL.

## The keys and their layers

The surface is JSON. Layers resolve per the
[config-cascade convention](config-cascade/README.md), per-key override, a later layer replacing
an earlier one key by key:

1. user-global `~/.claude/review-digest.json`
2. team: the `json config` block in `docs/conventions/review-digest.md`, else
   `.claude/review-digest.json`
3. overlay `.claude/review-digest.local.json`

An explicit `--policy` argument beats every layer. An unknown key is inert, and an invalid value
is reported and ignored. Lists replace whole. No key is policy-floor: each one only decides when a
reader is offered a view.

Where a built page goes is the `medium` key of the
[rendered-views concern](rendered-views/README.md#the-rendered-views-cascade-concern), not a key
here. The skill's shipped default is `file`.

The block below holds the shipped defaults, so this repository runs on them. A test holds it equal
to the skill's own defaults.

```json config
{
  "digest_policy": "offer",
  "max_files": 5,
  "max_changed_lines": 200,
  "blast_radius": ["HIGH", "CRITICAL"],
  "risk_paths": [".github/workflows/**", "**/hooks/**", "**/migrations/**"],
  "opt_in_label": "explain-change"
}
```
