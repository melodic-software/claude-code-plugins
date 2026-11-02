# Model routing

Each row of the routing table is this repository's default for one role, and every model a row
names is available to the whole team.

**Where a default can be changed.** These rows are the repository's defaults. One person's routing
preference goes in that operator's user-level settings and never in this table. Ordered from the
narrowest scope to the widest: the call site can pass `model` per call (only ever upward for a
verdict, as the rule above says); a helper's own `model` frontmatter gives that helper its default;
`CORVID_HELPER_MODEL` covers helpers that nothing else sets; `CORVID_DEFAULT_LARGE_MODEL`,
`CORVID_DEFAULT_MEDIUM_MODEL`, `CORVID_DEFAULT_SMALL_MODEL` and `CORVID_DEFAULT_TINY_MODEL` fix the
model behind each alias; and an `allowedModels` list caps all of these (see below).

- **Pointer:** the alias variables are listed under
  [environment variables](https://example.invalid/corvid/docs/model-config#environment-variables),
  and the allowlist under
  [restrict models](https://example.invalid/corvid/docs/model-config#restrict-models).
