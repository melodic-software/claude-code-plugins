---
bump: patch
---

### Fixed

- The unattended merge gate's cost hold (`babysit_risk.py`) now catches the timeout, model-leg, secret and runner shapes its probe passed (#9241). A raised timeout is compared at each job's or step's own key path, so another job's value moved in the same patch no longer hides it, and one removed (the 360-minute default applies), set to an expression, or written in flow style counts, as does a timeout on a workflow that calls a local workflow or action. A workflow's `ANTHROPIC_*MODEL`, `model:` or `max-turns:` input and a new local `uses: ./` call, a composite action's model settings and a `.github/scripts/` model flag are reported as `cost-finding`; a new model leg in a composite action holds as `agent-surface-review`. `${{ secrets }}`, `contains(secrets, ...)`, `secrets.*` and a reference split across a folded scalar hold as `secret-exposure-review`, and a `runs-on` expression's matrix values and input defaults count as runner values.
