#!/usr/bin/env python3
"""Convert one captured profile into a SQLite file for querying.

    trace_to_sqlite.py --in <file> --out <db> [--format auto|chrome-trace|cpuprofile|heapsnapshot]

Reads one Chrome trace-event file (optionally gzipped), V8 .cpuprofile or V8
.heapsnapshot and writes the tables below to <out>.partial, renamed to <out>
only after every row is in. It refuses to overwrite <out>. Every string value
is checked before insert and secret-shaped text is stored as <REDACTED>.
Input larger than MAX_INPUT_BYTES, after any gzip decompression, is refused
without reading past the limit. Every value from the file is bound as a SQL
parameter and nothing is ever passed to a shell.

Tables (all present in every output, empty when the format has none):
  meta(key, value)                                   format, source file name
  events(seq, name, cat, ph, ts, dur, pid, tid, args) chrome-trace events
  frames(profile, id, parent, name, url, line, col)   call-tree nodes, 1-based line/col
  samples(profile, seq, frame, delta_us)              one row per CPU sample
  nodes(idx, node_id, type, name, self_size, edge_count)  heap objects
  edges(seq, from_idx, to_idx, type, name)            heap references

Exit 0 with a JSON summary on stdout; exit 2 on any usage or input error, with
a one-line reason on stderr and nothing on stdout or at <out>.
"""

import argparse
import gzip
import json
import os
import re
import sqlite3
import sys
import zlib
from pathlib import Path

FORMATS = ("chrome-trace", "cpuprofile", "heapsnapshot")
MAX_INPUT_BYTES = 512 * 1024 * 1024
REDACTED = "<REDACTED>"
SECRET = re.compile(
    r"gh[pousr]_[A-Za-z0-9]{36}"
    r"|github_pat_[A-Za-z0-9_]{22,}"
    r"|(?:AKIA|ASIA)[0-9A-Z]{16}"
    r"|Bearer\s+[A-Za-z0-9._~+/=-]+"
)

SCHEMA = """
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE events (seq INTEGER PRIMARY KEY, name TEXT, cat TEXT, ph TEXT, ts REAL, dur REAL,
                     pid, tid, args TEXT);
CREATE TABLE frames (profile TEXT, id INTEGER, parent INTEGER, name TEXT, url TEXT, line INTEGER,
                     col INTEGER, PRIMARY KEY (profile, id));
CREATE TABLE samples (profile TEXT, seq INTEGER, frame INTEGER, delta_us REAL);
CREATE TABLE nodes (idx INTEGER PRIMARY KEY, node_id INTEGER, type TEXT, name TEXT,
                    self_size INTEGER, edge_count INTEGER);
CREATE TABLE edges (seq INTEGER PRIMARY KEY, from_idx INTEGER, to_idx INTEGER, type TEXT, name TEXT);
CREATE INDEX samples_frame ON samples (profile, frame);
CREATE INDEX edges_to ON edges (to_idx);
"""


class InputError(Exception):
    """The input cannot be read as the requested format."""


def clean(value):
    return SECRET.sub(REDACTED, value) if isinstance(value, str) else value


def clean_tree(value):
    if isinstance(value, dict):
        return {clean(k): clean_tree(v) for k, v in value.items()}
    if isinstance(value, list):
        return [clean_tree(v) for v in value]
    return clean(value)


def insert(con, table, *values):
    marks = ", ".join("?" * len(values))
    con.execute(f"INSERT INTO {table} VALUES ({marks})", [clean(v) for v in values])


def one_based(value):
    return value + 1 if isinstance(value, int) and value >= 0 else None


def detect(data):
    if isinstance(data, list) or (isinstance(data, dict) and "traceEvents" in data):
        return "chrome-trace"
    if (
        isinstance(data, dict)
        and {"snapshot", "nodes", "edges", "strings"} <= data.keys()
    ):
        return "heapsnapshot"
    if isinstance(data, dict) and {"nodes", "samples"} <= data.keys():
        return "cpuprofile"
    raise InputError("unknown format: not a Chrome trace, .cpuprofile or .heapsnapshot")


def insert_profile(con, profile, nodes, samples, deltas):
    if not isinstance(nodes, list) or not isinstance(samples, list):
        raise InputError("profile nodes and samples must be arrays")
    parents = {}
    for node in nodes:
        for child in node.get("children") or []:
            parents[child] = node["id"]
    for node in nodes:
        frame = node.get("callFrame") or {}
        insert(
            con,
            "frames",
            profile,
            node["id"],
            node.get("parent", parents.get(node["id"])),
            frame.get("functionName", ""),
            frame.get("url", ""),
            one_based(frame.get("lineNumber")),
            one_based(frame.get("columnNumber")),
        )
    deltas = deltas if isinstance(deltas, list) else []
    for seq, frame_id in enumerate(samples):
        delta = deltas[seq] if seq < len(deltas) else None
        insert(con, "samples", profile, seq, frame_id, delta)


def load_cpuprofile(con, data):
    insert_profile(con, "main", data["nodes"], data["samples"], data.get("timeDeltas"))


