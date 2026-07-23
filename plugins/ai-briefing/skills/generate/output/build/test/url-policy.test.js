import assert from "node:assert/strict";
import test from "node:test";
import { isAllowedUrlScheme, shouldSkipLinkCheck } from "../lib/url-policy.js";

test("isAllowedUrlScheme accepts the benign briefing schemes", () => {
	for (const url of [
		"https://example.com/a",
		"http://example.com/a",
		"mailto:person@example.com",
		"tel:+15551234567",
	]) {
		assert.equal(isAllowedUrlScheme(url), true, url);
	}
});

test("isAllowedUrlScheme rejects dangerous and unlisted schemes", () => {
	for (const url of [
		"javascript:alert(1)",
		"JavaScript:alert(1)",
		"data:text/html,<script>alert(1)</script>",
		"file:///etc/passwd",
		"file://host/share",
		"blob:https://example.com/uuid",
		"vbscript:msgbox(1)",
		"ftp://example.com/x",
		"not-a-url",
	]) {
		assert.equal(isAllowedUrlScheme(url), false, url);
	}
});

test("shouldSkipLinkCheck skips private, loopback, link-local and reserved hosts", async () => {
	for (const link of [
		"http://127.0.0.1/",
		"http://127.0.0.1:8080/x",
		"http://0x7f000001/", // hex form of 127.0.0.1
		"http://2130706433/", // integer form of 127.0.0.1
		"http://10.0.0.5/",
		"http://172.16.0.1/",
		"http://172.31.255.1/",
		"http://192.168.1.1/",
		"https://169.254.169.254/latest/meta-data/", // cloud metadata
		"http://0.0.0.0/",
		"http://localhost/",
		"http://foo.localhost/",
		"http://[::1]/",
		"http://[::]/",
		"http://[fe80::1]/",
		"http://[fc00::1]/",
		"http://[fd12:3456::1]/",
		"http://[::ffff:127.0.0.1]/", // IPv4-mapped loopback
	]) {
		assert.equal(await shouldSkipLinkCheck(link), true, link);
	}
});

test("shouldSkipLinkCheck still checks ordinary public hosts", async () => {
	for (const link of [
		"https://example.com/a",
		"http://8.8.8.8/",
		"https://172.15.0.1/", // just below the 172.16/12 private block
		"https://172.32.0.1/", // just above it
	]) {
		assert.equal(await shouldSkipLinkCheck(link), false, link);
	}
});

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
