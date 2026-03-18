#!/usr/bin/env bun
/**
 * Top-bank FinTS anonymous-init smoke matrix.
 *
 * What it tests (no credentials required):
 * - Endpoint reachability + FinTS envelope acceptance
 * - BPD presence (HIBPA)
 * - HIKAZS / HICAZS support advertisement
 * - HITANS TAN method IDs
 *
 * Usage:
 *     bun scripts/test-bank-matrix.ts
 *     bun scripts/test-bank-matrix.ts --timeout 20
 */

import { readFileSync, writeFileSync, mkdirSync } from "fs";
import { resolve, dirname } from "path";

const PRODUCT_ID = "F7C4049477F6136957A46EC28";
const COUNTRY = "280";

interface BankInfo {
	blz: string;
	bic: string;
	name: string;
	url: string;
}

interface ProbeResult {
	label: string;
	blz: string;
	name: string;
	url: string;
	endpoint_ok: boolean;
	bpd_ok: boolean;
	structural_ok: boolean;
	hikaz_versions: string[];
	has_hicazs: boolean;
	tan_methods: string[];
	response_codes: string[];
	http_status: number | null;
	error: string;
	variant: string;
}

function buildAnonymousInit(blz: string): string {
	const hkidn = `HKIDN:2:2+${COUNTRY}:${blz}+0+0+0'`;
	const hkvvb = `HKVVB:3:3+0+0+0+${PRODUCT_ID}+1.0'`;
	const inner = hkidn + hkvvb;
	const hnhbs = "HNHBS:4:1+1'";

	const headerPrefix = "HNHBK:1:3+";
	const headerSuffix = "+300+0+1'";
	const headerLen = headerPrefix.length + 12 + headerSuffix.length;
	const total = headerLen + inner.length + hnhbs.length;
	const header = `${headerPrefix}${String(total).padStart(12, "0")}${headerSuffix}`;
	return header + inner + hnhbs;
}

function buildAnonymousInitWithHksyn(blz: string): string {
	const hkidn = `HKIDN:2:2+${COUNTRY}:${blz}+0+0+0'`;
	const hkvvb = `HKVVB:3:3+0+0+0+${PRODUCT_ID}+5.0.0'`;
	const hksyn = "HKSYN:4:3+0'";
	const inner = hkidn + hkvvb + hksyn;
	const hnhbs = "HNHBS:5:1+1'";

	const headerPrefix = "HNHBK:1:3+";
	const headerSuffix = "+300+0+1'";
	const headerLen = headerPrefix.length + 12 + headerSuffix.length;
	const total = headerLen + inner.length + hnhbs.length;
	const header = `${headerPrefix}${String(total).padStart(12, "0")}${headerSuffix}`;
	return header + inner + hnhbs;
}

function decodeFintsResponse(raw: ArrayBuffer): string {
	const text = new TextDecoder("latin1").decode(raw);
	const clean = text.replace(/[\n\r ]/g, "");
	const decoded = Buffer.from(clean, "base64");
	return new TextDecoder("latin1").decode(decoded);
}

function parseSegmentVersion(header: string): string | null {
	const parts = header.split(":");
	if (parts.length < 3) return null;
	const ver = parts[2];
	return /^\d+$/.test(ver) ? ver : null;
}

function analyzeResponse(decoded: string) {
	const segments = decoded.split("'").filter(Boolean);

	const bpd_ok = segments.some((s) => s.startsWith("HIBPA"));
	const codeMatches = decoded.match(/([0-9]{4}):/g) || [];
	const codes = [...new Set(codeMatches.map((c) => c.slice(0, 4)))].sort();
	const structural_ok = !codes.includes("9110");

	const hikaz_versions: Set<string> = new Set();
	let has_hicazs = false;
	const tan_methods: Set<string> = new Set();

	for (const seg of segments) {
		if (seg.startsWith("HIKAZS:")) {
			const header = seg.split("+", 1)[0];
			const ver = parseSegmentVersion(header);
			if (ver) hikaz_versions.add(ver);
		} else if (seg.startsWith("HICAZS:")) {
			has_hicazs = true;
		} else if (seg.startsWith("HITANS:")) {
			const body = seg.split("+").slice(1);
			for (const field of body) {
				const m = field.match(/^([0-9]{3}):[0-9A-Z]:/);
				if (m) tan_methods.add(m[1]);
			}
		}
	}

	return {
		bpd_ok,
		structural_ok,
		hikaz_versions: [...hikaz_versions].sort((a, b) => Number(a) - Number(b)),
		has_hicazs,
		tan_methods: [...tan_methods].sort(),
		codes,
	};
}

