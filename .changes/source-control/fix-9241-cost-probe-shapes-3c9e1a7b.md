---
bump: minor
---

### Changed

- `babysit_risk`'s `cost-review-required` hold covers the timeout and model-leg shapes its probe still passed ([#9241](https://github.com/melodic-software/claude-code-plugins/issues/9241)). On a model workflow, a timeout raised, set to an expression or removed while its job stays now holds, in block or flow style. The patch's added values are paired against the ones it removes, largest first. With both sides read, each job's values are compared against its own, counting a value on the lines below its key, behind an alias, or in the matrix values, input default or `env` value an expression reads, so a raise beside a higher timeout moved elsewhere in the patch still holds. A local reusable workflow or composite action (`uses: ./...`) counts as a model leg. A workflow's added `model:` or `max-turns:` key and `ANTHROPIC_*MODEL` or `CLAUDE_CODE_*MODEL` variable hold. An action's `action.yml` under `.github/actions/` is read like a workflow's steps, and a file under `.github/scripts/` holds on an added `--model` or `--max-turns` flag, model variable or Claude Code package run (`_MODEL_CODE`); a file renamed or copied into either from outside them holds.
- `_SECRET_REF` also counts `secrets.*`, `${{ secrets }}`, `contains(secrets, ...)` and a reference a folded scalar splits across lines, and a bare `secrets` word in a comment no longer offsets one; a reference moved within one file still passes. A `runs-on:` expression's matrix values (block or flow style) and input defaults count as runner values, so a larger runner label added there holds.
