# Go Build Commands

## Build

```bash
cd "$PROJECT_DIR" && go build ./...
```

## Test

```bash
cd "$PROJECT_DIR" && go test ./...
```

## Lint / Format

Opt-in gated: only runs when a governing `.golangci.yml`/`.golangci.yaml`/`.golangci.toml`/
`.golangci.json` is present (see the `opt-in` key and its header-comment rationale in
`reference/ecosystems/go.yaml`) — otherwise skipped visibly rather than imposing golangci-lint's
own unconfigured "standard" linter preset on a repo that never configured any.

```bash
# Check (CI mode — fails on violations)
cd "$PROJECT_DIR" && golangci-lint run ./...

# Fix
cd "$PROJECT_DIR" && golangci-lint run --fix ./...
```

## Gotchas

- **`./...` is module-bounded, not repo-bounded** — `go build ./...`/`go test ./...`/
  `go list ./...` run from a repo root silently skip a *nested* module's packages. A nested
  `go.mod`, or even a root `go.work` file listing both modules, does not cross that boundary for
  `./...` expansion (empirically verified, Go 1.26.5). `project-discovery: ["go.mod"]` in
  `go.yaml` handles this by walking to each discovered module root — always run build/test/lint
  from the module root containing the relevant `go.mod`, not just the repo root.
- **golangci-lint's config discovery has no `root = true`-equivalent stop marker** — unlike
  EditorConfig, it walks from the target up to the filesystem root and then falls back to the
  user's **home directory**. A stray `~/.golangci.yml` on a developer's machine can make a local
  run diverge from a clean CI container that has no such file. This plugin's own `opt-in` gate
  only ceilings *its* presence check at the repo root — it does not (and cannot) suppress
  golangci-lint's own home-directory fallback once the tool actually runs.
- **`go mod tidy -diff` requires Go 1.23+** — the `go-mod-tidy-drift` gate in `go.yaml` uses this
  flag; on an older toolchain it will error rather than report drift.
- **GOFLAGS** — a repo-level `GOFLAGS` env var or `go env -w GOFLAGS=...` setting changes build/test
  behavior repo-wide (e.g. `-mod=readonly`); check for one before assuming a bare command failure
  is a real break.

## Project discovery

Find all Go modules dynamically:

```bash
find "$REPO_ROOT" -name "go.mod" -not -path "*/vendor/*"
```
