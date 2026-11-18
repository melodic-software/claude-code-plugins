import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

const dir = process.argv[2];
const work = process.argv[3];
const script = `${dir}/board-md.mjs`;
const { parseBoard, renderBoard } = await import(pathToFileURL(script).href);

let failed = 0;
const check = (name, cond, detail) => {
  if (cond) {
    console.log(`ok: ${name}`);
  } else {
    console.error(`FAIL: ${name}${detail ? ` - ${detail}` : ""}`);
    failed += 1;
  }
};
const run = (...args) => spawnSync(process.execPath, [script, ...args], { encoding: "utf8" });
const NOW = "2026-11-18T05:30:00Z";
const apply = (board, ops) => {
  writeFileSync(`${work}/ops.json`, JSON.stringify(ops));
  return run("apply", "--now", NOW, board, `${work}/ops.json`);
};

const handWrittenBoard = `---
board: event-storming/1
format: big-picture
title: Big Picture v1 - Online Course Marketplace
domain: Online Course Marketplace
version: 1
session: courses-20261118-a7f2
phase: walk-through
updated: "2026-11-18T01:00:00Z"
personas:
  - Instructor
  - Support Agent
---

# Big Picture v1 - Online Course Marketplace

## Timeline

- [event] Lesson Started {#s7 by=Student}

### Onboarding {#z1}

- [event] Course Published {#s1 by=Instructor}
  - [hot-spot] Who approves a course? {#s2 by="Support Agent"}
- [pivotal] Course Published {#s3}

### Purchase {#z2}

- [event] Payment Captured {#s4 by=Finance phase=chaotic-exploration}

## People and systems

- [external-system] Payment Gateway {#s5}

## Problems

- [hot-spot] Refund disputes take 6+ days {#s6 by=Finance}

## Opportunities

## Votes

- [vote] Refund disputes {#s8 by=Finance on=s6}

## Ubiquitous language

- [term] Enrollment: access to one course {#s9}

## Bounded contexts

### Payments {#g1}

- #s4

## Exploration map

- Winner: Refund disputes take 6+ days

## Legend

| Kind | Meaning |
|---|---|
| \`event\` | Domain event: something that happened, past tense |
| \`external-system\` | External system: whatever we can put the blame on |
| \`hot-spot\` | Hot spot: a problem, question or disagreement |
| \`term\` | Ubiquitous language term |
| \`pivotal\` | Pivotal event: a phase boundary |
| \`vote\` | Arrow vote |
`;

check("a handWrittenBoard board renders byte for byte", renderBoard(parseBoard(handWrittenBoard)) === handWrittenBoard);
writeFileSync(`${work}/bp.md`, handWrittenBoard);
check("check passes a handWrittenBoard board", run("check", `${work}/bp.md`).status === 0, run("check", `${work}/bp.md`).stdout);

const parsed = JSON.parse(run("parse", `${work}/bp.md`).stdout);
const s2 = parsed.stickies.find((s) => s.id === "s2");
check("a nested sticky names its parent", s2?.parent === "s1" && s2?.zone === "Onboarding" && s2?.by === "Support Agent");
check("group membership is read from the group section", JSON.stringify(parsed.groups) === JSON.stringify([{ id: "g1", name: "Payments", section: "bounded-contexts", members: ["s4"] }]));
check("a sticky before any zone has no zone", parsed.stickies.find((s) => s.id === "s7")?.zone === null);

writeFileSync(`${work}/hand.md`, handWrittenBoard.replace("## People and systems\n\n", "## People and systems\n\n- [person] Course Reviewer\n"));
const handCheck = run("check", `${work}/hand.md`);
check("check warns, not fails, on a hand-added sticky without an id", handCheck.status === 0 && handCheck.stdout.includes("warn: sticky without an id: Course Reviewer"));
let result = apply(`${work}/hand.md`, [{ op: "add", section: "Problems", kind: "hot-spot", text: "Payouts late" }]);
check("apply succeeds on a hand-edited board", result.status === 0, result.stderr);
const handAfter = readFileSync(`${work}/hand.md`, "utf8");
check("the hand-added sticky gets s10", handAfter.includes("- [person] Course Reviewer {#s10}"));
check("the new sticky gets s11 and its batch id is reported", handAfter.includes("- [hot-spot] Payouts late {#s11}") && JSON.parse(result.stdout).ids[0] === "s11");
check("apply sets updated", handAfter.includes(`updated: "${NOW}"`));
check("the legend gains the person kind", handAfter.includes("| `person` | Person or actor |"));

