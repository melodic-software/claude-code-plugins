#!/usr/bin/env python3
"""Run one read-only SQL query against a database trace_to_sqlite.py wrote.

    query_profile.py <db> <sql> [--param NAME=VALUE ...]

Prints a header row and then one tab-separated row per result. The database is
opened read-only and an authorizer allows only reading tables and calling
functions, so ATTACH, VACUUM, PRAGMA and every write are refused before they
run. Named parameters (:idx) are bound from --param values, never pasted into
the SQL. Exit 0 on success, 2 on a usage error, a missing database, a refused
statement or an SQL error, with a one-line reason on stderr.
"""

import argparse
import sqlite3
import sys
from pathlib import Path

ALLOWED_ACTIONS = {
    sqlite3.SQLITE_SELECT,
    sqlite3.SQLITE_READ,
    sqlite3.SQLITE_FUNCTION,
    sqlite3.SQLITE_RECURSIVE,
}
INT64 = range(-(2**63), 2**63)


def read_only(action, *_):
    return sqlite3.SQLITE_OK if action in ALLOWED_ACTIONS else sqlite3.SQLITE_DENY


def number_or_text(value):
    try:
        number = int(value)
    except ValueError:
        return value
    if number not in INT64:
        raise ValueError(f"{value} does not fit in a 64-bit integer")
    return number


def fail(message):
    print(f"query_profile: {message}", file=sys.stderr)
    return 2


def main(argv=None):
    parser = argparse.ArgumentParser(description="Query a converted profile read-only.")
    parser.add_argument("db", type=Path)
    parser.add_argument("sql")
    parser.add_argument("--param", action="append", default=[], metavar="NAME=VALUE")
    args = parser.parse_args(argv)
    if not args.db.is_file():
        return fail(f"database not found: {args.db}")
    params = {}
    for item in args.param:
        name, sep, value = item.partition("=")
        if not sep or not name:
            return fail(f"--param needs NAME=VALUE, got {item!r}")
        try:
            params[name] = number_or_text(value)
        except ValueError as exc:
            return fail(f"--param {name}: {exc}")
    try:
        con = sqlite3.connect(f"{args.db.resolve().as_uri()}?mode=ro", uri=True)
        try:
            con.set_authorizer(read_only)
            cursor = con.execute(args.sql, params)
            print(*(col[0] for col in cursor.description or ()), sep="\t")
            for row in cursor:
                print(*row, sep="\t")
        finally:
            con.close()
    except sqlite3.Error as exc:
        return fail(str(exc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
