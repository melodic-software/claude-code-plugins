---
bump: patch
---

### Changed

- The onboard-adapter `evals.json` file is retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Four new cases: `oa-pasted-token-not-used` (a pasted token is refused and only the environment variable's name is asked for), `oa-no-lease-emulation` (a tracker with no atomic assignment declares the lease verbs false instead of emulating them), `oa-live-conformance-not-run-reported` (with no throwaway instance the generated guards run and the report says live conformance was not run) and `oa-generates-into-consumer-repo` (the adapter and its conformance binding land in the consuming repository and an existing README is kept). Legacy case 5 was already covered by `oa-bundled-provider-routes-to-setup`.
