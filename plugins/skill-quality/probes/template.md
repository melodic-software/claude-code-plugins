# Probe set template

A probe set measures whether one skill's `description` wins the requests it should and stays
quiet on the ones it should not. Write one before rewriting a skill's description, so the rewrite
has a before-and-after score.

## Where it lives

`plugins/<plugin>/probes/<skill>.json`, inside the plugin being rewritten. The schema is the one
in [`reference/invocation-probes.md`](../reference/invocation-probes.md#probe-shape): `skill`,
`plugin`, `skill_dir`, `competitors[]`, `competitor_dirs`, and `queries[]` of `id`, `split`,
`expect_trigger`, `request`.

## Rules

- **16 to 20 queries**, both polarities (`expect_trigger` true and false) and both splits
  (`train` and `validation`).
- **A fresh author.** A fresh agent writes the queries and sees only the skill's *before*
  description, never the body or the planned rewrite. Queries are phrased the way a user asks,
  not copied from the listing.
- **Same-plugin competitors only.** List sibling skills from the same plugin, so a parallel
  rewrite in another plugin cannot move this score.
- **Frozen before the rewrite.** Commit the set before the description changes, and leave it
  unchanged through the rewrite.

## Check it

```shell
bash plugins/skill-quality/scripts/measure-invocation.sh validate plugins/<plugin>/probes
```

`validate` reads only the `*.json` files in the directory, so this file is never parsed as a
probe. CI runs `validate` once for every `plugins/*/probes` directory.
