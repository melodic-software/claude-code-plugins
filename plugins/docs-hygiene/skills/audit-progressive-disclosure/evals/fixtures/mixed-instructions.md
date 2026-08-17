# Project instructions

- Build with `make build`; tests with `make test`.
- The service name is `orders-api`; staging lives at `staging.internal`.
- Never commit directly to `main`.

## Deploy procedure

1. Bump the version in `VERSION`.
2. Run `make release` and wait for the artifact to publish.
3. Open a change ticket and link the artifact URL.
4. Run `deploy.sh staging` and smoke-test the health endpoint.
5. If the smoke test passes, run `deploy.sh prod` within the change window.
6. Announce completion in the operations channel and close the ticket.

## Frontend style rules

These apply only to files under `webapp/frontend/`:

- Components use PascalCase filenames; hooks use a `use` prefix.
- Styling goes through the design-token layer; no raw hex values.
- Every new component ships with a Storybook story.

## Legacy migration playbook (pre-2024 tenants only)

Almost no session touches legacy tenants; the modern path below never uses this.

- Export the tenant with `legacy-export --tenant <id>`.
- Transform the dump with the field-mapping table (48 rows, kept inline here):
  `old_name -> new_name`, `old_status -> state`, `billing_v1 -> billing.plan`,
  and 45 further mappings maintained in this section.
- Re-import with `legacy-import --strict` and reconcile counts by hand.

## Modern tenant provisioning

Every new tenant uses this path; it is mutually exclusive with the legacy playbook above.

- Provision through `tenantctl create` with the standard plan template.
- DNS and certificates are automatic; do not hand-edit zone files.
