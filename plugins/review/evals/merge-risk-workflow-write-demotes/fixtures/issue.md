# acme/storefront#87: Tag each release from the release workflow

State: OPEN

Today someone tags each release by hand after the release job passes, and two releases last month
went out untagged.

## Acceptance criteria

1. After a green release build on `main`, the release workflow pushes a `v<version>` tag read from
   `package.json`.
