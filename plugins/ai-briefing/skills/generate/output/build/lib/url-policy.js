const citationOnlyHosts = ["x.com", "twitter.com"];

// Schemes safe to render as an href, embed as a PPTX hyperlink, or hand to the
// reachability checker. http/https/mailto/tel are the schemes a legitimate
// briefing may contain and are inert at every sink; every other scheme
// (javascript:, data:, file:, blob:, vbscript:, and rarer ones such as ftp:) is
// rejected as deliberate fail-closed hardening.
const allowedSchemes = new Set(["http:", "https:", "mailto:", "tel:"]);

/** True when `value` parses as a URL whose scheme is on the allowlist. */
export function isAllowedUrlScheme(value) {
	let protocol;
	try {
		protocol = new URL(value).protocol;
	} catch {
		return false;
	}
	return allowedSchemes.has(protocol.toLowerCase());
}

function isCitationOnlyHost(hostname) {
	const normalized = hostname.toLowerCase().replace(/\.$/, "");
	return citationOnlyHosts.some(
		(host) => normalized === host || normalized.endsWith(`.${host}`),
	);
}

// Matches the IANA IPv4 Special-Purpose Address Registry's non-global blocks,
// not just RFC1918: any literal target outside globally reachable unicast
// space is refused, including shared address space (CGN) and the multicast
// and reserved ranges.
function isPrivateIPv4(host) {
	const octets = host.split(".").map(Number);
	if (
		octets.length !== 4 ||
		octets.some((n) => !Number.isInteger(n) || n < 0 || n > 255)
	) {
		return false;
	}
	const [a, b, c] = octets;
	return (
		a === 0 || // 0.0.0.0/8 "this host"
		a === 10 || // 10.0.0.0/8 private
		(a === 100 && b >= 64 && b <= 127) || // 100.64.0.0/10 shared address space (CGN)
		a === 127 || // 127.0.0.0/8 loopback
		(a === 169 && b === 254) || // 169.254.0.0/16 link-local (cloud metadata)
		(a === 172 && b >= 16 && b <= 31) || // 172.16.0.0/12 private
		(a === 192 && b === 0 && c === 0) || // 192.0.0.0/24 IETF protocol assignments
		(a === 192 && b === 0 && c === 2) || // 192.0.2.0/24 TEST-NET-1
		(a === 192 && b === 168) || // 192.168.0.0/16 private
		(a === 198 && (b === 18 || b === 19)) || // 198.18.0.0/15 benchmarking
		(a === 198 && b === 51 && c === 100) || // 198.51.100.0/24 TEST-NET-2
		(a === 203 && b === 0 && c === 113) || // 203.0.113.0/24 TEST-NET-3
		a >= 224 // 224.0.0.0/4 multicast + 240.0.0.0/4 reserved + broadcast
	);
}

// Expand a WHATWG-canonical IPv6 literal (brackets already stripped) to its eight
// 16-bit groups, or null when it is not a well-formed address.
function expandIPv6(address) {
	const halves = address.split("::");
	if (halves.length > 2) return null;
	const parse = (part) =>
		part === "" ? [] : part.split(":").map((h) => parseInt(h, 16));
	const head = parse(halves[0]);
	const tail = halves.length === 2 ? parse(halves[1]) : [];
	const groups =
		halves.length === 2
			? [...head, ...Array(8 - head.length - tail.length).fill(0), ...tail]
			: head;
	if (
		groups.length !== 8 ||
		groups.some((g) => !Number.isInteger(g) || g < 0 || g > 0xffff)
	) {
		return null;
	}
	return groups;
}