def load_chrome_trace(con, data):
    events = data["traceEvents"] if isinstance(data, dict) else data
    if not isinstance(events, list):
        raise InputError("traceEvents must be an array")
    chunks = {}
    for seq, event in enumerate(events):
        if not isinstance(event, dict):
            raise InputError(f"trace event {seq} is not an object")
        args = event.get("args")
        insert(
            con,
            "events",
            seq,
            event.get("name"),
            event.get("cat"),
            event.get("ph"),
            event.get("ts"),
            event.get("dur"),
            event.get("pid"),
            event.get("tid"),
            json.dumps(clean_tree(args)) if args is not None else None,
        )
        if event.get("name") == "ProfileChunk":
            payload = (args or {}).get("data") or {}
            cpu = payload.get("cpuProfile") or {}
            key = f"{event.get('pid')}:{event.get('id')}"
            chunk = chunks.setdefault(key, {"nodes": [], "samples": [], "deltas": []})
            chunk["nodes"] += cpu.get("nodes") or []
            chunk["samples"] += cpu.get("samples") or []
            chunk["deltas"] += payload.get("timeDeltas") or []
    for key, chunk in chunks.items():
        insert_profile(con, key, chunk["nodes"], chunk["samples"], chunk["deltas"])


def load_heapsnapshot(con, data):
    meta = data["snapshot"]["meta"]
    node_fields, edge_fields = meta["node_fields"], meta["edge_fields"]
    node_types, edge_types = meta["node_types"][0], meta["edge_types"][0]
    nodes, edges, strings = data["nodes"], data["edges"], data["strings"]
    width, edge_width = len(node_fields), len(edge_fields)
    if not width or not edge_width:
        raise InputError("node_fields and edge_fields must not be empty")
    if len(nodes) % width or len(edges) % edge_width:
        raise InputError("node or edge array length does not match its field count")
    nf = {name: i for i, name in enumerate(node_fields)}
    ef = {name: i for i, name in enumerate(edge_fields)}
    by_name = {"element", "hidden"}
    edge_seq = 0
    for idx in range(len(nodes) // width):
        row = nodes[idx * width : (idx + 1) * width]
        edge_count = row[nf["edge_count"]]
        insert(
            con,
            "nodes",
            idx,
            row[nf["id"]],
            node_types[row[nf["type"]]],
            strings[row[nf["name"]]],
            row[nf["self_size"]],
            edge_count,
        )
        for _ in range(edge_count):
            erow = edges[edge_seq * edge_width : (edge_seq + 1) * edge_width]
            if len(erow) < edge_width:
                raise InputError("edge counts exceed the edge array")
            to_node = erow[ef["to_node"]]
            if to_node % width or not 0 <= to_node < len(nodes):
                raise InputError(f"edge {edge_seq} points outside the node array")
            edge_type = edge_types[erow[ef["type"]]]
            raw_name = erow[ef["name_or_index"]]
            name = str(raw_name) if edge_type in by_name else strings[raw_name]
            insert(con, "edges", edge_seq, idx, to_node // width, edge_type, name)
            edge_seq += 1


LOADERS = {
    "chrome-trace": load_chrome_trace,
    "cpuprofile": load_cpuprofile,
    "heapsnapshot": load_heapsnapshot,
}


def read_json(path):
    with path.open("rb") as fh:
        gzipped = fh.read(2) == b"\x1f\x8b"
        fh.seek(0)
        stream = gzip.GzipFile(fileobj=fh) if gzipped else fh
        raw = stream.read(MAX_INPUT_BYTES + 1)
    if len(raw) > MAX_INPUT_BYTES:
        raise InputError(
            f"{path.name} is larger than {MAX_INPUT_BYTES} bytes once read; refusing it"
        )
    return json.loads(raw)


def convert(src, out, fmt):
    try:
        data = read_json(src)
    except RecursionError as exc:
        raise InputError(f"{src.name} is nested too deeply to parse") from exc
    except (OSError, EOFError, ValueError, zlib.error) as exc:
        raise InputError(f"cannot read {src.name}: {exc}") from exc
    found = detect(data) if fmt == "auto" else fmt
    partial = Path(str(out) + ".partial")
    partial.unlink(missing_ok=True)
    try:
        con = sqlite3.connect(partial)
        try:
            con.executescript(SCHEMA)
            insert(con, "meta", "format", found)
            insert(con, "meta", "source", src.name)
            LOADERS[found](con, data)
            con.commit()
            counts = {
                table: con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
                for table in ("events", "frames", "samples", "nodes", "edges")
            }
        finally:
            con.close()
        if out.exists():
            raise InputError(f"{out.name} appeared during the run; not overwriting it")
        os.replace(partial, out)
    except OverflowError as exc:
        raise InputError(f"{src.name} holds a number SQLite cannot store") from exc
    except RecursionError as exc:
        raise InputError(f"{src.name} is nested too deeply to store") from exc
    except (KeyError, IndexError, TypeError, AttributeError, ValueError) as exc:
        raise InputError(
            f"{src.name} does not have the {found} shape: {exc!r}"
        ) from exc
    finally:
        partial.unlink(missing_ok=True)
    return {"format": found, "tables": counts}


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Convert one captured profile into SQLite."
    )
    parser.add_argument(
        "--in", dest="src", required=True, type=Path, help="profile file to read"
    )
    parser.add_argument("--out", required=True, type=Path, help="SQLite file to create")
    parser.add_argument("--format", default="auto", choices=("auto", *FORMATS))
    args = parser.parse_args(argv)
    if not args.src.is_file():
        print(f"trace_to_sqlite: input not found: {args.src}", file=sys.stderr)
        return 2
    if args.out.exists():
        print(f"trace_to_sqlite: refusing to overwrite {args.out}", file=sys.stderr)
        return 2
    try:
        summary = convert(args.src, args.out, args.format)
    except (InputError, sqlite3.Error) as exc:
        print(f"trace_to_sqlite: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
