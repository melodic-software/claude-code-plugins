import assert from "node:assert/strict";
import test from "node:test";
import { shouldSkipLinkCheck } from "../lib/url-policy.js";

test("skips X and Twitter citation hosts and their aliases", async () => {
	const links = [
		"https://x.com/user/status/1",
		"https://www.x.com/user/status/1",
		"https://twitter.com/user/status/1",
		"https://www.twitter.com/user/status/1",
		"https://mobile.twitter.com/user/status/1",
		"https://API.TWITTER.COM./resource",
	];

	for (const link of links) {
		assert.equal(await shouldSkipLinkCheck(link), true, link);
	}
});

test("does not skip lookalike or unrelated hosts", async () => {
	const links = [
		"https://x.com.example.com/user/status/1",
		"https://twitter.com.example.com/user/status/1",
		"https://notx.com/user/status/1",
		"https://example.com/?next=https://x.com/user/status/1",
	];

	for (const link of links) {
		assert.equal(await shouldSkipLinkCheck(link), false, link);
	}
});

test("preserves the existing local and embedded link exclusions", async () => {
	for (const link of [
		"#section",
		"file:///tmp/deck.html",
		"data:image/png;base64,abc",
	]) {
		assert.equal(await shouldSkipLinkCheck(link), true, link);
	}
});