async function sendAnonymousProbe(
	bank: BankInfo,
	timeoutMs: number,
	variant: string = "anon",
): Promise<ProbeResult> {
	const base: Omit<ProbeResult, "endpoint_ok" | "bpd_ok" | "structural_ok" | "hikaz_versions" | "has_hicazs" | "tan_methods" | "response_codes" | "http_status" | "error"> = {
		label: bank.name,
		blz: bank.blz,
		name: bank.name,
		url: bank.url,
		variant,
	};

	try {
		const msg = variant === "anon_hksyn"
			? buildAnonymousInitWithHksyn(bank.blz)
			: buildAnonymousInit(bank.blz);
		const body = Buffer.from(msg, "latin1").toString("base64");

		const controller = new AbortController();
		const timer = setTimeout(() => controller.abort(), timeoutMs);

		const resp = await fetch(bank.url, {
			method: "POST",
			body,
			headers: { "Content-Type": "text/plain" },
			signal: controller.signal,
		});
		clearTimeout(timer);

		if (resp.status !== 200) {
			return {
				...base,
				endpoint_ok: false,
				bpd_ok: false,
				structural_ok: false,
				hikaz_versions: [],
				has_hicazs: false,
				tan_methods: [],
				response_codes: [],
				http_status: resp.status,
				error: `HTTP ${resp.status}`,
			};
		}

		const rawBuf = await resp.arrayBuffer();
		const decoded = decodeFintsResponse(rawBuf);
		const analysis = analyzeResponse(decoded);

		return {
			...base,
			endpoint_ok: true,
			...analysis,
			response_codes: analysis.codes,
			http_status: resp.status,
			error: "",
		};
	} catch (err) {
		return {
			...base,
			endpoint_ok: false,
			bpd_ok: false,
			structural_ok: false,
			hikaz_versions: [],
			has_hicazs: false,
			tan_methods: [],
			response_codes: [],
			http_status: null,
			error: String(err),
		};
	}
}

function chooseBetterResult(primary: ProbeResult, secondary: ProbeResult): ProbeResult {
	if (!primary.endpoint_ok && secondary.endpoint_ok) return secondary;
	if (primary.endpoint_ok && !secondary.endpoint_ok) return primary;

	const score = (r: ProbeResult) =>
		(r.bpd_ok ? 4 : 0) +
		(r.structural_ok ? 2 : 0) +
		(r.hikaz_versions.length > 0 ? 1 : 0) +
		(r.has_hicazs ? 1 : 0);

	return score(secondary) > score(primary) ? secondary : primary;
}

function parseBanksZig(path: string): Map<string, BankInfo> {
	const text = readFileSync(path, "utf-8");
	const pattern = /makeBank\("(\d{8})",\s*"([^"]*)",\s*"([^"]*)",\s*"([^"]*)"\)/g;
	const banks = new Map<string, BankInfo>();
	let m: RegExpExecArray | null;
	while ((m = pattern.exec(text)) !== null) {
		banks.set(m[1], { blz: m[1], bic: m[2], name: m[3], url: m[4] });
	}
	return banks;
}

function chooseAtruviaRepresentative(banks: Map<string, BankInfo>): BankInfo | null {
	const candidates = [...banks.values()]
		.filter(
			(b) =>
				b.url.includes("fints1.atruvia.de/cgi-bin/hbciservlet") &&
				(/Volksbank|Raiffeisenbank|VR Bank/.test(b.name)),
		)
		.sort((a, b) => a.blz.localeCompare(b.blz));
	return candidates[0] ?? null;
}

function buildTargetList(banks: Map<string, BankInfo>): Array<[string, BankInfo]> {
	const targets: Array<[string, string]> = [
		["Comdirect", "20041177"],
		["Berliner Sparkasse", "10050000"],
		["Deutsche Bank", "10070000"],
		["Commerzbank", "10040000"],
		["Postbank", "10010010"],
		["ING", "50010517"],
		["DKB", "12030000"],
	];

	const out: Array<[string, BankInfo]> = [];
	for (const [label, blz] of targets) {
		const bank = banks.get(blz);
		if (bank) out.push([label, bank]);
	}

	const atruvia = chooseAtruviaRepresentative(banks);
	if (atruvia) out.push(["Atruvia representative", atruvia]);
	return out;
}

