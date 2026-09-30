# Generating jobs from a spec

Widget Runner can draft job definitions from a written spec. This page covers the plan and
generate stages; debugging a failing job is a separate flow, below.

## Spec-driven workflow (plan, generate, heal)

For a whole feature rather than one ad-hoc session, drive job authoring from a written spec instead of an ungoverned exploration session. A **baseline job** is a minimal job that puts the workspace in the state every scenario starts from (checkout, login, feature flags). All three stages debug against it via `widget run <baseline> --debug` (background) + `widget attach jb-XXXX`, never by opening the dashboard URL directly (that skips custom setup the baseline performs).

1. **Plan**: write findings to `specs/<feature>.plan.md`, one scenario per heading.
2. **Generate**: turn each scenario into a job under `jobs/`.
3. **Heal**: rerun failing jobs and let the runner propose a fix.

## Debugging a failing job

The attach and debug mechanics follow the runner's debugging reference
(`https://example.invalid/widget-runner/docs/debugging`).
