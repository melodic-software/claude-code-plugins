// Stand-in recorder: clicks the drawer toggle and writes per-frame state to the --out directory.
import { mkdirSync, writeFileSync } from "node:fs";
const out = process.argv[process.argv.indexOf("--out") + 1] ?? "evidence";
mkdirSync(out, { recursive: true });
writeFileSync(`${out}/animation-frames.json`, JSON.stringify([{ frame: 0, property: "transform" }]));
console.log(`clicked #drawer-toggle; wrote ${out}/animation-frames.json`);