function isPrivateIPv6(address) {
	const g = expandIPv6(address);
	if (!g) return false;
	if (g.every((h) => h === 0)) return true; // :: unspecified
	if (g.slice(0, 7).every((h) => h === 0) && g[7] === 1) return true; // ::1 loopback
	if ((g[0] & 0xfe00) === 0xfc00) return true; // fc00::/7 unique-local
	if ((g[0] & 0xffc0) === 0xfe80) return true; // fe80::/10 link-local
	if ((g[0] & 0xff00) === 0xff00) return true; // ff00::/8 multicast
	if (g[0] === 0x0100 && g[1] === 0 && g[2] === 0 && g[3] === 0) return true; // 100::/64 discard-only
	if (g[0] === 0x0064 && g[1] === 0xff9b && g[2] === 0x0001) return true; // 64:ff9b:1::/48 local-use NAT64 (RFC 8215)
	if (g[0] === 0x2001 && (g[1] & 0xfe00) === 0) return true; // 2001::/23 IETF special-purpose (Teredo, benchmarking 2001:2::/48, ORCHID, ...)
	if (g[0] === 0x2001 && g[1] === 0x0db8) return true; // 2001:db8::/32 documentation
	if (g[0] === 0x2002) return true; // 2002::/16 6to4 (deprecated; not globally reachable per IANA)
	if (g[0] === 0x3fff && (g[1] & 0xf000) === 0) return true; // 3fff::/20 documentation (RFC 9637)
	if (g[0] === 0x5f00) return true; // 5f00::/16 SRv6 SIDs (RFC 9602)
	const embedsIPv4 =
		(g.slice(0, 5).every((h) => h === 0) && g[5] === 0xffff) || // ::ffff:a.b.c.d IPv4-mapped
		(g[0] === 0x0064 &&
			g[1] === 0xff9b &&
			g.slice(2, 6).every((h) => h === 0)); // 64:ff9b::/96 NAT64 well-known prefix
	if (embedsIPv4) {
		const v4 = `${g[6] >> 8}.${g[6] & 0xff}.${g[7] >> 8}.${g[7] & 0xff}`;
		return isPrivateIPv4(v4);
	}
	return false;
}

// True for hosts that must never be dereferenced during a reachability check.
// Relies on WHATWG URL canonicalization to fold decimal/hex/octal/integer IPv4
// and compressed IPv6 into the literal forms matched here. DNS names that resolve
// to a private address at fetch time are not covered — the checker resolves DNS
// itself, so a rebind remains out of reach of this offline literal gate.
function isPrivateHost(hostname) {
	const host = hostname.toLowerCase().replace(/\.$/, "");
	if (host === "localhost" || host.endsWith(".localhost")) return true;
	if (host.startsWith("[") && host.endsWith("]")) {
		return isPrivateIPv6(host.slice(1, -1));
	}
	if (/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) return isPrivateIPv4(host);
	return false;
}

// Default DNS resolver for the non-literal-host gate below: every address the
// name resolves to, both families.
async function lookupAllAddresses(hostname) {
	const { lookup } = await import("node:dns/promises");
	return lookup(hostname, { all: true });
}

/**
 * Return true for links that must not be included in reachability checks.
 *
 * SSRF guard, two layers: a literal IP host is judged directly against the
 * non-global blocks above, and a DNS name is resolved (every A/AAAA record)
 * and refused when ANY resolved address is non-global — so a hostname whose
 * record points at, e.g., 169.254.169.254 is never dereferenced. A name that
 * does not resolve is skipped too: nothing reachable to check. Residual,
 * documented in the CHANGELOG: the checker performs its own resolution at
 * fetch time, so a rebind between this gate and the fetch, or a redirect hop
 * to a private target inside the checker, remains outside this gate.
 *
 * `resolveHost` is injectable for tests; production uses the real resolver.
 */
export async function shouldSkipLinkCheck(link, resolveHost = lookupAllAddresses) {
	if (/^(?:data:|file:|#)/i.test(link)) return true;

	try {
		const url = new URL(link);
		if (isPrivateHost(url.hostname)) return true;
		if (url.protocol !== "http:" && url.protocol !== "https:") return false;
		if (isCitationOnlyHost(url.hostname)) return true;

		const host = url.hostname.toLowerCase().replace(/\.$/, "");
		const isLiteral =
			(host.startsWith("[") && host.endsWith("]")) ||
			/^\d{1,3}(?:\.\d{1,3}){3}$/.test(host);
		if (!isLiteral) {
			let records;
			try {
				records = await resolveHost(host);
			} catch {
				return true; // unresolvable — nothing reachable to check
			}
			const addresses = Array.isArray(records) ? records : [records];
			if (addresses.length === 0) return true;
			for (const record of addresses) {
				const address =
					typeof record === "string" ? record : record?.address;
				if (typeof address !== "string" || address.length === 0) {
					return true; // unreadable answer — fail closed
				}
				const nonGlobal = address.includes(":")
					? isPrivateIPv6(address)
					: isPrivateIPv4(address);
				if (nonGlobal) return true;
			}
		}
		return false;
	} catch {
		return false;
	}
}
