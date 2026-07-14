import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const directory = path.dirname(fileURLToPath(import.meta.url));
const runner = path.join(directory, "per-profile-runner.js");

for (const inheritedName of ["toString", "__defineSetter__", "constructor"]) {
	const result = spawnSync(process.execPath, [runner, inheritedName], {
		cwd: directory,
		encoding: "utf8",
	});
	assert.equal(result.status, 2, `${inheritedName} must be rejected`);
	const response = JSON.parse(result.stdout.trim().split("\n").at(-1));
	assert.equal(response.error, `Unknown subcommand: ${inheritedName}`);
}

process.stdout.write("per-profile runner inherited-command rejection: ok\n");
