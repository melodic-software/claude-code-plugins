#!/usr/bin/env node
// Build the morning-brief status report page from the brief's own text on stdin.
//
//   morning-brief.sh ... | build-brief-view.mjs --out <file>   writes the page, prints its path
//
// The brief carries issue and pull-request titles (K2), so the page is built only from
// templates/brief.html plus the lines as escaped JSON data: the interactive profile of the
// shared builder. Sections are the brief's `== Title ==` headings, each collapsible, and
// one box filters every line.
// Exit 0 built, 1 the page fails its profile, 2 usage or environment.

import { readFileSync, writeFileSync } from "node:fs";
import { buildView, ViewBuildError } from "../../../lib/view-builder.mjs";

function briefData(brief) {
  const data = { title: "Morning brief", notes: [], sections: [] };
  let section = null;
  let titled = false;
  for (const raw of brief.replace(/\r\n?/g, "\n").split("\n")) {
    const line = raw.trimEnd();
    const heading = /^== (.+?) ==$/.exec(line);
    if (heading) {
      section = { name: heading[1], lines: [] };
      data.sections.push(section);
    } else if (line.trim() !== "") {
      if (section) {
        section.lines.push(line);
      } else if (!titled && line.startsWith("Morning brief")) {
        data.title = line;
        titled = true;
      } else {
        data.notes.push(line.trim());
      }
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
