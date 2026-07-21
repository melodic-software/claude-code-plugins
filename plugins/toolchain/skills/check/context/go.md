# Go Build Commands

## Build

```bash
go build ./...
```

## Test

```bash
go test ./...
```

## Lint (golangci-lint v2)

```bash
# Check
golangci-lint run ./...

# Fix (safe auto-fixes only)
golangci-lint run --fix ./...
```

golangci-lint is package-scope by design — it loads and type-checks whole packages, so it always
runs against `./...`, never a single `<files>` argument (unlike gofmt below). With no
`.golangci.yml`/`.golangci.yaml` present it runs its own built-in default linter set — there is no
opt-in gate on the lint leg.

## Format (gofmt)

```bash
# Check (CI mode — lists files that would be reformatted)
gofmt -l <files>

# Fix
gofmt -w <files>
```

gofmt ships with the Go toolchain and has no configuration surface — there is one canonical Go
style, so this leg always runs unconditionally, unlike a config-gated formatter such as Ruff. A
repo that wants import-organizing (goimports) or stricter formatting (gofumpt) on top of gofmt
configures `formatters.enable` in its own golangci-lint v2 config and overrides this ecosystem's
`check-cmd`/`fix-cmd` to route the format leg through `golangci-lint fmt`/`golangci-lint fmt --diff`
instead — see the ecosystem file's `opt-in` field. (`golangci-lint fmt` runs zero formatters with no
such config, verified empirically against golangci-lint v2.12.2 — it would silently no-op as a
shipped default, which is why the bundled default routes through gofmt directly.)

## go mod tidy (project-declared gate)

```bash
go mod tidy -diff
```

Bundled as this ecosystem's `go-mod-tidy` gate (non-mutating; exits non-zero when go.mod/go.sum
drift from what `go mod tidy` would produce). Fix with plain `go mod tidy`.

## govulncheck (optional, not run by default)

```bash
govulncheck ./...
```

Not part of the bundled default — see the ecosystem file's `notes`. A consumer wanting vulnerability
scanning locally adds it as their own `gates` entry in `.claude/ecosystems/go.yaml`.

## Gotchas

- **golangci-lint is package-scope, not per-file** — always pass `./...` (or a package path), never
  an individual `.go` file; a single file out of package context fails to type-check.
- **gofmt operates on individual files** — pass `<files>`, not a directory glob, mirroring
  ShellCheck/shfmt's per-file invocation in `context/bash.md`.
- **`go build`/`go test` compile the whole module** — a change in one package can surface a build
  failure attributed to a different package; read the actual compiler output, don't assume the
  changed file is the fault.
- **golangci-lint config discovery** — `.golangci.yml`/`.golangci.yaml`/`.golangci.toml`/
  `.golangci.json` is walked upward from the working directory; run from `$REPO_ROOT`.

## File discovery

Discover dynamically:

```bash
find "$REPO_ROOT" -name "*.go" -not -path "*/vendor/*"
```
