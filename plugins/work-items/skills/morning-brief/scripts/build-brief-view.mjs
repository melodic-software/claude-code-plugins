#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { buildView, ViewBuildError } from "../../../lib/view-builder.mjs";

function briefData(brief) {
  const data = { title: "Morning brief", notes: [], sections: [] };
  let section = null;
  let titled = false;
  for (const raw of brief.split(/\r\n?|\n/)) {
    const line = raw.trimEnd();
    if (!line) continue;
    const heading = /^== (.+?) ==$/.exec(line);
    if (heading) {
      section = { name: heading[1], lines: [] };
      data.sections.push(section);
    } else if (section) {
      section.lines.push(line);
    } else if (!titled && line.startsWith("Morning brief")) {
      data.title = line;
      titled = true;
    } else {
      data.notes.push(line.trim());
    }
  }
  return data;
}

function main(argv) {
  const out = argv[0] === "--out" ? argv[1] : undefined;
  if (!out) {
    console.error("usage: build-brief-view.mjs --out <file>   (the morning brief on stdin)");
    return 2;
  }
  try {
    const template = readFileSync(new URL("../templates/brief.html", import.meta.url), "utf8");
    writeFileSync(out, buildView({ profile: "interactive", template, data: briefData(readFileSync(0, "utf8")) }));
    console.log(out);
    return 0;
  } catch (err) {
    console.error(err.message);
    return err instanceof ViewBuildError ? 1 : 2;
  }
}

process.exitCode = main(process.argv.slice(2));
