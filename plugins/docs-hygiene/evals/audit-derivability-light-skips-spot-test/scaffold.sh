#!/usr/bin/env bash
# A sandbox repository whose default branch, pushed to a local bare origin, sets
# `verification: light` for docs-hygiene. docs/build.md restates the Makefile's targets in prose,
# a load-bearing delete or convert-to-pointer candidate that the standard level would spot-test.
set -euo pipefail

git init -q -b main
mkdir -p docs/conventions src

printf 'verification: light\n' >docs/conventions/docs-hygiene.yaml

cat >Makefile <<'MK'
.PHONY: build test lint release

build:
	cc -O2 -o bin/tool src/main.c

test: build
	./bin/tool --self-test

lint:
	clang-format --dry-run --Werror src/*.c

release: test lint
	tar -czf dist/tool.tar.gz bin/tool
MK

printf 'int main(void) { return 0; }\n' >src/main.c

cat >docs/build.md <<'MD'
# Building the tool

New contributors start here. The build has four make targets.

- `make build` compiles `src/main.c` with `cc -O2` into `bin/tool`.
- `make test` builds first, then runs `./bin/tool --self-test`.
- `make lint` checks every C file in `src/` with `clang-format --dry-run --Werror`.
- `make release` runs `test` and `lint`, then packs `bin/tool` into `dist/tool.tar.gz`.
MD

printf '.work/\n' >.gitignore
git add .
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add tool, Makefile and build doc"
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
