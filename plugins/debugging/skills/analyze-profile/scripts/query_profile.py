#!/usr/bin/env python3
"""Run one read-only SQL query against a database trace_to_sqlite.py wrote.

    query_profile.py <db> <sql> [--param NAME=VALUE ...]

Prints a header row and then one tab-separated row per result. The database is
opened read-only and an authorizer allows only reading tables and calling
functions, so ATTACH, VACUUM, PRAGMA and every write are refused before they
run. Named parameters (:idx) are bound from --param values (an integer, else a
finite decimal, else text), never pasted into
the SQL. Exit 0 on success, 2 on a usage error, a missing database, a refused
statement or an SQL error, with a one-line reason on stderr.

Two subcommands read converted heap snapshots (a database whose meta format is
heapsnapshot). A database file named compare or retainers is passed as ./compare.

    query_profile.py compare <before.db> <after.db> [--limit N]

Prints which heap types grew between two snapshots: a header row, then one row
per type and name with the columns type, name, before_n, after_n, delta_n,
before_bytes, after_bytes, delta_bytes. A type and name in one snapshot only
counts 0 in the other. Rows run by delta_bytes, then delta_n (largest first),
then type, then name, and stop at --limit (default 20). Exit 0.

    query_profile.py retainers <db> <idx>

Prints the shortest path that skips weak edges from the root (idx 0) to the
node <idx>, as a header row and one row per node from the object (depth 0) up to
the root, with the columns depth, idx, node_id, type, name, via. via is the
type:name of the edge that row's node uses to point at the row above. Equal
paths break on the lowest edge seq. Exit 0 with the path, 1 when no path
reaches the root, with a one-line reason on stderr and nothing on stdout.

Both subcommands exit 2, with a one-line reason on stderr and nothing on stdout,
for a usage error, a missing database, a database that is not a heap snapshot,
an SQL error, or (retainers) an <idx> that is not a node.
"""

import argparse
import collections
import math
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
    """An integer, else a finite decimal, else the text as given."""
    try:
        number = int(value)
    except ValueError:
        try:
            decimal = float(value)
        except ValueError:
            return value
        return decimal if math.isfinite(decimal) else value
    if number not in INT64:
        raise ValueError(f"{value} does not fit in a 64-bit integer")
    return number


def fail(message):
    print(f"query_profile: {message}", file=sys.stderr)
    return 2


class Refused(Exception):
    """A subcommand stops with this exit code and one stderr line."""

    def __init__(self, message, code=2):
        super().__init__(message)
        self.code = code


class OneLineParser(argparse.ArgumentParser):
    def error(self, message):
        raise Refused(f"{self.prog}: {message}")


def open_heap(path):
    """A read-only connection to a converted heap snapshot."""
    if not path.is_file():
        raise Refused(f"database not found: {path}")
    try:
        con = sqlite3.connect(f"{path.resolve().as_uri()}?mode=ro", uri=True)
        try:
            con.set_authorizer(read_only)
            row = con.execute(
                "SELECT value FROM meta WHERE key = ?", ("format",)
            ).fetchone()
        except sqlite3.Error:
            con.close()
            raise
    except sqlite3.Error as exc:
        raise Refused(f"{path}: {exc}") from exc
    if row is None or row[0] != "heapsnapshot":
        con.close()
        raise Refused(f"{path} is not a heapsnapshot database")
    return con


def type_counts(con):
    rows = con.execute(
        "SELECT type, name, COUNT(*), SUM(self_size) FROM nodes GROUP BY type, name"
    )
    return {(kind, name): (count, size or 0) for kind, name, count, size in rows}


def compare(argv):
    parser = OneLineParser(prog="query_profile.py compare")
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args(argv)
    if args.limit < 0:
        raise Refused("--limit must not be negative")
    counts = []
    for path in (args.before, args.after):
        con = open_heap(path)
        try:
            counts.append(type_counts(con))
        except sqlite3.Error as exc:
            raise Refused(f"{path}: {exc}") from exc
        finally:
            con.close()
    before, after = counts
    rows = []
    for kind, name in before.keys() | after.keys():
        n0, b0 = before.get((kind, name), (0, 0))
        n1, b1 = after.get((kind, name), (0, 0))
        rows.append((kind, name, n0, n1, n1 - n0, b0, b1, b1 - b0))
    rows.sort(key=lambda r: (-r[7], -r[4], str(r[0]), str(r[1])))
    return [
        "type\tname\tbefore_n\tafter_n\tdelta_n\tbefore_bytes\tafter_bytes\tdelta_bytes",
        *("\t".join(map(str, row)) for row in rows[: args.limit]),
    ], 0


def retainers(argv):
    parser = OneLineParser(prog="query_profile.py retainers")
    parser.add_argument("db", type=Path)
    parser.add_argument("idx", type=int)
    args = parser.parse_args(argv)
    con = open_heap(args.db)
    try:
        node = "SELECT idx, node_id, type, name FROM nodes WHERE idx = ?"
        if con.execute(node, (args.idx,)).fetchone() is None:
            raise Refused(f"no node with idx {args.idx} in {args.db}")
        holders = (
            "SELECT from_idx, type, name FROM edges "
            "WHERE to_idx = ? AND type != 'weak' ORDER BY seq"
        )
        # reached[n] is (the node it was reached from, the edge n uses to point at it)
        reached = {args.idx: None}
        queue = collections.deque([args.idx])
        while queue and 0 not in reached:
            current = queue.popleft()
            for holder, kind, name in con.execute(holders, (current,)):
                if holder not in reached:
                    reached[holder] = (current, f"{kind}:{name}")
                    queue.append(holder)
                    if holder == 0:
                        break
        if 0 not in reached:
            raise Refused(f"no path from the root reaches idx {args.idx}", 1)
        chain = []
        step = 0
        while step is not None:
            chain.append(step)
            step = reached[step][0] if reached[step] else None
        lines = ["depth\tidx\tnode_id\ttype\tname\tvia"]
        for depth, idx in enumerate(reversed(chain)):
            info = con.execute(node, (idx,)).fetchone()
            via = reached[idx][1] if reached[idx] else ""
            lines.append("\t".join(map(str, (depth, *info, via))))
    except sqlite3.Error as exc:
        raise Refused(f"{args.db}: {exc}") from exc
    finally:
        con.close()
    return lines, 0


SUBCOMMANDS = {"compare": compare, "retainers": retainers}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else list(argv)
    if argv and argv[0] in SUBCOMMANDS:
        try:
            lines, code = SUBCOMMANDS[argv[0]](argv[1:])
        except Refused as exc:
            print(f"query_profile: {exc}", file=sys.stderr)
            return exc.code
        print(*lines, sep="\n")
        return code
    return run_sql(argv)


def run_sql(argv):
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