function yn(v: boolean): string {
	return v ? "YES" : "NO";
}

function printMatrix(results: ProbeResult[]) {
	const cols: Array<[string, number]> = [
		["Bank", 24],
		["BLZ", 8],
		["Endpoint", 8],
		["BPD", 4],
		["Struct", 6],
		["HIKAZS", 8],
		["HICAZS", 6],
		["TAN methods", 18],
		["Codes", 20],
		["Variant", 10],
	];
	console.log(cols.map(([n, w]) => n.padEnd(w)).join("  "));
	console.log(cols.map(([, w]) => "-".repeat(w)).join("  "));

	for (const r of results) {
		const hikaz = r.hikaz_versions.join(",") || "-";
		const tan = r.tan_methods.join(",") || "-";
		const codes = r.response_codes.join(",") || "-";
		const row = [
			r.label.slice(0, 24).padEnd(24),
			r.blz.padEnd(8),
			yn(r.endpoint_ok).padEnd(8),
			yn(r.bpd_ok).padEnd(4),
			yn(r.structural_ok).padEnd(6),
			hikaz.slice(0, 8).padEnd(8),
			yn(r.has_hicazs).padEnd(6),
			tan.slice(0, 18).padEnd(18),
			codes.slice(0, 20).padEnd(20),
			r.variant.slice(0, 10).padEnd(10),
		];
		console.log(row.join("  "));
		if (r.error) console.log(`    error: ${r.error}`);
		console.log(`    url: ${r.url}`);
	}
}

// --- Main ---

const args = process.argv.slice(2);
let timeoutS = 15;
let tryHksyn = false;
let jsonOut = "scripts/bank-matrix-last.json";

for (let i = 0; i < args.length; i++) {
	if (args[i] === "--timeout" && args[i + 1]) {
		timeoutS = Number(args[++i]);
	} else if (args[i] === "--try-hksyn-variant") {
		tryHksyn = true;
	} else if (args[i] === "--json-out" && args[i + 1]) {
		jsonOut = args[++i];
	}
}

const repoRoot = resolve(dirname(new URL(import.meta.url).pathname), "..");
const banksPath = resolve(repoRoot, "libwimg/src/banks.zig");
const banksByBlz = parseBanksZig(banksPath);
const targets = buildTargetList(banksByBlz);

console.log(`Running anonymous FinTS probes for ${targets.length} banks (timeout=${timeoutS.toFixed(1)}s)\n`);

const results: ProbeResult[] = [];
for (const [label, bank] of targets) {
	process.stdout.write(`- probing ${label} (${bank.blz}) ...\n`);
	const primary = await sendAnonymousProbe(
		{ ...bank, name: label },
		timeoutS * 1000,
		"anon",
	);
	let chosen = primary;
	if (tryHksyn && (!primary.bpd_ok || !primary.structural_ok)) {
		process.stdout.write("  -> trying anon_hksyn variant ...\n");
		const secondary = await sendAnonymousProbe(
			{ ...bank, name: label },
			timeoutS * 1000,
			"anon_hksyn",
		);
		chosen = chooseBetterResult(primary, secondary);
	}
	results.push(chosen);
}

console.log();
printMatrix(results);

const endpointOk = results.filter((r) => r.endpoint_ok).length;
const bpdOk = results.filter((r) => r.bpd_ok).length;
const structuralOk = results.filter((r) => r.structural_ok).length;
console.log(
	`\nSummary: endpoint_ok=${endpointOk}/${results.length}, bpd_ok=${bpdOk}/${results.length}, structural_ok=${structuralOk}/${results.length}`,
);

const payload = {
	summary: {
		count: results.length,
		endpoint_ok: endpointOk,
		bpd_ok: bpdOk,
		structural_ok: structuralOk,
		timeout_seconds: timeoutS,
	},
	results,
};

const outPath = resolve(repoRoot, jsonOut);
mkdirSync(dirname(outPath), { recursive: true });
writeFileSync(outPath, JSON.stringify(payload, null, 2));
console.log(`JSON report written: ${outPath}`);
