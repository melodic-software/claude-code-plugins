// Every workflow job that calls the GitHub API leaves api-budget readings and
// logs them at its end, so the lane record's githubCalls covers the job: the
// job (or the calling step) sets API_BUDGET_TOKEN, and a final always() step
// runs this action. A job calls GitHub when a step:
//   - runs `gh api|issue|pr|run|workflow|release|label|search|repo`, or
//     handoff-evidence.sh or dispatcher-current.sh;
//   - runs a repository script (scripts/ or .github/scripts/, .sh or .bash)
//     whose own text does any of those;
//   - uses resolve-config or check-trusted-trigger.
// It does not see GitHub calls made from Node or Python (an api-budget.mjs
// caller, babysit_gh.py), through a script a script runs, or through other gh
// subcommands.
import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path/posix";
import { test } from "node:test";

import { parse } from "yaml";

const ROOT = new URL("../../../", import.meta.url);
const WORKFLOWS = new URL(".github/workflows/", ROOT);

// Jobs that call GitHub and are not yet covered, each with its reason.
const ALLOWED = new Map([
	...["pr-run-activity-read.yml:run", "pr-run-activity-write.yml:run"].map(
		(key) => [
			key,
			"the lane job: no job-end log step, and check-trusted-trigger and resolve-config run without API_BUDGET_TOKEN",
		],
	),
	...[
		"intake-triage.yml:redispatch-refined",
		"intake-triage.yml:triage-split-children",
		"pr-review-main.yml:record",
	].map((key) => [
		key,
		"no checkout to load the log-api-budget action from, and no API_BUDGET_TOKEN",
	]),
	[
		"dependabot-fragments.yml:write",
		"the step's own gh pr and gh api calls run with no API_BUDGET_TOKEN",
	],
	// The detector judges selection-audit.sh by the whole file; trace, the mode
	// this job runs, makes none of its gh calls (red-replay does).
	[
		"maintenance-audit-test-selection.yml:audit-test-selection",
		"the per-file detector: trace calls no GitHub API, so no log step",
	],
	...[
		"release-publish-plugins.yml:build",
		"release-publish-plugins.yml:merge",
	].map((key) => [
		key,
		"decide-rebuild.sh does not wrap its gh calls, and the job sets no API_BUDGET_TOKEN",
	]),
	[
		"pr-require-checks.yml:ci-status",
		"report-escalation.sh runs as its own process and does not wrap its gh calls",
	],
	[
		"pr-unblock.yml:report-stop-status",
		"report-escalation.sh runs as its own process and does not wrap its gh calls",
	],
	...[
		"intake-triage.yml:apply-refinement",
		"pr-merge.yml:merge",
		"pr-merge.yml:enable-auto-merge",
		"pr-review-main.yml:review",
		"pr-review-main.yml:review-subscription",
		"pr-review-main.yml:review-fallback",
		"pr-unblock.yml:adjudicate-feedback",
		"pr-verify.yml:check-intent",
		"pr-verify.yml:check-intent-subscription",
		"pr-verify.yml:check-intent-fallback",
		"work-unblock.yml:label-unblocked",
	].map((key) => [
		key,
		"resolve-config runs without API_BUDGET_TOKEN, so its readings go unrecorded",
	]),
	[
		"pr-unblock-dispatch.yml:dispatch",
		"check-trusted-trigger runs without API_BUDGET_TOKEN, so its readings go unrecorded",
	],
]);

