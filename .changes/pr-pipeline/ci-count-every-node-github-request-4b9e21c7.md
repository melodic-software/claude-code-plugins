---
bump: patch
---

### Fixed

- The job-end `api-calls` notice counts every GitHub request the lane scripts' Node clients send. Before, the clients built by address-feedback (its select and context mains, fix-ci-context and review-dependency), pr-verify's job-log read, and three steps that named no bucket sent requests the notice never saw. A client on a second token now counts under `API_BUDGET_OVERRIDE_TOKEN` when the request's token is not the step's own `GH_TOKEN` (else `GITHUB_TOKEN`), the rule babysit's gh calls already follow. Before, the job token's calls in a lanes App step were counted as lanes-app. No request changes.
- The notice adds `graphql=K`, the GraphQL requests among the count, which spend GraphQL's own pool: `<token>=N not-modified=M graphql=K`.
