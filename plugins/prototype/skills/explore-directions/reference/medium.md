# Resolve `medium` first

On the HTML mockup substrate, run the shared medium resolver before the design-canvas offer. This
plugin has no `medium` option, so `--option` is empty. Add `--argument` only when the reader passed
`--medium`, with the value they gave; it is not part of the scope:

```bash
node "<plugin-root>/lib/view-settings.mjs" resolve --lane prototype:explore-directions --option "" [--argument <the --medium value>]
```

It prints one JSON line, then the report line naming the medium and what decided it, then one line
per notice. Print the report line and each notice in the handover as they stand, except that a
notice's closing "; per user, the prototype plugin's medium option also works" clause is dropped,
since this plugin has no such option. Leave every settings file to the resolver. A usage error
(exit 2) means the argument named no medium: say so in one line and run it again without
`--argument`.

- **The JSON's `publishes` is `false`**: the medium keeps the view on this machine. Build the
  mockup and make no design-canvas offer, since the canvas is published. When `page` is also
  `false`, say the mockup is still a local file because a layout is judged by looking at it.
- **`publishes` is `true`, or `medium` is `null`** (no setting decided): keep the shipped default,
  the mockup plus the offer; this skill publishes nothing itself.
- **`node` is missing, or the resolver fails another way** (any nonzero exit after the retry): say
  so in one line in place of the report line, and keep the shipped default.
