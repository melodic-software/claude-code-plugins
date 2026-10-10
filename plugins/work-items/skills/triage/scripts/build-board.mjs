#!/usr/bin/env node
// Build the triage board page from work items read on stdin.
//
//   {"repo":"","generated":"","items":[{"number":1,"title":"","kind":"issue","state":"","labels":[""],"blockedBy":[2]}]}
//
// state is the attention-view bucket (unlabeled, raw marker, needs-info reply, blocked by
// won't-do); omit blockedBy when blockers were not read.
//
//   build-board.mjs --out <file>      writes the page, prints its path
//   build-board.mjs --out <data_dir>/page.html --connect http://127.0.0.1:<port>
//                                     the Claude-interactive page view-bridge serves
//
// The page's row id items-N names the Nth input item; nothing else identifies an item.
//
// Item text is tracker text (K2): it reaches the page only as JSON data that the
// shared runtime renders as text. The markup is templates/board.html and nothing else.
// Exit 0 built, 1 the page or the input fails its profile, 2 usage or environment.

import { readFileSync, writeFileSync } from "node:fs";
import { buildView, ViewBuildError } from "../../../lib/view-builder.mjs";

const text = (value) => (["string", "number"].includes(typeof value) ? String(value) : "");
const number = (value) => (Number.isSafeInteger(value) && value > 0 ? String(value) : "?");

function boardData(input) {
  const items = Array.isArray(input?.items) ? input.items : [];
  const rows = items.map((item) => {
    // An item whose blockers were not read is neither blocked nor unblocked.
    const blockers = Array.isArray(item?.blockedBy) ? item.blockedBy.map((n) => `#${number(n)}`) : null;
    const labels = (Array.isArray(item?.labels) ? item.labels : []).map(text).filter(Boolean);
    return {
      ref: `#${number(item?.number)}`,
      kind: text(item?.kind) || "issue",
      title: text(item?.title),
      state: text(item?.state) || "untriaged",
      blocker: blockers === null ? "blockers not read" : blockers.length ? `blocked by ${blockers.join(" ")}` : "unblocked",
      labels: labels.join(", "),
      blockers: blockers === null ? ["blockers not read"] : blockers.length ? blockers : ["unblocked"],
      labelList: labels.length ? labels : ["no label"],
    };
  });
  const view = ({ ref, kind, title, state, blocker, labels }) => ({ ref, kind, title, state, blocker, labels });
  const group = (names, rowsKey) => {
    const byName = new Map();
    for (const row of rows) {
      for (const name of names(row)) {
        byName.set(name, [...(byName.get(name) ?? []), view(row)]);
      }
    }
    return [...byName]
      .sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]))
      .map(([name, members]) => ({ name, count: members.length, [rowsKey]: members }));
  };
  return {
    title: text(input?.title) || "Triage board",
    repo: text(input?.repo),
    generated: text(input?.generated),
    total: rows.length,
    bystate: group((row) => [row.state], "srows"),
    byblocker: group((row) => row.blockers, "brows"),
    bylabel: group((row) => row.labelList, "lrows"),
    // Input order, so the page's row id items-N is the Nth item in the input.
    items: rows.map(({ ref, title }) => ({ ref, title })),
  };
}

function main(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i += 2) {
    args[argv[i]] = argv[i + 1];
  }
  const out = args["--out"];
  const ok = Object.entries(args).every(
    ([key, value]) => ["--out", "--connect"].includes(key) && typeof value === "string" && value !== "",
  );
  if (!out || !ok) {
    console.error("usage: build-board.mjs --out <file> [--connect <session-bridge origin>]   (JSON on stdin)");
    return 2;
  }
  try {
    const template = readFileSync(new URL("../templates/board.html", import.meta.url), "utf8");
    const data = boardData(JSON.parse(readFileSync(0, "utf8")));
    writeFileSync(out, buildView({ profile: "interactive", template, data, connect: args["--connect"] ?? null }));
    console.log(out);
    return 0;
  } catch (err) {
    console.error(err.message);
    return err instanceof ViewBuildError || err instanceof SyntaxError ? 1 : 2;
  }
}

process.exitCode = main(process.argv.slice(2));
