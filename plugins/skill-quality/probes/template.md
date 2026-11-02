# Probe set template

A probe set measures whether one skill's `description` wins the requests it should and stays
quiet on the ones it should not. Write one before rewriting a skill's description, so the rewrite
has a before-and-after score.

## Where it lives

`plugins/<plugin>/probes/<skill>.json`, inside the plugin being rewritten. The schema is the one
in [`reference/invocation-probes.md`](../reference/invocation-probes.md#probe-shape): `skill`,
`plugin`, `skill_dir`, `competitors[]`, and `queries[]` of `id`, `split`, `expect_trigger`,
`request`. Each competitor's directory is derived from its `plugin:skill` id, so the file holds no
path into another plugin; add a `competitor_dirs` entry only for a rival outside `plugins/`.

## Rules

- **16 to 20 queries**, both polarities (`expect_trigger` true and false) and both splits
  (`train` and `validation`).
- **A fresh author.** A fresh agent writes the queries and sees only the skill's *before*
  description, never the body or the planned rewrite. Queries are phrased the way a user asks,
  not copied from the listing.
- **Competitors by purpose.** For the committed `listing-overlap` baseline, list sibling skills
  from the same plugin, so a parallel rewrite in another plugin cannot move that score. A probe
  set meant for live `emit-plugin-eval` runs may also list rivals from other plugins: each
  emitted case loads their plugins beside the target, and the before and after runs load the
  same copies. `validate` warns on each cross-plugin rival as a reminder of that trade.
- **Frozen before the rewrite.** Commit the set before the description changes, and leave it
  unchanged through the rewrite.

## Check it

```shell
bash plugins/skill-quality/scripts/measure-invocation.sh validate plugins/<plugin>/probes
```

`validate` reads only the `*.json` files in the directory, so this file is never parsed as a
probe. CI runs `validate` once for every `plugins/*/probes` directory.
