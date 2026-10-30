// The builder against a synthetic reusable and caller: it must run the compose
// script it finds, fail closed when it cannot, and fill each case with that
// script's prompt. No assertion reads the real reusable's prompt text.
import assert from "node:assert/strict";
import { existsSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

import { tempDir } from "../../../../lib/test-tmp.mjs";
import { build, callerInputs, composeScript } from "./build-suite.mjs";

const SCRIPT = [
	'const fs = require("node:fs");',
	'const path = require("node:path");',
	"const env = process.env;",
	"const labels = await github.paginate(github.rest.issues.listLabelsForRepo, {});",
	'const dir = fs.mkdtempSync(path.join(env.RUNNER_TEMP, "t-"));',
	// biome-ignore lint/suspicious/noTemplateCurlyInString: the stub script's own template literal
	'fs.writeFileSync(path.join(dir, "p.md"), `ISSUE ${env.ISSUE_NUMBER} AT ${env.ISSUE_FILE} OF ${context.repo.repo} (${labels.length})\\n${env.INSTRUCTIONS}`);',
	'fs.writeFileSync(path.join(dir, "s.json"), "{}");',
	'core.setOutput("prompt-file", path.join(dir, "p.md"));',
	'core.setOutput("schema-file", path.join(dir, "s.json"));',
];
const step = (lines) =>
	[
		"      - name: Compose",
		"        id: compose",
		"        with:",
		"          script: |",
		...lines.map((l) => `            ${l}`),
		"",
	].join("\n");
const reusable = (...steps) =>
	["jobs:", "  triage:", "    steps:", ...steps].join("\n");
const CALLER = [
	"jobs:",
	"  intake-triage:",
	"    uses: melodic-software/ci-workflows/.github/workflows/intake-triage.yml@abc123",
	"    with:",
	"      allowed-labels: |",
	"        priority: low",
	"        needs-human",
	"      instructions: |",
	"        RULE ONE.",
	"",
	"          indented line",
	"    secrets: {}",
	"",
].join("\n");

test("composeScript returns the one script every compose step carries", () => {
	assert.match(
		composeScript(reusable(step(SCRIPT), step(SCRIPT))),
		/^const fs = require/u,
	);
});

test("composeScript fails closed on no step, differing legs or a workflow expression", () => {
	assert.throws(() => composeScript(reusable()), /no compose step/u);
	assert.throws(
		() => composeScript(reusable(step(SCRIPT), step([...SCRIPT, "// other"]))),
		/2 compose scripts differ/u,
	);
	assert.throws(
		// biome-ignore lint/suspicious/noTemplateCurlyInString: a workflow expression, not a template
		() => composeScript(reusable(step(['const x = "${{ inputs.y }}";']))),
		/workflow expression/u,
	);
});

test("callerInputs reads the pin and dedents the block scalars as YAML does", () => {
	assert.deepEqual(callerInputs(CALLER), {
		ref: "abc123",
		allowedLabels: "priority: low\nneeds-human\n",
		instructions: "RULE ONE.\n\n  indented line\n",
	});
});

test("build fills every case with the composed prompt and writes the issue files the prompt names", async () => {
	for (const instructions of [true, false]) {
		const out = tempDir("reentry-build-");
		const { cases } = await build({
			reusable: reusable(step(SCRIPT)),
			sha: "0".repeat(40),
			out,
			instructions,
			callerText: CALLER,
		});
		assert.equal(cases.length, 4);
		for (const name of cases) {
			const dir = join(out, "evals", name);
			const prompt = JSON.parse(
				readFileSync(join(dir, "case.yaml"), "utf8").match(
					/^ {2}prompt: (.*)$/mu,
				)[1],
			);
			const issue = JSON.parse(
				readFileSync(
					join(dir, "workspace", ".intake-triage-eval", "issue.json"),
					"utf8",
				),
			);
			assert.ok(
				prompt.startsWith(
					`ISSUE ${issue.number} AT .intake-triage-eval/issue.json OF claude-code-plugins (`,
				),
				name,
			);
			assert.equal(prompt.includes("RULE ONE."), instructions, name);
			assert.ok(
				prompt.trimEnd().endsWith("{}"),
				"the schema the script wrote ends the prompt",
			);
			for (const file of [issue.body, ...issue.comments.map((c) => c.body)])
				assert.ok(existsSync(join(dir, "workspace", file)), file);
			assert.match(issue.comments[0].url, /#issuecomment-\d+$/u);
			assert.ok(existsSync(join(dir, "workspace", "AGENTS.md")));
			assert.ok(
				statSync(join(dir, "scaffold.sh")).mode & 0o100,
				"scaffold is executable",
			);
		}
	}
});
