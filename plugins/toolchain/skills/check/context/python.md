# Python Build Commands

## Lint

```bash
# Check (CI mode — no auto-fix)
cd "$PROJECT_DIR" && uv run ruff check . --no-fix

# Code-fix (semantic lint autofixes — /toolchain:lint --code-fix only)
cd "$PROJECT_DIR" && uv run ruff check <files> --fix --no-unsafe-fixes --unfixable F401
```

`--unfixable F401` matches the `ruff-format` hook: protects just-added imports during iterative
editing; F401 still surfaces as a finding. Only auto-deletion is suppressed.

## Format

```bash
# Check (CI mode)
cd "$PROJECT_DIR" && uv run ruff format . --check

# Fix (format-only — /toolchain:lint --fix)
cd "$PROJECT_DIR" && uv run ruff format <files>
```

## Test

```bash
cd "$PROJECT_DIR" && uv run pytest tests/ -x -q
```

### Test output signals

Read for the `Passed on retry` and `Run signals to echo` rules in `SKILL.md` §2:

- **Retry-earned pass (pytest-rerunfailures).** A rerun shows as an `R` in the progress line and as `N rerun` in the final summary line (`2 passed, 1 rerun`), and the run still exits 0. Count the reruns that ended in a pass as flaky. With `-rR` the plugin also prints a `rerun test summary info` section naming each test, otherwise name them from the `R` outcomes. Pointer: <https://github.com/pytest-dev/pytest-rerunfailures/blob/master/CHANGES.rst> (rerun summary and `--fail-on-flaky`). As of: 2026-10-06, observed locally on pytest-rerunfailures 16.7 with pytest 9.1. Recheck trigger: a release changes the summary wording or the outcome letter.
- **Slowest tests.** pytest prints a `slowest N durations` section only when the command or `addopts` passes `--durations=N` (`--durations=10` is the usual size). Absent it, the note names that flag for the consumer's own `test-cmd` or `addopts`.
- **Shuffle seed (pytest-randomly).** The plugin prints `Using --randomly-seed=<n>` in the report header, which `-q` (the bundled default) hides. When pytest-randomly is a project dependency and no seed shows, report `seed: hidden by -q` and the replay form `--randomly-seed=last`, which reuses the previous run's seed. Pointer: <https://github.com/pytest-dev/pytest-randomly#readme>. As of: 2026-10-06, observed locally on pytest-randomly 5.0. Recheck trigger: the README changes the header line or the `last` form.

## Type check

Part of `check-cmd`, which has no fix mode. `fix-cmd` is format-only; `code-fix-cmd` is ruff check only:

```bash
cd "$PROJECT_DIR" && uv run pyright
```

pyright is a **hard prerequisite** of the python default once ruff config opts the ecosystem in. It shares the single compound `check-cmd` with ruff, and tool presence is evaluated per ecosystem, not per tool. The preflight probe is satisfied by `uv`, the runner every python command is invoked through; pyright is never probed. So on a ruff-configured project with `uv` installed and pyright absent from both the project environment and `PATH`, nothing skips: the two ruff commands run and pass, then `uv run pyright` exits 2 (`error: Failed to spawn: pyright` / `program not found`) and the ecosystem reports Lint **`FAIL`**, not a missing-tool `skip`. Because `check-cmd` is one opaque string, that FAIL cannot be narrowed to pyright alone. Install pyright alongside ruff (see the ecosystem's `install-hint`), or, if the project genuinely does not want type checking, drop it by overriding `check-cmd` in the consumer's own `.claude/ecosystems/python.yaml` (ladder rung 1).

## Gotchas

- **Use `uv run` prefix in uv-managed projects** (a `uv.lock` is the signal): it ensures the managed virtualenv is used. In pip/poetry projects, use that project's documented invocation instead
- **E501 (line-too-long) is not auto-fixable**: the formatter handles code wrapping, but docstrings/comments/string literals exceeding the configured `line-length` must be shortened manually
- **pyright runs in its default standard mode absent a `pyrightconfig.json` or `pyproject.toml [tool.pyright]`**: on an untyped or partially-typed project this can surface genuine type errors; set `typeCheckingMode` (e.g. `basic` or `off`) or add project config to tune the strictness rather than suppressing findings ad hoc
- **Run from project directory**: each `pyproject.toml` defines an independent project root. Always `cd` to the directory containing `pyproject.toml` before running commands

## Project discovery

Find all Python projects dynamically:

```bash
find "$REPO_ROOT" -name "pyproject.toml" -not -path "*/node_modules/*" -not -path "*/.venv/*"
```
