---
bump: patch
---

### Changed

- The map-components, map-dependencies and map-events `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Ten new cases: `mc-renders-existing-graph` (renders a committed graph without re-collecting it and offers the view without building it), `mc-layer-violation-informational` (a layer violation is marked and reported as informational), `mc-single-module-thin` (a single module is a thin result with no diagram), `mc-gemfile-unknown` and `mp-gemfile-unknown` (an unsupported manifest is reported as unknown), `mp-dotnet-edges-cited`, `mp-cycles-only` and `mp-mixed-ecosystems` (edges cite their manifests across ecosystems), `me-name-resolution` and `me-queue-per-endpoint` (message names resolve by namespace, queues are per endpoint). `mp-unresolved-not-matched` and `me-orphans-by-namespace` gain graders. The build half of each interactive-view case is held: an eval run cannot set the `medium` option. The other nine skills' `evals.json` files stay for later pull requests.