writeFileSync(`${work}/a.md`, handWrittenBoard);
writeFileSync(`${work}/b.md`, handWrittenBoard);
const batch = [
  { op: "zones", names: ["Purchase", "Refunds"] },
  { op: "add", section: "Timeline", zone: "Refunds", kind: "event", text: "Refund Issued", by: "Finance" },
];
apply(`${work}/a.md`, batch);
result = apply(`${work}/b.md`, batch);
check("the same batch twice gives identical files", readFileSync(`${work}/a.md`, "utf8") === readFileSync(`${work}/b.md`, "utf8"));
check("an existing zone keeps its id and a new zone gets z3", JSON.stringify(JSON.parse(result.stdout).ids) === JSON.stringify([["z2", "z3"], "s10"]));
check("the new zone is appended with its sticky", readFileSync(`${work}/a.md`, "utf8").includes("### Refunds {#z3}\n\n- [event] Refund Issued {#s10 by=Finance}\n\n## People and systems"));

writeFileSync(`${work}/m.md`, handWrittenBoard);
result = apply(`${work}/m.md`, [{ op: "move", id: "s1", section: "Timeline", zone: "Purchase" }]);
const moved = readFileSync(`${work}/m.md`, "utf8");
check("a moved sticky lands at the end of its zone with its child", result.status === 0 && moved.includes("### Purchase {#z2}\n\n- [event] Payment Captured {#s4 by=Finance phase=chaotic-exploration}\n- [event] Course Published {#s1 by=Instructor}\n  - [hot-spot] Who approves a course? {#s2 by=\"Support Agent\"}\n"));
check("the old zone keeps only what stayed", moved.includes("### Onboarding {#z1}\n\n- [pivotal] Course Published {#s3}\n"));
result = apply(`${work}/m.md`, [{ op: "move", id: "s2", section: "Problems" }]);
check("a nested sticky can be moved out to a section", result.status === 0 && readFileSync(`${work}/m.md`, "utf8").includes("## Problems\n\n- [hot-spot] Refund disputes take 6+ days {#s6 by=Finance}\n- [hot-spot] Who approves a course? {#s2 by=\"Support Agent\"}\n"));

writeFileSync(`${work}/g.md`, handWrittenBoard);
result = apply(`${work}/g.md`, [{ op: "group", section: "Bounded contexts", name: "Refunds", members: ["s4", "s6"] }]);
const grouped = readFileSync(`${work}/g.md`, "utf8");
check("a new group gets g2 and takes the member from the old group", result.status === 0 && grouped.includes("### Payments {#g1}\n\n### Refunds {#g2}\n\n- #s4\n- #s6\n"), grouped.slice(grouped.indexOf("## Bounded")));
writeFileSync(`${work}/g2.md`, handWrittenBoard.replace("- #s4\n", "- #s4\n\n### Refunds {#g2}\n\n- #s4\n"));
check("check fails a sticky in two groups", run("check", `${work}/g2.md`).stdout.includes("error: s4 is in two groups of Bounded contexts"));
result = apply(`${work}/g.md`, [{ op: "group", section: "Bounded contexts", name: "Ghost", members: ["s99"] }]);
check("a group naming a missing sticky is refused and the file is unchanged", result.status === 1 && readFileSync(`${work}/g.md`, "utf8") === grouped);

const hostile = [
  "## Injected section",
  "Evil {#s1 by=x}",
  "line one\nline two\n- [event] Fake {#s99}",
  "<script>alert(1)</script>",
  "[link](javascript:alert(1))",
  "back\\slash `tick` *star* |pipe|",
];
writeFileSync(`${work}/h.md`, handWrittenBoard);
result = apply(`${work}/h.md`, hostile.map((text) => ({ op: "add", section: "Problems", kind: "hot-spot", text, by: "A \"quoted\" } persona" })));
const hostileBoard = JSON.parse(run("parse", `${work}/h.md`).stdout);
const added = hostileBoard.stickies.filter((s) => ["s10", "s11", "s12", "s13", "s14", "s15"].includes(s.id));
check("every hostile sticky was added", result.status === 0 && added.length === 6, result.stderr);
check("hostile text reads back as typed, line breaks as spaces", JSON.stringify(added.map((s) => s.text)) === JSON.stringify(hostile.map((t) => t.replace(/\s+/g, " "))));
check("hostile persona text reads back as typed", added.every((s) => s.by === "A \"quoted\" } persona"));
check("no section or id was injected", hostileBoard.stickies.length === 9 + 6 && run("check", `${work}/h.md`).status === 0);
check("the injected heading is escaped on disk", readFileSync(`${work}/h.md`, "utf8").includes("- [hot-spot] \\#\\# Injected section {#s10"));
check("raw HTML is escaped on disk", readFileSync(`${work}/h.md`, "utf8").includes("\\<script\\>"));