const GH_CALL =
	/(?:^|[\s;&|({`$])gh (?:api|issue|pr|run|workflow|release|label|search|repo)\b|handoff-evidence\.sh|dispatcher-current\.sh/m;
const GH_ACTION = /\/actions\/(?:resolve-config|check-trusted-trigger)$/;
const SCRIPT =
	/(?:^|[\s"'])(?:\.base\/)?((?:\.github\/)?scripts\/[\w./-]+\.(?:sh|bash))\b/g;
const WRAP = /\bapi_budget_wrap_gh\b/;
// The self-wrap line: source the wrapper by a path relative to the script,
// then call api_budget_wrap_gh <token>.
const SELF_WRAP =
	/\.\s+"\$\{BASH_SOURCE\[0\]%\/\*\}\/([\w./-]*api-budget\.bash)"[^\n]*\bapi_budget_wrap_gh [a-z]/;

const repoFs = {
	read: (path) => {
		const file = new URL(path, ROOT);
		return existsSync(file) ? readFileSync(file, "utf8") : "";
	},
	exists: (path) => existsSync(new URL(path, ROOT)),
};

// The detector over a file system of repository-relative paths.
const detector = ({ read, exists }) => {
	const actionOf = (step) =>
		step.uses
			?.split("@")[0]
			.split(" ")[0]
			.match(GH_ACTION)?.[0]
			.slice("/actions/".length);
	const scriptsOf = (step) =>
		[...(step.run ?? "").matchAll(SCRIPT)]
			.map(([, path]) => path)
			.filter((path) => GH_CALL.test(read(path)));
	// A script run as its own process gets no gh() a step defines: it wraps its
	// own calls, itself or through a scripts/lib file it sources, by sourcing a
	// wrapper file that exists and defines api_budget_wrap_gh.
	const wrapsItself = (path) => {
		const rel = read(path).match(SELF_WRAP)?.[1];
		if (!rel) return false;
		const wrapper = join(dirname(path), rel);
		return exists(wrapper) && /\bapi_budget_wrap_gh\(\)/.test(read(wrapper));
	};
	const scriptWraps = (path) =>
		wrapsItself(path) ||
		[...read(path).matchAll(/\blib\/([\w.-]+\.(?:sh|bash))\b/g)].some(
			([, lib]) => wrapsItself(`scripts/lib/${lib}`),
		);
	const stepCallsGitHub = (step) =>
		Boolean(actionOf(step)) ||
		GH_CALL.test(step.run ?? "") ||
		scriptsOf(step).length > 0;

	// A job logs its budget through this action under always(), or through the
	// shell library's api_budget_emit, as ci-status does with no checkout.
	const covered = (job) => {
		const { steps } = job;
		const logs = steps.some(
			(s) =>
				(s.uses?.split(" ")[0].endsWith("/actions/log-api-budget") &&
					/always\(\)/.test(s.if ?? "")) ||
				/\bapi_budget_emit\b/.test(s.run ?? ""),
		);
		// A sourced script runs in the step's shell, under the gh() it defines.
		const sourcedUnderWrap = (path) =>
			steps.some(
				(s) =>
					WRAP.test(s.run ?? "") &&
					new RegExp(
						`(?:^|[\\s;{(])(?:\\.|source) ["']?(?:\\.base/)?${path.replaceAll(".", "\\.")}`,
						"m",
					).test(s.run),
			);
		const scripts = steps.flatMap(scriptsOf);
		const unwrapped = scripts.filter(
			(path) => !scriptWraps(path) && !sourcedUnderWrap(path),
		);
		// The actions read API_BUDGET_TOKEN from their own environment; a script's
		// self-wrap does not reach them.
		const actionGaps = steps
			.filter(
				(s) =>
					actionOf(s) && !job.env?.API_BUDGET_TOKEN && !s.env?.API_BUDGET_TOKEN,
			)
			.map((s) => `${actionOf(s)} without API_BUDGET_TOKEN`);
		const shellCalls = steps.some(
			(s) => GH_CALL.test(s.run ?? "") || scriptsOf(s).length > 0,
		);
		const token =
			!shellCalls ||
			job.env?.API_BUDGET_TOKEN ||
			steps.some((s) => s.env?.API_BUDGET_TOKEN || WRAP.test(s.run ?? "")) ||
			(scripts.length > 0 && unwrapped.length === 0);
		return [
			logs ? null : "no job-end log-api-budget step",
			token ? null : "no API_BUDGET_TOKEN",
			...new Set(actionGaps),
			...[...new Set(unwrapped)].map(
				(path) => `${path} does not wrap its gh calls`,
			),
		].filter(Boolean);
	};

	// Every gap in { file: parsed workflow }, as `file:job: what is missing`.
	const gaps = (workflows) =>
		Object.entries(workflows).flatMap(([file, wf]) =>
			Object.entries(wf?.jobs ?? {})
				.filter(([, job]) => job.steps?.some(stepCallsGitHub))
				.map(([id, job]) => [`${file}:${id}`, covered(job)])
				.filter(([, missing]) => missing.length)
				.map(([key, missing]) => `${key}: ${missing.join("; ")}`),
		);
	return { stepCallsGitHub, covered, gaps };
};

const repo = detector(repoFs);
const repoWorkflows = () =>
	Object.fromEntries(
		readdirSync(WORKFLOWS)
			.filter((f) => /\.ya?ml$/.test(f))
			.sort()
			.map((f) => [f, parse(readFileSync(new URL(f, WORKFLOWS), "utf8"))]),
	);
const keyOf = (gap) => gap.slice(0, gap.indexOf(": "));

test("every job that calls the GitHub API logs its api budget", () => {
	assert.deepEqual(
		repo.gaps(repoWorkflows()).filter((gap) => !ALLOWED.has(keyOf(gap))),
		[],
	);
});

test("every allowlisted job still has a gap", () => {
	const open = new Set(repo.gaps(repoWorkflows()).map(keyOf));
	assert.deepEqual(
		[...ALLOWED.keys()].filter((key) => !open.has(key)),
		[],
	);
});

test("the detector sees each kind of GitHub call", () => {
	const { stepCallsGitHub } = repo;
	assert.equal(
		stepCallsGitHub({ run: 'sha=$(gh api "repos/x/pulls/1")' }),
		true,
	);
	assert.equal(stepCallsGitHub({ run: "gh issue create --title t" }), true);
	for (const sub of ["run", "workflow", "release", "label", "search", "repo"]) {
		assert.equal(stepCallsGitHub({ run: `gh ${sub} list` }), true, `gh ${sub}`);
	}
	assert.equal(
		stepCallsGitHub({
			run: "bash .base/.github/scripts/lib/handoff-evidence.sh posted",
		}),
		true,
	);
	assert.equal(
		stepCallsGitHub({
			uses: "./.base/.github/actions/resolve-config # zizmor: ignore[self-repository]",
		}),
		true,
	);
	assert.equal(
		stepCallsGitHub({ uses: "./.github/actions/check-trusted-trigger" }),
		true,
	);
	assert.equal(
		stepCallsGitHub({ run: "bash scripts/claude-code-release-issues.sh" }),
		true,
	);
	assert.equal(stepCallsGitHub({ run: "gh auth status" }), false);
	assert.equal(stepCallsGitHub({ run: "npm test" }), false);
	assert.equal(stepCallsGitHub({ uses: "actions/checkout@v7" }), false);
});

// Fixtures: a wrapper, a script that wraps through it, one whose source path
// misses it, and one with no wrap at all.
const WRAPPER = ".github/actions/log-api-budget/api-budget.bash";
const files = {
	[WRAPPER]: "api_budget_wrap_gh() {\n  :\n}\n",
	"scripts/wraps.sh": `[[ -z "\${RUNNER_TEMP:-}" ]] || ! . "\${BASH_SOURCE[0]%/*}/../${WRAPPER}" 2>/dev/null || api_budget_wrap_gh github-token\ngh api x\n`,
	"scripts/wrong-path.sh": `[[ -z "\${RUNNER_TEMP:-}" ]] || ! . "\${BASH_SOURCE[0]%/*}/../../${WRAPPER}" 2>/dev/null || api_budget_wrap_gh github-token\ngh api x\n`,
	"scripts/bare.sh": "gh issue list\n",
	"scripts/names-only.sh":
		"# api_budget_wrap_gh is defined elsewhere\ngh pr view 1\n",
};
const fixture = detector({
	read: (path) => files[path] ?? "",
	exists: (path) => path in files,
});
const LOG = { uses: "./.base/.github/actions/log-api-budget", if: "always()" };
const env = { API_BUDGET_TOKEN: "github-token" };

test("covered() names each missing piece", () => {
	const { covered } = fixture;
	assert.deepEqual(
		covered({ env, steps: [{ run: "bash scripts/wraps.sh" }, LOG] }),
		[],
	);
	assert.deepEqual(covered({ env, steps: [{ run: "gh api x" }] }), [
		"no job-end log-api-budget step",
	]);
	assert.deepEqual(
		covered({ env, steps: [{ run: "gh api x" }, { ...LOG, if: "success()" }] }),
		["no job-end log-api-budget step"],
	);
	assert.deepEqual(covered({ steps: [{ run: "gh api x" }, LOG] }), [
		"no API_BUDGET_TOKEN",
	]);
	assert.deepEqual(
		covered({ env, steps: [{ run: "bash scripts/bare.sh" }, LOG] }),
		["scripts/bare.sh does not wrap its gh calls"],
	);
	assert.deepEqual(
		covered({ env, steps: [{ run: "bash scripts/names-only.sh" }, LOG] }),
		["scripts/names-only.sh does not wrap its gh calls"],
	);
	assert.deepEqual(
		covered({ steps: [{ run: "bash scripts/wrong-path.sh" }, LOG] }),
		["no API_BUDGET_TOKEN", "scripts/wrong-path.sh does not wrap its gh calls"],
	);
	// A self-wrapping script gives the job no token for the actions.
	assert.deepEqual(
		covered({
			steps: [
				{ uses: "./.github/actions/resolve-config" },
				{ run: "bash scripts/wraps.sh" },
				LOG,
			],
		}),
		["resolve-config without API_BUDGET_TOKEN"],
	);
	assert.deepEqual(
		covered({
			steps: [{ uses: "./.github/actions/check-trusted-trigger", env }, LOG],
		}),
		[],
	);
});

test("gaps() reports each uncovered job by file and id", () => {
	const workflows = {
		"a.yml": {
			jobs: {
				ok: { env, steps: [{ run: "gh api x" }, LOG] },
				nolog: { env, steps: [{ run: "gh api x" }] },
				quiet: { steps: [{ run: "npm test" }] },
			},
		},
		"b.yml": {
			jobs: { script: { steps: [{ run: "bash .base/scripts/bare.sh" }, LOG] } },
		},
	};
	assert.deepEqual(fixture.gaps(workflows), [
		"a.yml:nolog: no job-end log-api-budget step",
		"b.yml:script: no API_BUDGET_TOKEN; scripts/bare.sh does not wrap its gh calls",
	]);
});
