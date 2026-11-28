import { writeFileSync } from "node:fs";
import process from "node:process";

import { reportFirstDifference } from "./report-first-difference.mjs";

export function markerForms(name, instruction) {
  return [
    {
      prefix: `<!-- BEGIN GENERATED: ${name}.`,
      start: `<!-- BEGIN GENERATED: ${name}. ${instruction} -->`,
      end: `<!-- END GENERATED: ${name} -->`,
    },
    { prefix: `<!-- ${name}:start -->`, start: `<!-- ${name}:start -->`, end: `<!-- ${name}:end -->` },
  ];
}

function scanMarkers(content, forms) {
  const found = forms.map(() => ({ starts: [], ends: [] }));
  let at = 0;
  for (const raw of content.split("\n")) {
    const text = raw.trim();
    const offset = at + raw.indexOf(text);
    forms.forEach((form, i) => {
      if (text.startsWith(form.prefix)) found[i].starts.push({ at: offset, text });
      else if (text === form.end) found[i].ends.push({ at: offset, text });
    });
    at += raw.length + 1;
  }
  return found;
}

export function findMarkerBlock(content, forms) {
  const present = scanMarkers(content, forms)
    .map((lines, i) => ({ form: forms[i], ...lines }))
    .filter((f) => f.starts.length > 0 || f.ends.length > 0);
  if (present.length === 0) return { error: "missing" };
  if (present.length > 1) {
    const found = present.map((f) => [...new Set([...f.starts, ...f.ends].map((m) => m.text))].join(", "));
    return { error: `carries markers of more than one form (${found.join("; ")}); keep one form` };
  }
  const [{ form, starts, ends }] = present;
  const odd = starts.find((m) => m.text !== form.start);
  if (odd) {
    return { error: `has the start marker line ${odd.text}, which differs from the expected line ${form.start}` };
  }
  if (starts.length !== 1 || ends.length !== 1 || ends[0].at < starts[0].at) {
    return {
      error:
        `has unbalanced markers (${starts.length} of ${form.start}, ${ends.length} of ${form.end}); ` +
        "it needs exactly one of each, start first",
    };
  }
  return { form, block: content.slice(starts[0].at, ends[0].at + form.end.length) };
}

export function wrapMarkerBlock(form, body, forms) {
  const stray = scanMarkers(body, forms).flatMap((f) => [...f.starts, ...f.ends])[0];
  if (stray) return { error: `would get generated content holding the marker line ${stray.text}` };
  return { block: `${form.start}\n\n${body}\n\n${form.end}` };
}

export function syncMarkerBlock({ path, content, existing, expected, check, messages }) {
  if (existing === expected) {
    console.log(check ? messages.inSync : messages.unchanged);
    process.exit(0);
  }
  if (check) {
    console.error(messages.drift);
    console.error(messages.rerun);
    reportFirstDifference(expected, existing);
    process.exit(1);
  }
  writeFileSync(path, content.replace(existing, () => expected));
  console.log(messages.regenerated);
}