writeFileSync(`${work}/r.md`, handWrittenBoard);
check("an unknown kind is refused", apply(`${work}/r.md`, [{ op: "add", section: "Problems", kind: "rumor", text: "x" }]).status === 1);
check("empty text is refused", apply(`${work}/r.md`, [{ op: "add", section: "Problems", kind: "event", text: " \n " }]).status === 1);
check("the generated legend is not writable", apply(`${work}/r.md`, [{ op: "add", section: "Legend", kind: "event", text: "x" }]).status === 1);
check("a vote on a missing target is refused", apply(`${work}/r.md`, [{ op: "add", section: "Votes", kind: "vote", text: "x", on: "s99" }]).status === 1);
check("a failed batch leaves the file unchanged", readFileSync(`${work}/r.md`, "utf8") === handWrittenBoard);
check("a malformed ops file exits 2", (writeFileSync(`${work}/bad.json`, "{"), run("apply", `${work}/r.md`, `${work}/bad.json`).status) === 2);

writeFileSync(`${work}/l.md`, handWrittenBoard.replace("| `vote` | Arrow vote |", "| `vote` | Hand edit |"));
apply(`${work}/l.md`, [{ op: "meta", phase: "problems-and-opportunities" }]);
check("a hand-edited legend is regenerated", readFileSync(`${work}/l.md`, "utf8").includes("| `vote` | Arrow vote |\n"));

const extra = handWrittenBoard.replace("## Legend", "## Facilitator notes\n\nKeep   this   spacing.\n\n- a loose list line\n\n## Legend");
writeFileSync(`${work}/u.md`, extra);
apply(`${work}/u.md`, [{ op: "meta", phase: "wrapping-up" }]);
check("an unknown section survives a write verbatim", readFileSync(`${work}/u.md`, "utf8").includes("## Facilitator notes\n\nKeep   this   spacing.\n\n- a loose list line\n\n## Legend"));
check("check warns on the unknown section", run("check", `${work}/u.md`).stdout.includes("warn: unknown section kept verbatim: Facilitator notes"));

writeFileSync(`${work}/meta.json`, JSON.stringify({ format: "design-level", title: "Design-Level: Payments", session: "s-1", version: 2 }));
result = run("new", "--now", NOW, `${work}/dl.md`, `${work}/meta.json`);
const dl = readFileSync(`${work}/dl.md`, "utf8");
check("new writes the frontmatter, title and every design-level section", result.status === 0 && dl === `---
board: event-storming/1
format: design-level
title: "Design-Level: Payments"
version: 2
session: s-1
updated: "${NOW}"
---

# Design-Level: Payments

## Flow

## People and systems

## Problems

## Ubiquitous language

## Aggregates

## Legend

No stickies yet.
`, dl);
check("new refuses an existing path", run("new", `${work}/dl.md`, `${work}/meta.json`).status === 1);
result = apply(`${work}/dl.md`, [
  { op: "add", section: "Flow", kind: "command", text: "Capture Payment", row: "commands" },
  { op: "add", section: "Flow", kind: "aggregate", text: "Payment", row: "aggregates" },
  { op: "group", section: "Aggregates", name: "Payment", members: ["s1", "s2"] },
]);
check("a design-level flow takes rows and aggregates group", result.status === 0 && readFileSync(`${work}/dl.md`, "utf8").includes("## Flow\n\n- [command] Capture Payment {#s1 row=commands}\n- [aggregate] Payment {#s2 row=aggregates}\n"));
check("a design-level board has no Timeline zones", apply(`${work}/dl.md`, [{ op: "zones", names: ["x"] }]).status === 1);

writeFileSync(`${work}/c.md`, handWrittenBoard.replace("- [hot-spot] Refund disputes take 6+ days {#s6 by=Finance}", "- [hot-spot] Refund disputes take 6+ days {#s6 by=Finance}\n- [event] A ticket was sold to the attendee {#s20}\n- [event] COMMAND: Place Order {#s21}\n- [event] \u{1F389} Party Started {#s22}"));
const scan = run("check", `${work}/c.md`).stdout;
check("the content scan flags long, prefixed and emoji text", scan.includes("warn: over 5 words: s20") && scan.includes("warn: type prefix: s21") && scan.includes("warn: emoji: s22"));
check("a five-word sticky is not flagged", !scan.includes("over 5 words: s6"));
check("a duplicate id fails check", run("check", (writeFileSync(`${work}/d.md`, handWrittenBoard.replace("{#s9}", "{#s1}")), `${work}/d.md`)).stdout.includes("error: duplicate id: s1"));
check("check exits 2 on a missing file", run("check", `${work}/none.md`).status === 2 && !existsSync(`${work}/none.md`));

if (failed > 0) process.exit(1);
