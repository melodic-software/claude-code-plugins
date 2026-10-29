# tarnquill

Team tooling for the tarnquill project: the `tq` command-line tool and the shared paging library.

## Build

```sh
make build        # or: bash scripts/build.sh, pwsh scripts/build.ps1
make check        # runs tests/Tarnquill.Core.Checks
make tq ARGS="env check"
```

The forge is reached through `TARNQUILL_FORGE_URL`; when it is unset no forge is reachable.
