import { Buffer } from "node:buffer";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { inspect } from "node:util";
import { checkView, setIntervalMax } from "./frontends/view.ts";
import { compile } from "./pipeline.ts";
import { check, messageOf } from "./run.ts";

const [stage, specFile, configFile, optionsJson, viewFile] = process.argv.slice(2);

try {
  const options = JSON.parse(optionsJson);
  setIntervalMax(options.limits.intervalMax);
  const view = checkView(
    viewFile ? await import(pathToFileURL(path.resolve(viewFile)).href) : {},
    inspect,
  );
  const { files, exit } = compile(
    await check(
      specFile,
      configFile,
      { jar: options.jar, java: options.java },
      options.bounds,
      options.limits,
    ),
    view,
  );
  const draft = path.join(stage, "draft");
  fs.mkdirSync(draft);
  for (const [name, parts] of files) {
    const fd = fs.openSync(path.join(draft, name), "wx");
    try {
      for (const part of parts)
        fs.writeSync(fd, typeof part === "string" ? Buffer.from(part) : part);
      fs.writeSync(fd, "\n");
    } finally {
      fs.closeSync(fd);
    }
  }
  fs.renameSync(draft, path.join(stage, "done"));
  process.exit(exit);
} catch (error) {
  console.error(messageOf(error));
  process.exit(2);
}
