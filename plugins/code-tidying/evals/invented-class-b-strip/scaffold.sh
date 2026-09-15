#!/usr/bin/env bash
exec bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed.sh" class-b.sh class-b.test.sh Makefile
