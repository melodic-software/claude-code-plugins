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

// Every block in the IANA IPv4 Special-Purpose Address Registry whose "Globally
// Reachable" column is not True, not just RFC1918: shared address space (CGN),
// the documentation TEST-NETs, benchmarking, the deprecated 6to4 relay anycast
// range, plus the multicast and reserved space above 224/8.
//
// A deny list is the right shape here, unlike the IPv6 predicate below. IPv4
// global unicast is not one prefix — it is 1.0.0.0 through 223.255.255.255 minus
// the carve-outs — so the two ends are handled by range (`a === 0`, `a >= 224`)
// and the middle needs the registry's blocks enumerated either way. The list is
// complete against the registry; the only rows omitted are those the registry
// marks globally reachable (the AS112, AMT, PCP and TURN anycast assignments).
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
		(a === 192 && b === 88 && c === 99) || // 192.88.99.0/24 deprecated 6to4 relay anycast (RFC 7526)
		(a === 192 && b === 168) || // 192.168.0.0/16 private
		(a === 198 && (b === 18 || b === 19)) || // 198.18.0.0/15 benchmarking
		(a === 198 && b === 51 && c === 100) || // 198.51.100.0/24 TEST-NET-2
		(a === 203 && b === 0 && c === 113) || // 203.0.113.0/24 TEST-NET-3
		a >= 224 // 224.0.0.0/4 multicast + 240.0.0.0/4 reserved + broadcast
	);
}

const hextetRe = /^[0-9a-f]{1,4}$/i;

// Expand an IPv6 literal (brackets already stripped) to its eight 16-bit groups,
// or null when it is not a well-formed address. Accepts RFC 4291 form 3 — a
// trailing dotted quad standing for the last two groups — because the DNS
// resolver feeding this gate can answer in that form, and reading the quad as
// hex would silently misread the address (`192.168.1.1` as 0x192).
function expandIPv6(address) {
	const halves = address.split("::");
	if (halves.length > 2) return null;
	const parse = (part) => {
		if (part === "") return [];
		const tokens = part.split(":");
		let trailing = [];
		if (tokens[tokens.length - 1].includes(".")) {
			const octets = tokens.pop().split(".").map(Number);
			if (
				octets.length !== 4 ||
				octets.some((n) => !Number.isInteger(n) || n < 0 || n > 255)
			) {
				return null;
			}
			trailing = [(octets[0] << 8) | octets[1], (octets[2] << 8) | octets[3]];
		}
		if (!tokens.every((h) => hextetRe.test(h))) return null;
		return [...tokens.map((h) => parseInt(h, 16)), ...trailing];
	};
	const head = parse(halves[0]);
	const tail = halves.length === 2 ? parse(halves[1]) : [];
	if (head === null || tail === null) return null;
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

// Non-global IPv6, derived from the IANA IPv6 Special-Purpose Address Registry.
// The test is an ALLOWLIST inversion: only globally reachable unicast space
// (2000::/3) survives, and the registry's non-global blocks inside 2000::/3 are
// carved back out. An enumerated deny list keeps reopening one class of bypass —
// every prefix nobody listed reads as public, so each newly noticed block is
// another fix — whereas this shape defaults an unlisted, unassigned, or newly
// registered block to refused.
function isPrivateIPv6(address) {
	const g = expandIPv6(address);
	if (!g) return false;

	// The prefixes that carry an IPv4 address are judged by that address: the v6
	// wrapper is only as global as the v4 target it names, so a NAT64 literal
	// wrapping the cloud metadata address is refused like the bare v4 form.
	const embedsIPv4 =
		(g.slice(0, 5).every((h) => h === 0) && g[5] === 0xffff) || // ::ffff:a.b.c.d IPv4-mapped
		(g[0] === 0x0064 &&
			g[1] === 0xff9b &&
			g.slice(2, 6).every((h) => h === 0)); // 64:ff9b::/96 NAT64 well-known prefix
	if (embedsIPv4) {
		const v4 = `${g[6] >> 8}.${g[6] & 0xff}.${g[7] >> 8}.${g[7] & 0xff}`;
		return isPrivateIPv4(v4);
	}

	// RFC 8215 reserves 64:ff9b:1::/48 for translation local to a single domain
	// and permits inter-domain use only under RFC 6052 section 3.2, so the whole
	// prefix is refused rather than unwrapped: its suffix is not a fixed-width v4
	// address, and an internal network routing it is precisely the SSRF target
	// this gate exists to keep out.
	if (g[0] === 0x0064 && g[1] === 0xff9b && g[2] === 0x0001) return true;

	// Outside 2000::/3: `::` unspecified, `::1` loopback, 100::/64 discard-only,
	// 100:0:0:1::/64 dummy prefix (RFC 9780), 5f00::/16 SRv6 SIDs, fc00::/7
	// unique-local, fe80::/10 link-local, ff00::/8 multicast, and every block
	// IANA has not allocated for global unicast.
	if ((g[0] & 0xe000) !== 0x2000) return true;

	// The non-global blocks that sit inside 2000::/3.
	if (g[0] === 0x2001 && (g[1] & 0xfe00) === 0) return true; // 2001::/23 IETF special-purpose (Teredo, benchmarking 2001:2::/48, ORCHID, ...)
	if (g[0] === 0x2001 && g[1] === 0x0db8) return true; // 2001:db8::/32 documentation
	if (g[0] === 0x2002) return true; // 2002::/16 6to4 — wraps an arbitrary IPv4 tunnel endpoint
	if (g[0] === 0x3fff && (g[1] & 0xf000) === 0) return true; // 3fff::/20 documentation (RFC 9637)

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
