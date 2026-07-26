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

test("shouldSkipLinkCheck skips shared-address and other non-global blocks", async () => {
	for (const link of [
		"http://100.64.0.1/", // 100.64.0.0/10 shared address space (CGN)
		"http://100.127.255.254/",
		"http://192.0.0.8/", // 192.0.0.0/24 IETF protocol assignments
		"http://192.0.2.1/", // TEST-NET-1
		"http://198.18.0.1/", // benchmarking
		"http://198.19.255.1/",
		"http://198.51.100.7/", // TEST-NET-2
		"http://203.0.113.9/", // TEST-NET-3
		"http://192.88.99.1/", // 192.88.99.0/24 deprecated 6to4 relay anycast
		"http://192.88.99.2/", // 6a44-relay anycast
		"http://224.0.0.251/", // multicast
		"http://240.0.0.1/", // reserved
		"http://255.255.255.255/", // broadcast
		"http://[::ffff:100.64.0.1]/", // IPv4-mapped shared address space
		"http://[64:ff9b::a00:1]/", // NAT64 prefix embedding 10.0.0.1
		"http://[100::1]/", // discard-only
		"http://[64:ff9b:1::1]/", // local-use NAT64 (RFC 8215)
		"http://[2001:2::1]/", // benchmarking, inside 2001::/23 special-purpose
		"http://[2001::1]/", // Teredo, inside 2001::/23 special-purpose
		"http://[2001:db8::1]/", // documentation
		"http://[2002:5db8:d822::1]/", // 6to4
		"http://[3fff::1]/", // documentation (RFC 9637)
		"http://[5f00::1]/", // SRv6 SIDs (RFC 9602)
		"http://[ff02::1]/", // multicast
	]) {
		assert.equal(await shouldSkipLinkCheck(link), true, link);
	}
});

// The IPv6 predicate allowlists global unicast (2000::/3) rather than
// enumerating a deny list, so a block nobody listed is refused by default
// instead of read as public.
test("shouldSkipLinkCheck skips IPv6 outside global unicast space", async () => {
	for (const link of [
		"http://[4000::1]/", // unassigned
		"http://[1000::1]/", // unassigned
		"http://[8000::1]/", // unassigned
		"http://[c000::1]/", // unassigned
		"http://[100:0:0:1::1]/", // dummy IPv6 prefix (RFC 9780)
		"http://[64:ff9b:2::1]/", // unassigned, just above the local-use NAT64 block
		"http://[1fff:ffff:ffff:ffff:ffff:ffff:ffff:ffff]/", // just below 2000::/3
		"http://[4000::]/", // just above it
	]) {
		assert.equal(await shouldSkipLinkCheck(link), true, link);
	}
});

test("shouldSkipLinkCheck covers the whole 2001::/23 special-purpose block", async () => {
	for (const link of [
		"http://[2001:1::1]/", // Port Control Protocol anycast
		"http://[2001:3::1]/", // AMT
		"http://[2001:4:112::1]/", // AS112-v6
		"http://[2001:10::1]/", // deprecated ORCHID
		"http://[2001:20::1]/", // ORCHIDv2
		"http://[2001:30::1]/", // drone remote ID
		"http://[2001:1ff:ffff:ffff:ffff:ffff:ffff:ffff]/", // top of the block
	]) {
		assert.equal(await shouldSkipLinkCheck(link), true, link);
	}
	// 2001:200:: is the first global-unicast address above the block.
	assert.equal(await shouldSkipLinkCheck("http://[2001:200::1]/"), false);
});

// Stub resolvers so tests never touch real DNS.
const resolvesPublic = async () => [{ address: "93.184.216.34", family: 4 }];

test("shouldSkipLinkCheck reads resolver answers in RFC 4291 dotted-quad form", async () => {
	// node:dns can answer with the IPv4-mapped dotted form; parsing the quad as
	// hex reads 192.168.1.1 as 0x192, so the record would fall through as public.
	for (const address of ["::ffff:192.168.1.1", "::ffff:169.254.169.254"]) {
		assert.equal(
			await shouldSkipLinkCheck("http://name.example/", async () => [
				{ address, family: 6 },
			]),
			true,
			address,
		);
	}
	assert.equal(
		await shouldSkipLinkCheck("http://name.example/", async () => [
			{ address: "::ffff:93.184.216.34", family: 6 },
		]),
		false,
	);
});

test("shouldSkipLinkCheck skips hostnames resolving to non-global addresses", async () => {
	const cases = [
		["http://metadata.attacker.example/", [{ address: "169.254.169.254", family: 4 }]],
		["http://internal.attacker.example/", [{ address: "10.0.0.7", family: 4 }]],
		["http://cgn.attacker.example/", [{ address: "100.64.0.9", family: 4 }]],
		["http://v6.attacker.example/", [{ address: "::1", family: 6 }]],
		["http://mixed.attacker.example/", [
			{ address: "93.184.216.34", family: 4 },
			{ address: "192.168.1.5", family: 4 },
		]], // ANY non-global record refuses the whole name
	];
	for (const [link, records] of cases) {
		assert.equal(await shouldSkipLinkCheck(link, async () => records), true, link);
	}
});

test("shouldSkipLinkCheck skips unresolvable and unreadable hostnames (fail closed)", async () => {
	const failing = async () => {
		throw new Error("ENOTFOUND");
	};
	assert.equal(await shouldSkipLinkCheck("https://nxdomain.example/", failing), true);
	assert.equal(
		await shouldSkipLinkCheck("https://empty.example/", async () => []),
		true,
	);
	assert.equal(
		await shouldSkipLinkCheck("https://weird.example/", async () => [{}]),
		true,
	);
});

test("shouldSkipLinkCheck still checks hostnames resolving to global addresses", async () => {
	assert.equal(
		await shouldSkipLinkCheck("https://example.com/a", resolvesPublic),
		false,
	);
});

test("shouldSkipLinkCheck still checks ordinary public hosts", async () => {
	for (const link of [
		"https://example.com/a",
		"http://8.8.8.8/",
		"https://172.15.0.1/", // just below the 172.16/12 private block
		"https://172.32.0.1/", // just above it
		"https://100.63.255.254/", // just below the 100.64/10 shared block
		"https://100.128.0.1/", // just above it
		"https://192.0.1.1/", // between 192.0.0/24 and 192.0.2/24
		"https://192.88.98.1/", // just below the 192.88.99/24 relay block
		"https://192.88.100.1/", // just above it
		"https://198.17.255.1/", // just below the 198.18/15 benchmarking block
		"https://198.20.0.1/", // just above it
		"https://223.255.255.254/", // top of unicast space, below multicast
		"https://[2001:db7::1]/", // just below the 2001:db8::/32 documentation block
		"https://[2001:200::1]/", // just above the 2001::/23 special-purpose block
		"https://[2003::1]/", // just above the 2002::/16 6to4 block
	]) {
		assert.equal(await shouldSkipLinkCheck(link, resolvesPublic), false, link);
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
		assert.equal(await shouldSkipLinkCheck(link, resolvesPublic), false, link);
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
