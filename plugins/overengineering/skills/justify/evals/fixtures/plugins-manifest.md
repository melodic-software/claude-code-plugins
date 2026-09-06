# Bundle manifest

Every bundle below registers hooks. The `setup` column records whether the bundle also ships its own
setup skill, which walks an installer through the bundle's first-run configuration.

| Bundle | Hooks registered | Ships its own `setup` skill |
|---|---|---|
| alpha | 2 | yes |
| bravo | 1 | yes |
| charlie | 3 | yes |
| delta | 1 | yes |
| echo | 2 | yes |
| foxtrot | 1 | yes |
| golf | 4 | yes |
| hotel | 1 | yes |
| india | 2 | no |
| juliet | 1 | no |

The setup skills are not identical. Each configures its own bundle's hooks, and each names the
settings keys that bundle reads. They were added one per bundle as each bundle grew a first-run step.

The two bundles with no setup skill are the two whose hooks need no configuration at all.
